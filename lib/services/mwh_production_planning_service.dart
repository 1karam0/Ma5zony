import 'dart:math';

import 'package:ma5zony/models/demand_record.dart';
import 'package:ma5zony/models/forecast_result.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/services/demand_aggregation_service.dart';
import 'package:ma5zony/services/forecasting_service.dart';
import 'package:ma5zony/services/spp_inventory_service.dart';

/// MWH (Makridakis–Wheelwright–Hyndman) Production-Planning Service.
///
/// Reference:
///   Makridakis, S., Wheelwright, S. C., & Hyndman, R. J. (1998/2008).
///   *Forecasting: Methods and Applications*.
///
/// The Ma5zony `ForecastingService` already implements every algorithm
/// recommended by MWH (SMA, WMA, SES, Holt's linear trend, Holt-Winters
/// seasonal) and selects the lowest-MAPE candidate via
/// `autoSelectBestForecast`. What was missing — and what this service adds —
/// is the business-facing wrapper that MWH describes in Chapter 9:
///
///   Forecasted demand for chosen horizon
///     + Minimum stock requirement (from SPP)
///     − Current stock
///     = Recommended production quantity
///
/// plus a confidence bucket (High / Medium / Low) derived from MAPE, and a
/// plain-language reason for the recommendation.
///
/// This service does not duplicate any existing logic — it composes
/// `DemandAggregationService`, `ForecastingService`, and `SppInventoryService`.
class MwhProductionPlanningService {
  final DemandAggregationService _aggregator;
  final ForecastingService _forecaster;
  final SppInventoryService _spp;

  MwhProductionPlanningService({
    DemandAggregationService? aggregator,
    ForecastingService? forecaster,
    SppInventoryService? spp,
  })  : _aggregator = aggregator ?? DemandAggregationService(),
        _forecaster = forecaster ?? ForecastingService(),
        _spp = spp ?? SppInventoryService();

  /// Computes the production recommendation for a single product over a
  /// user-selected coverage period.
  ///
  /// [coverageDays] = how many days forward the user wants to be covered
  ///                  (typical SME values: 30, 60, 90).
  /// [growthAdjustment] = optional extra multiplier (e.g. 0.10 for +10 % to
  ///                  account for a known promo). Defaults to 0.0.
  MwhProductionPlan plan({
    required Product product,
    required List<DomainDemandRecord> demandHistory,
    required int coverageDays,
    int? supplierLeadTimeDays,
    int productionTimeDays = 0,
    double growthAdjustment = 0.0,
    double serviceLevelPercent = 95,
    DateTime? now,
  }) {
    // Get the SPP minimum stock first — production must keep us above it.
    final spp = _spp.compute(
      product: product,
      demandHistory: demandHistory,
      supplierLeadTimeDays: supplierLeadTimeDays,
      productionTimeDays: productionTimeDays,
      serviceLevelPercent: serviceLevelPercent,
      now: now,
    );

    // Aggregate to monthly buckets — MWH recommends this resolution for
    // small-business demand because daily data is too noisy and yearly is
    // too coarse (Chapter 2: choosing the time bucket).
    final monthly = _aggregator.fillMissingPeriods(
      _aggregator.aggregateToMonthly(demandHistory),
    );
    final series = _aggregator.toSeries(monthly);
    final periods = _aggregator.toPeriods(monthly);

    if (series.length < 3) {
      // MWH §2.5: with <3 observations, no statistical forecast is
      // defensible. Fall back to the SPP daily average × coverage period.
      final fallback =
          (spp.averageDailyDemand * coverageDays * (1 + growthAdjustment))
              .round();
      final required = max(0, fallback + spp.minimumStock - product.currentStock);
      return MwhProductionPlan(
        productId: product.id,
        productName: product.name,
        coverageDays: coverageDays,
        forecastedDemand: fallback,
        currentStock: product.currentStock,
        minimumStock: spp.minimumStock,
        recommendedProductionQty: required,
        algorithmUsed: 'naive (insufficient history)',
        confidence: MwhConfidence.low,
        forecastResult: null,
        reason: required == 0
            ? '${product.name} has very little sales history. Current stock '
                'already covers the next $coverageDays days at the recent pace, '
                'so no production is needed right now.'
            : 'Sales history is too short for a statistical forecast. Based on '
                'the current daily run-rate, you would need roughly $required '
                'units to cover $coverageDays days plus the safety floor.',
      );
    }

    // Run the MWH algorithm contest and pick the lowest-MAPE candidate.
    final result = _forecaster.autoSelectBestForecast(
      productId: product.id,
      periods: periods,
      demand: series,
      leadTimeDays: 0,
      serviceLevelZ: SppInventoryService.serviceLevelToZ(serviceLevelPercent),
    );

    // The forecast is per *month* (the aggregation bucket). Convert to the
    // user's coverage window.
    final monthlyForecast = (result.forecast.isNotEmpty)
        ? result.forecast.last
        : (series.reduce((a, b) => a + b) / series.length);
    final dailyForecast = monthlyForecast / 30.0;
    final coverageDemand =
        (dailyForecast * coverageDays * (1 + growthAdjustment)).round();

    final required =
        max(0, coverageDemand + spp.minimumStock - product.currentStock);

    final confidence = _confidenceFromMape(result.mape);

    return MwhProductionPlan(
      productId: product.id,
      productName: product.name,
      coverageDays: coverageDays,
      forecastedDemand: coverageDemand,
      currentStock: product.currentStock,
      minimumStock: spp.minimumStock,
      recommendedProductionQty: required,
      algorithmUsed: result.algorithm,
      confidence: confidence,
      forecastResult: result,
      reason: _reason(
        product: product,
        coverageDays: coverageDays,
        coverageDemand: coverageDemand,
        currentStock: product.currentStock,
        minimumStock: spp.minimumStock,
        required: required,
        algorithm: result.algorithm,
        confidence: confidence,
      ),
    );
  }

  /// Convenience: run the plan for every product the user owns.
  List<MwhProductionPlan> planForCatalog({
    required List<Product> products,
    required Map<String, List<DomainDemandRecord>> demandByProduct,
    required int coverageDays,
    Map<String, int?> supplierLeadTimes = const {},
    Map<String, int> productionTimes = const {},
    double growthAdjustment = 0.0,
    double serviceLevelPercent = 95,
    DateTime? now,
  }) {
    return products
        .where((p) => p.isActive)
        .map(
          (p) => plan(
            product: p,
            demandHistory: demandByProduct[p.id] ?? const [],
            coverageDays: coverageDays,
            supplierLeadTimeDays: supplierLeadTimes[p.id],
            productionTimeDays: productionTimes[p.id] ?? 0,
            growthAdjustment: growthAdjustment,
            serviceLevelPercent: serviceLevelPercent,
            now: now,
          ),
        )
        .toList();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// MWH Chapter 2: classify forecast accuracy by MAPE bands.
  ///   < 10 %  → highly accurate
  ///   10–20 % → good
  ///   20–50 % → reasonable
  ///   > 50 %  → inaccurate
  MwhConfidence _confidenceFromMape(double? mape) {
    if (mape == null || mape.isNaN || mape.isInfinite) return MwhConfidence.low;
    if (mape < 15) return MwhConfidence.high;
    if (mape < 35) return MwhConfidence.medium;
    return MwhConfidence.low;
  }

  String _reason({
    required Product product,
    required int coverageDays,
    required int coverageDemand,
    required int currentStock,
    required int minimumStock,
    required int required,
    required String algorithm,
    required MwhConfidence confidence,
  }) {
    final confidenceWord = switch (confidence) {
      MwhConfidence.high => 'high',
      MwhConfidence.medium => 'medium',
      MwhConfidence.low => 'low',
    };

    if (required == 0) {
      return 'Current stock of $currentStock units already covers the next '
          '$coverageDays days of expected demand ($coverageDemand) plus the '
          'minimum safety floor of $minimumStock. No production needed now. '
          '(Forecast: $algorithm, $confidenceWord confidence.)';
    }

    return 'To cover the next $coverageDays days the system expects demand of '
        '$coverageDemand units. Current stock is $currentStock and the minimum '
        'required is $minimumStock, so the recommended production is $required '
        'units. (Forecast: $algorithm, $confidenceWord confidence.)';
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Result objects
// ════════════════════════════════════════════════════════════════════════════

enum MwhConfidence { high, medium, low }

class MwhProductionPlan {
  final String productId;
  final String productName;
  final int coverageDays;
  final int forecastedDemand;
  final int currentStock;
  final int minimumStock;
  final int recommendedProductionQty;
  final String algorithmUsed;
  final MwhConfidence confidence;
  final ForecastResult? forecastResult;
  final String reason;

  const MwhProductionPlan({
    required this.productId,
    required this.productName,
    required this.coverageDays,
    required this.forecastedDemand,
    required this.currentStock,
    required this.minimumStock,
    required this.recommendedProductionQty,
    required this.algorithmUsed,
    required this.confidence,
    required this.forecastResult,
    required this.reason,
  });
}

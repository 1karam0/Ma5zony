import 'package:ma5zony/models/demand_record.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/replenishment_recommendation.dart';
import 'package:ma5zony/models/supplier.dart';
import 'package:ma5zony/services/abc_xyz_service.dart';
import 'package:ma5zony/services/demand_aggregation_service.dart';
import 'package:ma5zony/services/forecasting_service.dart';
import 'package:ma5zony/services/inventory_policy_service.dart';
import 'package:ma5zony/services/settings_service.dart';

/// Builds replenishment recommendations by orchestrating the full pipeline:
///
///   Demand Data → Aggregation → Forecasting → Inventory Policy → Recommendation
///
/// Uses [ForecastingService] for demand prediction, [InventoryPolicyService]
/// for EOQ/ROP/Safety Stock, and optionally [AbcXyzService] for priority
/// classification.
class ReplenishmentService {
  final ForecastingService _forecastingService;
  final InventoryPolicyService _policyService;
  final DemandAggregationService _aggregationService;
  final AbcXyzService _abcXyzService;

  ReplenishmentService({
    ForecastingService? forecastingService,
    InventoryPolicyService? policyService,
    DemandAggregationService? aggregationService,
    AbcXyzService? abcXyzService,
  })  : _forecastingService = forecastingService ?? ForecastingService(),
        _policyService = policyService ?? InventoryPolicyService(),
        _aggregationService =
            aggregationService ?? DemandAggregationService(),
        _abcXyzService = abcXyzService ?? AbcXyzService();

  /// Maps a service-level percentage (e.g. 95) to its Z-score.
  static double serviceLevelToZ(double serviceLevelPercent) {
    if (serviceLevelPercent >= 99) return 2.33;
    if (serviceLevelPercent >= 97.5) return 1.96;
    if (serviceLevelPercent >= 95) return 1.65;
    if (serviceLevelPercent >= 90) return 1.28;
    if (serviceLevelPercent >= 85) return 1.04;
    if (serviceLevelPercent >= 80) return 0.84;
    return 0.67;
  }

  /// Generates [ReplenishmentRecommendation] objects for products whose
  /// current stock is at or below the computed reorder point.
  ///
  /// **Key enhancement**: Uses the forecasting pipeline to predict demand
  /// (via auto-select or specified algorithm) and feeds forecasted demand
  /// into the inventory policy calculations, rather than using a simple
  /// SMA(3) as before.
  List<ReplenishmentRecommendation> buildRecommendations({
    required List<Product> products,
    required Map<String, List<DomainDemandRecord>> demandByProduct,
    required Map<String, Supplier> suppliers,
    UserSettings? settings,
    String? forceAlgorithm,
  }) {
    final recommendations = <ReplenishmentRecommendation>[];
    final serviceLevelZ = settings != null
        ? serviceLevelToZ(settings.serviceLevelTarget)
        : 1.65;

    // Optional: compute ABC-XYZ classification for sorting priority
    Map<String, ProductClassification>? classifications;
    try {
      classifications = _abcXyzService.buildMatrix(
        products: products,
        demandByProduct: demandByProduct,
      );
    } catch (_) {
      // If classification fails, continue without it
    }

    for (final product in products) {
      final records = demandByProduct[product.id] ?? [];
      if (records.isEmpty) continue;

      // ── Step 1: Aggregate demand into monthly series ──────────────────
      final monthly = _aggregationService.aggregateToMonthly(records);
      final filled = _aggregationService.fillMissingPeriods(monthly);
      final demandSeries = _aggregationService.toSeries(filled);
      final periods = _aggregationService.toPeriods(filled);

      if (demandSeries.isEmpty) continue;

      // ── Step 2: Run forecast using best algorithm (or forced) ─────────
      final classification = classifications?[product.id];
      final algorithm =
          forceAlgorithm ?? classification?.recommendedAlgorithm ?? 'SMA';

      final supplier =
          (product.supplierId != null &&
                  suppliers.containsKey(product.supplierId))
              ? suppliers[product.supplierId]!
              : Supplier(
                  id: '_default',
                  name: 'Default',
                  contactEmail: '',
                  typicalLeadTimeDays: 7,
                );

      final effectiveLeadTimeDays = product.leadTimeDays > 0
          ? product.leadTimeDays
          : supplier.typicalLeadTimeDays;

      final forecastResult = _forecastingService.generateForecast(
        productId: product.id,
        periods: periods,
        demand: demandSeries,
        algorithm: algorithm,
        leadTimeDays: effectiveLeadTimeDays,
        serviceLevelZ: serviceLevelZ,
      );

      final forecastedDemand = forecastResult.nextPeriodForecast;

      // ── Step 3: Compute inventory policy using forecasted demand ──────
      final policy = _policyService.buildPolicy(
        product: product,
        demandSeries: demandSeries,
        supplier: supplier,
        serviceLevelZ: serviceLevelZ,
        forecastedDemandPerPeriod: forecastedDemand,
      );

      // ── Step 4: Generate recommendation if stock ≤ ROP ────────────────
      if (product.currentStock <= policy.reorderPoint) {
        final suggestedQty = policy.eoq.ceil().clamp(1, 99999);

        // Compute timing: when to order based on days of stock remaining
        final avgDailyDemand = forecastedDemand / 30.0;
        final daysOfStockLeft = avgDailyDemand > 0
            ? (product.currentStock / avgDailyDemand).floor()
            : 0;
        final latestOrderDay = daysOfStockLeft - effectiveLeadTimeDays;
        final orderInDays = latestOrderDay > 1 ? latestOrderDay : 1;

        // Determine urgency
        final urgency = _computeUrgency(
          currentStock: product.currentStock,
          reorderPoint: policy.reorderPoint,
          daysOfStockLeft: daysOfStockLeft,
          leadTimeDays: effectiveLeadTimeDays,
        );

        recommendations.add(
          ReplenishmentRecommendation(
            productId: product.id,
            productName: product.name,
            sku: product.sku,
            currentStock: product.currentStock,
            forecastNextPeriod: forecastedDemand.toInt(),
            reorderPoint: policy.reorderPoint,
            suggestedOrderQty: suggestedQty,
            recommendedOrderDate: DateTime.now().add(
              Duration(days: orderInDays),
            ),
            urgency: urgency,
            abcXyzClass: classification?.label,
            algorithmUsed: algorithm,
            safetyStock: policy.safetyStock,
            eoq: policy.eoq,
          ),
        );
      }
    }

    // Sort: Critical first, then Warning, then Normal; within each
    // group sort by ABC class (A before B before C)
    recommendations.sort((a, b) {
      final urgencyOrder = {
        'Critical': 0,
        'Warning': 1,
        'Normal': 2,
      };
      final ua = urgencyOrder[a.urgency] ?? 2;
      final ub = urgencyOrder[b.urgency] ?? 2;
      if (ua != ub) return ua.compareTo(ub);
      return a.currentStock.compareTo(b.currentStock);
    });

    return recommendations;
  }

  /// Determines urgency level based on stock and lead time.
  static String _computeUrgency({
    required int currentStock,
    required int reorderPoint,
    required int daysOfStockLeft,
    required int leadTimeDays,
  }) {
    if (currentStock == 0) return 'Critical';
    if (daysOfStockLeft <= leadTimeDays) return 'Critical';
    if (daysOfStockLeft <= leadTimeDays * 1.5) return 'Warning';
    return 'Normal';
  }
}

import 'dart:math';
import 'package:ma5zony/models/inventory_policy.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/supplier.dart';

/// Pure-Dart inventory policy calculator.
///
/// Implements the classical inventory control formulas from
/// Silver, Pyke & Peterson and Chopra & Meindl:
///   - Economic Order Quantity (EOQ)
///   - Safety Stock
///   - Reorder Point (ROP)
///   - Total Relevant Cost (TRC)
///   - Order Cycle Time
///
/// All methods accept either historical demand or forecasted demand
/// so that forecasts can be piped directly into policy calculations.
class InventoryPolicyService {
  // ── EOQ ────────────────────────────────────────────────────────────────────

  /// Classical Economic Order Quantity formula: √((2 × D × S) / H)
  ///
  /// [annualDemand] = D (units/year)
  /// [orderCost]    = S ($/order — fixed cost per replenishment order)
  /// [holdingCost]  = H ($/unit/year — cost to hold one unit for one year)
  double computeEoq({
    required double annualDemand,
    required double orderCost,
    required double holdingCost,
  }) {
    if (holdingCost <= 0 || annualDemand <= 0) return 0;
    return sqrt((2 * annualDemand * orderCost) / holdingCost);
  }

  // ── Safety Stock ───────────────────────────────────────────────────────────

  /// Safety stock = σ_demand × √(LT_periods) × Z
  ///
  /// [demandStdDevPerPeriod] = standard deviation of demand per period
  /// [leadTimeInPeriods]     = supplier lead time in demand periods
  /// [serviceLevelZ]         = z-score for desired service level
  ///                           (1.28 = 90%, 1.65 = 95%, 1.96 = 97.5%, 2.33 = 99%)
  int computeSafetyStock({
    required double demandStdDevPerPeriod,
    required double leadTimeInPeriods,
    required double serviceLevelZ,
  }) {
    return (demandStdDevPerPeriod * sqrt(leadTimeInPeriods) * serviceLevelZ)
        .round();
  }

  // ── Reorder Point ─────────────────────────────────────────────────────────

  /// ROP = (avg_demand × LT_periods) + safety_stock
  ///
  /// Can accept either historical average or forecasted demand per period.
  int computeReorderPoint({
    required double averageDemandPerPeriod,
    required double leadTimeInPeriods,
    required int safetyStock,
  }) {
    return (averageDemandPerPeriod * leadTimeInPeriods).round() + safetyStock;
  }

  // ── Total Relevant Cost ───────────────────────────────────────────────────

  /// TRC = (D/Q × S) + (Q/2 × H)
  ///
  /// Annual ordering cost + annual holding cost.
  /// At EOQ, these two components are equal (TRC is minimised).
  TotalRelevantCost computeTotalCost({
    required double annualDemand,
    required double orderQuantity,
    required double orderCost,
    required double holdingCost,
  }) {
    if (orderQuantity <= 0) {
      return TotalRelevantCost(orderingCost: 0, holdingCost: 0, totalCost: 0);
    }
    final ordCost = (annualDemand / orderQuantity) * orderCost;
    final hldCost = (orderQuantity / 2) * holdingCost;
    return TotalRelevantCost(
      orderingCost: ordCost,
      holdingCost: hldCost,
      totalCost: ordCost + hldCost,
    );
  }

  // ── Order Cycle Time ──────────────────────────────────────────────────────

  /// Days between orders = (EOQ / annual_demand) × 365
  double computeOrderCycleTimeDays({
    required double eoq,
    required double annualDemand,
  }) {
    if (annualDemand <= 0) return 0;
    return (eoq / annualDemand) * 365;
  }

  /// Number of orders per year = D / Q
  double computeOrdersPerYear({
    required double annualDemand,
    required double orderQuantity,
  }) {
    if (orderQuantity <= 0) return 0;
    return annualDemand / orderQuantity;
  }

  // ── Policy Builder ────────────────────────────────────────────────────────

  /// Builds a complete [InventoryPolicy] from a product, its demand series
  /// and its supplier.
  ///
  /// Can accept either:
  ///   1. Historical demand series (monthly units sold)
  ///   2. Forecasted demand for next period (via [forecastedDemandPerPeriod])
  ///
  /// When [forecastedDemandPerPeriod] is provided, it overrides the
  /// historical average for EOQ/ROP calculations — this connects the
  /// forecasting pipeline to inventory policy as required by the system design.
  ///
  /// Defaults:
  /// - orderingCost = 50 USD/order
  /// - holdingRate = 20% of unit cost per year
  /// - serviceLevelZ = 1.65 (≈ 95% service level)
  /// - leadTimeInPeriods = supplier.typicalLeadTimeDays / 30
  InventoryPolicy buildPolicy({
    required Product product,
    required List<double> demandSeries,
    required Supplier supplier,
    double orderingCost = 50.0,
    double holdingRate = 0.20,
    double serviceLevelZ = 1.65,
    double? forecastedDemandPerPeriod,
  }) {
    if (demandSeries.isEmpty) {
      return InventoryPolicy(
        productId: product.id,
        eoq: 0,
        reorderPoint: 0,
        safetyStock: 0,
        annualDemand: 0,
        orderingCost: orderingCost,
        holdingCost: product.unitCost * holdingRate,
      );
    }

    // Use forecasted demand if available, otherwise historical average
    final double avg =
        demandSeries.reduce((a, b) => a + b) / demandSeries.length;
    final double demandPerPeriod = forecastedDemandPerPeriod ?? avg;
    final double annualDemand = demandPerPeriod * 12;
    final double holdingCost = product.unitCost * holdingRate;
    final double leadTimeInPeriods = supplier.typicalLeadTimeDays / 30.0;

    // Standard deviation (always from historical data for variability measure)
    final double variance =
        demandSeries.map((d) => (d - avg) * (d - avg)).reduce((a, b) => a + b) /
        demandSeries.length;
    final double stdDev = sqrt(variance);

    final int safetyStock = computeSafetyStock(
      demandStdDevPerPeriod: stdDev,
      leadTimeInPeriods: leadTimeInPeriods,
      serviceLevelZ: serviceLevelZ,
    );

    final int rop = computeReorderPoint(
      averageDemandPerPeriod: demandPerPeriod,
      leadTimeInPeriods: leadTimeInPeriods,
      safetyStock: safetyStock,
    );

    final double eoq = computeEoq(
      annualDemand: annualDemand,
      orderCost: orderingCost,
      holdingCost: holdingCost,
    );

    return InventoryPolicy(
      productId: product.id,
      eoq: eoq,
      reorderPoint: rop,
      safetyStock: safetyStock,
      annualDemand: annualDemand,
      orderingCost: orderingCost,
      holdingCost: holdingCost,
    );
  }
}

/// Breakdown of total relevant inventory cost.
class TotalRelevantCost {
  final double orderingCost;
  final double holdingCost;
  final double totalCost;

  const TotalRelevantCost({
    required this.orderingCost,
    required this.holdingCost,
    required this.totalCost,
  });
}

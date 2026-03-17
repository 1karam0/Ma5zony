import 'dart:math';
import 'package:ma5zony/models/inventory_policy.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/supplier.dart';

/// Pure-Dart inventory policy calculator. No Flutter dependencies.
class InventoryPolicyService {
  // ── EOQ ────────────────────────────────────────────────────────────────────

  /// Classical Economic Order Quantity formula: sqrt((2 * D * S) / H)
  /// [annualDemand] = D, [orderCost] = S, [holdingCost] = H (per unit per year)
  double computeEoq({
    required double annualDemand,
    required double orderCost,
    required double holdingCost,
  }) {
    if (holdingCost <= 0) return 0;
    return sqrt((2 * annualDemand * orderCost) / holdingCost);
  }

  // ── Safety Stock ───────────────────────────────────────────────────────────

  /// Safety stock = demandStdDevPerPeriod × √leadTimeInPeriods × serviceLevelZ
  int computeSafetyStock({
    required double demandStdDevPerPeriod,
    required double leadTimeInPeriods,
    required double serviceLevelZ,
  }) {
    return (demandStdDevPerPeriod * sqrt(leadTimeInPeriods) * serviceLevelZ)
        .round();
  }

  // ── Reorder Point ─────────────────────────────────────────────────────────

  /// ROP = (averageDemandPerPeriod × leadTimeInPeriods) + safetyStock
  int computeReorderPoint({
    required double averageDemandPerPeriod,
    required double leadTimeInPeriods,
    required int safetyStock,
  }) {
    return (averageDemandPerPeriod * leadTimeInPeriods).round() + safetyStock;
  }

  // ── Policy Builder ────────────────────────────────────────────────────────

  /// Builds a complete [InventoryPolicy] from a product, its monthly demand
  /// series and its supplier.
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

    final double avg =
        demandSeries.reduce((a, b) => a + b) / demandSeries.length;
    final double annualDemand = avg * 12;
    final double holdingCost = product.unitCost * holdingRate;
    final double leadTimeInPeriods = supplier.typicalLeadTimeDays / 30.0;

    // Standard deviation
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
      averageDemandPerPeriod: avg,
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

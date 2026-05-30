import 'dart:math';

import 'package:ma5zony/models/bill_of_materials.dart';
import 'package:ma5zony/models/demand_record.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/raw_material.dart';
import 'package:ma5zony/services/replenishment_service.dart';
import 'package:ma5zony/services/settings_service.dart';

/// Computed reorder point for a single raw material, derived from the demand
/// of every finished product that consumes it (via its active BOM).
class RawMaterialStockResult {
  final String rawMaterialId;

  /// Average units of this material consumed per day across all products.
  final double dailyConsumption;

  /// Lead time used in the calculation (material lead time, or a 7-day
  /// fallback when none is configured).
  final int leadTimeDays;

  /// Buffer to absorb demand variability during the lead time.
  final int safetyStock;

  /// Reorder point = expected consumption during lead time + safety stock.
  /// This is the level at which a new purchase should be triggered.
  final int reorderPoint;

  /// Whether enough connected data (demand + BOM linkage) existed to compute
  /// a meaningful figure. When false, callers should keep any manual value.
  final bool hasData;

  RawMaterialStockResult({
    required this.rawMaterialId,
    required this.dailyConsumption,
    required this.leadTimeDays,
    required this.safetyStock,
    required this.reorderPoint,
    required this.hasData,
  });
}

/// Calculates raw-material reorder points automatically by exploding finished
/// product demand through each product's active Bill of Materials.
///
/// Raw-material demand is a *derived* quantity: a material is only consumed
/// when the products that use it are built. So the reorder point is:
///
///   reorderPoint = (Σ productDailyDemand × qtyPerUnit) × leadTime + safetyStock
///
/// This removes the need for the user to hand-enter a safety-stock figure —
/// once products, demand history and BOMs are set up, the value is computed.
class RawMaterialStockService {
  /// Computes reorder points for every raw material.
  Map<String, RawMaterialStockResult> computeAll({
    required List<RawMaterial> rawMaterials,
    required List<Product> products,
    required List<BillOfMaterials> boms,
    required Map<String, List<DomainDemandRecord>> demandByProduct,
    UserSettings? settings,
  }) {
    final serviceLevelZ = settings != null
        ? ReplenishmentService.serviceLevelToZ(settings.serviceLevelTarget)
        : 1.65;

    // Pre-compute per-product daily demand mean & standard deviation once.
    final productStats = <String, _ProductDemandStats>{};
    for (final product in products) {
      final records = demandByProduct[product.id] ?? const [];
      productStats[product.id] = _ProductDemandStats.fromRecords(records);
    }

    // Index active BOMs by finished product id.
    final activeBomByProduct = <String, BillOfMaterials>{};
    for (final bom in boms) {
      if (bom.isActive) activeBomByProduct[bom.finalProductId] = bom;
    }

    final results = <String, RawMaterialStockResult>{};
    for (final rm in rawMaterials) {
      double dailyConsumption = 0;
      // Combine per-product safety contributions assuming independence:
      // total variance = Σ (qtyPerUnit × dailyStdDev)².
      double safetyVariance = 0;

      for (final entry in activeBomByProduct.entries) {
        final bom = entry.value;
        final stats = productStats[entry.key];
        if (stats == null || !stats.hasData) continue;

        for (final line in bom.materials) {
          if (line.kind != BomComponentKind.rawMaterial) continue;
          if (line.refId != rm.id) continue;
          final qtyPerUnit = line.effectiveQuantityPerUnit;
          dailyConsumption += stats.dailyMean * qtyPerUnit;
          final contrib = qtyPerUnit * stats.dailyStdDev;
          safetyVariance += contrib * contrib;
        }
      }

      if (dailyConsumption <= 0) {
        results[rm.id] = RawMaterialStockResult(
          rawMaterialId: rm.id,
          dailyConsumption: 0,
          leadTimeDays: rm.leadTimeDays,
          safetyStock: rm.safetyStock,
          reorderPoint: rm.safetyStock,
          hasData: false,
        );
        continue;
      }

      final leadTime = rm.leadTimeDays > 0 ? rm.leadTimeDays : 7;
      final combinedStdDev = sqrt(safetyVariance);
      final safetyStock =
          (serviceLevelZ * combinedStdDev * sqrt(leadTime.toDouble())).ceil();
      final cycleStock = (dailyConsumption * leadTime).ceil();
      final reorderPoint = cycleStock + safetyStock;

      results[rm.id] = RawMaterialStockResult(
        rawMaterialId: rm.id,
        dailyConsumption: dailyConsumption,
        leadTimeDays: leadTime,
        safetyStock: safetyStock,
        reorderPoint: reorderPoint,
        hasData: true,
      );
    }
    return results;
  }
}

/// Daily demand mean / standard deviation derived from a product's demand
/// records, normalised to a per-day basis so it can be combined across the
/// raw material's lead time.
class _ProductDemandStats {
  final double dailyMean;
  final double dailyStdDev;
  final bool hasData;

  const _ProductDemandStats({
    required this.dailyMean,
    required this.dailyStdDev,
    required this.hasData,
  });

  factory _ProductDemandStats.fromRecords(List<DomainDemandRecord> records) {
    if (records.isEmpty) {
      return const _ProductDemandStats(
          dailyMean: 0, dailyStdDev: 0, hasData: false);
    }

    final sorted = List<DomainDemandRecord>.from(records)
      ..sort((a, b) => a.periodStart.compareTo(b.periodStart));

    final spanDays =
        sorted.last.periodStart.difference(sorted.first.periodStart).inDays.abs();
    final windowDays = max(spanDays, 30);
    final totalDemand = sorted.fold<double>(0, (s, r) => s + r.quantity);
    final dailyMean = totalDemand / windowDays;

    if (dailyMean <= 0) {
      return const _ProductDemandStats(
          dailyMean: 0, dailyStdDev: 0, hasData: false);
    }

    // Standard deviation of per-record demand, converted to a daily figure by
    // dividing by the average record span (records are typically monthly).
    final recordMean = totalDemand / sorted.length;
    final variance = sorted.fold<double>(
            0, (s, r) => s + pow(r.quantity - recordMean, 2).toDouble()) /
        sorted.length;
    final recordStdDev = sqrt(variance);
    final avgRecordSpanDays = max(windowDays / sorted.length, 1);
    final dailyStdDev = recordStdDev / avgRecordSpanDays;

    return _ProductDemandStats(
      dailyMean: dailyMean,
      dailyStdDev: dailyStdDev,
      hasData: true,
    );
  }
}

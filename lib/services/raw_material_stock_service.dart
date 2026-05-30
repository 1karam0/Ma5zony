import 'dart:math';

import 'package:ma5zony/models/bill_of_materials.dart';
import 'package:ma5zony/models/demand_record.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/raw_material.dart';
import 'package:ma5zony/services/replenishment_service.dart';
import 'package:ma5zony/services/settings_service.dart';

/// Reorder result for one raw material.
class RawMaterialStockResult {
  final String rawMaterialId;

  // avg units used per day across all products
  final double dailyConsumption;

  // material lead time, or 7 if not set
  final int leadTimeDays;

  final int safetyStock;

  // reorder when stock hits this level
  final int reorderPoint;

  // false when there's no demand/BOM data yet
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

/// Works out raw-material reorder points from product demand and BOMs.
/// A material is only used when its products are built, so:
///   reorderPoint = (sum of product daily demand * qty per unit) * leadTime + safety
/// This way the user doesn't have to type a safety-stock number by hand.
class RawMaterialStockService {
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

    // daily demand mean + std dev per product
    final productStats = <String, _ProductDemandStats>{};
    for (final product in products) {
      final records = demandByProduct[product.id] ?? const [];
      productStats[product.id] = _ProductDemandStats.fromRecords(records);
    }

    // active BOM per product
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

/// Daily demand mean and std dev for one product.
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

    // std dev of demand per record, turned into a daily number
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

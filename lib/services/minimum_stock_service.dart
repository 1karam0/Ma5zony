import 'dart:math';
import 'package:ma5zony/models/bill_of_materials.dart';
import 'package:ma5zony/models/demand_record.dart';
import 'package:ma5zony/models/manufacturer.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/raw_material.dart';
import 'package:ma5zony/models/supplier.dart';
import 'package:ma5zony/services/replenishment_service.dart';
import 'package:ma5zony/services/settings_service.dart';

class MinimumStockResult {
  final String productId;
  final String productName;
  final String sku;
  final double averageDailySales;
  final int rmLeadTimeDays;
  final int manufacturingDays;
  final int totalLeadTimeDays;
  final int safetyStock;
  final int minimumStock;
  final double daysOfStockLeft;
  final bool isUrgent;
  final int currentStock;

  MinimumStockResult({
    required this.productId,
    required this.productName,
    required this.sku,
    required this.averageDailySales,
    required this.rmLeadTimeDays,
    required this.manufacturingDays,
    required this.totalLeadTimeDays,
    required this.safetyStock,
    required this.minimumStock,
    required this.daysOfStockLeft,
    required this.isUrgent,
    required this.currentStock,
  });
}

class MinimumStockService {
  /// Computes minimum stock requirements for a single product.
  MinimumStockResult? computeForProduct({
    required Product product,
    required List<DomainDemandRecord> demandRecords,
    required List<BillOfMaterials> boms,
    required List<RawMaterial> rawMaterials,
    required List<Supplier> suppliers,
    required List<Manufacturer> manufacturers,
    UserSettings? settings,
  }) {
    if (demandRecords.isEmpty) return null;

    // ── Average daily sales ─────────────────────────────────────────────
    final sorted = List<DomainDemandRecord>.from(demandRecords)
      ..sort((a, b) => a.periodStart.compareTo(b.periodStart));

    final earliest = sorted.first.periodStart;
    final latest = sorted.last.periodStart;
    final spanDays = latest.difference(earliest).inDays.abs();
    final windowDays = max(spanDays, 30);
    final totalDemand = sorted.fold<double>(0, (s, r) => s + r.quantity);
    final averageDailySales = totalDemand / windowDays;

    if (averageDailySales <= 0) return null;

    // ── Lead times ──────────────────────────────────────────────────────
    final activeBom = boms
        .where((b) => b.finalProductId == product.id && b.isActive)
        .toList();

    int rmLeadTimeDays = 0;
    if (activeBom.isNotEmpty) {
      final bom = activeBom.first;
      for (final line in bom.materials) {
        final rm = rawMaterials.where((r) => r.id == line.rawMaterialId).firstOrNull;
        if (rm != null && rm.leadTimeDays > rmLeadTimeDays) {
          rmLeadTimeDays = rm.leadTimeDays;
        }
      }
    }

    final manufacturingDays = product.leadTimeDays;
    final totalLeadTimeDays = rmLeadTimeDays + manufacturingDays;
    final effectiveLead = totalLeadTimeDays > 0 ? totalLeadTimeDays : 7;

    // ── Safety stock ────────────────────────────────────────────────────
    final serviceLevelZ = settings != null
        ? ReplenishmentService.serviceLevelToZ(settings.serviceLevelTarget)
        : 1.65;

    // Demand std dev (over the recorded periods)
    final mean = totalDemand / sorted.length;
    final variance = sorted.fold<double>(
            0, (s, r) => s + pow(r.quantity - mean, 2)) /
        sorted.length;
    final stdDev = sqrt(variance);
    final safetyStock =
        (serviceLevelZ * stdDev * sqrt(effectiveLead.toDouble())).ceil();

    // ── Minimum stock ───────────────────────────────────────────────────
    final cycleStock = (averageDailySales * effectiveLead).ceil();
    final minimumStock = cycleStock + safetyStock;

    // ── Days of stock left ──────────────────────────────────────────────
    final daysOfStockLeft = product.currentStock / averageDailySales;
    final isUrgent = product.currentStock < minimumStock;

    return MinimumStockResult(
      productId: product.id,
      productName: product.name,
      sku: product.sku,
      averageDailySales: averageDailySales,
      rmLeadTimeDays: rmLeadTimeDays,
      manufacturingDays: manufacturingDays,
      totalLeadTimeDays: effectiveLead,
      safetyStock: safetyStock,
      minimumStock: minimumStock,
      daysOfStockLeft: daysOfStockLeft,
      isUrgent: isUrgent,
      currentStock: product.currentStock,
    );
  }

  /// Computes minimum stock for all products that have demand records.
  List<MinimumStockResult> computeAll({
    required List<Product> products,
    required Map<String, List<DomainDemandRecord>> demandByProduct,
    required List<BillOfMaterials> boms,
    required List<RawMaterial> rawMaterials,
    required List<Supplier> suppliers,
    required List<Manufacturer> manufacturers,
    UserSettings? settings,
  }) {
    final results = <MinimumStockResult>[];
    for (final product in products) {
      final records = demandByProduct[product.id] ?? [];
      final result = computeForProduct(
        product: product,
        demandRecords: records,
        boms: boms,
        rawMaterials: rawMaterials,
        suppliers: suppliers,
        manufacturers: manufacturers,
        settings: settings,
      );
      if (result != null) results.add(result);
    }
    results.sort((a, b) => a.daysOfStockLeft.compareTo(b.daysOfStockLeft));
    return results;
  }
}

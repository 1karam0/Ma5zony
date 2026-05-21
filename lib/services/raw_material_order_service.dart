import 'dart:math';
import 'package:ma5zony/models/bill_of_materials.dart';
import 'package:ma5zony/models/raw_material.dart';
import 'package:ma5zony/models/raw_material_purchase_order.dart';
import 'package:ma5zony/models/supplier.dart';

class RawMaterialOrderService {
  /// BOM-explodes a forecast quantity into grouped RawMaterialPurchaseOrders
  /// (one order per supplier).
  ///
  /// Returns an empty list if no active BOM exists for the product.
  List<RawMaterialPurchaseOrder> createFromForecast({
    required String productId,
    required double forecastQty,
    required List<BillOfMaterials> boms,
    required List<RawMaterial> rawMaterials,
    required List<Supplier> suppliers,
    String? forecastProductId,
  }) {
    // Find the single active BOM for this product.
    final activeBom = boms
        .where((b) => b.finalProductId == productId && b.isActive)
        .toList();
    if (activeBom.isEmpty) return [];
    final bom = activeBom.first;

    final rmMap = {for (final r in rawMaterials) r.id: r};
    final supplierMap = {for (final s in suppliers) s.id: s};

    // Group BOM line items by supplierId.
    final bySupplier = <String, List<RawMaterialLineItem>>{};

    for (final line in bom.materials) {
      final rm = rmMap[line.rawMaterialId];
      if (rm == null) continue;
      final sid = rm.supplierId ?? '_unassigned';
      final totalQty = (line.quantityPerUnit * forecastQty);
      final lineItem = RawMaterialLineItem(
        rawMaterialId: rm.id,
        rawMaterialName: rm.name,
        quantityOrdered: totalQty,
        unitOfMeasure: line.unitOfMeasure.isNotEmpty
            ? line.unitOfMeasure
            : rm.unitOfMeasure,
        unitCost: rm.unitCost,
      );
      bySupplier.putIfAbsent(sid, () => []).add(lineItem);
    }

    final orders = <RawMaterialPurchaseOrder>[];
    for (final entry in bySupplier.entries) {
      final supplier = supplierMap[entry.key];
      orders.add(RawMaterialPurchaseOrder(
        id: _generateId(),
        supplierId: entry.key,
        supplierName: supplier?.name ?? 'Unassigned Supplier',
        forecastProductId: forecastProductId ?? productId,
        items: entry.value,
        status: 'draft',
        createdAt: DateTime.now(),
      ));
    }

    return orders;
  }

  String _generateId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random.secure();
    return List.generate(20, (_) => chars[rand.nextInt(chars.length)]).join();
  }
}

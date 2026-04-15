import 'dart:math';

import 'package:ma5zony/models/bill_of_materials.dart';
import 'package:ma5zony/models/production_order.dart';
import 'package:ma5zony/models/raw_material.dart';
import 'package:ma5zony/models/raw_material_order.dart';
import 'package:ma5zony/services/inventory_repository.dart';

/// Orchestrates production-order creation and raw-material order generation.
class ManufacturingService {
  final InventoryRepository repo;
  ManufacturingService({required this.repo});

  /// Create a production order from an approved recommendation.
  Future<ProductionOrder> createProductionOrder({
    required String finalProductId,
    required int quantity,
    required String manufacturerId,
    required double estimatedCost,
    DateTime? estimatedCompletionDate,
  }) async {
    final order = ProductionOrder(
      id: '', // Firestore will assign
      finalProductId: finalProductId,
      quantity: quantity,
      status: ProductionOrderStatus.draft,
      manufacturerId: manufacturerId,
      createdAt: DateTime.now(),
      estimatedCost: estimatedCost,
      estimatedCompletionDate: estimatedCompletionDate,
    );
    return repo.addProductionOrder(order);
  }

  /// Generate raw-material orders for a production order based on BOM.
  Future<List<RawMaterialOrder>> generateRawMaterialOrders({
    required ProductionOrder productionOrder,
    required BillOfMaterials bom,
    required List<RawMaterial> rawMaterials,
  }) async {
    final orders = <RawMaterialOrder>[];
    final rng = Random.secure();

    for (final mat in bom.materials) {
      final rm = rawMaterials.where((r) => r.id == mat.rawMaterialId).firstOrNull;
      final token = List.generate(
        32,
        (_) => 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'[
            rng.nextInt(62)],
      ).join();

      final rmOrder = RawMaterialOrder(
        id: '', // Firestore will assign
        productionOrderId: productionOrder.id,
        rawMaterialId: mat.rawMaterialId,
        supplierId: rm?.supplierId ?? '',
        quantity: (mat.quantityPerUnit * productionOrder.quantity).ceil(),
        requestedDate: DateTime.now(),
        accessToken: token,
      );
      final saved = await repo.addRawMaterialOrder(rmOrder);
      orders.add(saved);
    }

    return orders;
  }
}

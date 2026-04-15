import 'package:ma5zony/models/production_order.dart';
import 'package:ma5zony/models/raw_material_order.dart';
import 'package:ma5zony/models/workflow_log.dart';
import 'package:ma5zony/services/inventory_repository.dart';

/// Handles production-order lifecycle transitions and logs each action.
class WorkflowService {
  final InventoryRepository repo;
  WorkflowService({required this.repo});

  /// Transition a production order to a new status.
  /// Returns the updated order.
  Future<ProductionOrder> transitionProductionOrder(
    ProductionOrder order,
    ProductionOrderStatus newStatus,
    String performedBy,
  ) async {
    order.status = newStatus;
    if (newStatus == ProductionOrderStatus.completed) {
      order.completedAt = DateTime.now();
    }
    await repo.updateProductionOrder(order);
    await _log(
      entityType: 'ProductionOrder',
      entityId: order.id,
      action: 'status_change:${newStatus.name}',
      performedBy: performedBy,
    );
    return order;
  }

  /// Update the status of a raw-material order. Returns the updated order.
  Future<RawMaterialOrder> updateRawMaterialOrderStatus(
    RawMaterialOrder order,
    String newStatus,
    String performedBy,
  ) async {
    order.status = newStatus;
    if (newStatus == 'completed') {
      order.completedDate = DateTime.now();
    }
    await repo.updateRawMaterialOrder(order);
    await _log(
      entityType: 'RawMaterialOrder',
      entityId: order.id,
      action: 'status_change:$newStatus',
      performedBy: performedBy,
    );
    return order;
  }

  /// Check if all raw-material orders for a production order are completed.
  Future<bool> areAllMaterialsReady(String productionOrderId) async {
    final orders = await repo.getRawMaterialOrders();
    final siblings =
        orders.where((o) => o.productionOrderId == productionOrderId).toList();
    if (siblings.isEmpty) return false;
    return siblings.every((o) => o.status == 'completed');
  }

  Future<void> _log({
    required String entityType,
    required String entityId,
    required String action,
    required String performedBy,
    String? details,
  }) async {
    final log = WorkflowLog(
      id: 'wl-${DateTime.now().millisecondsSinceEpoch}',
      entityType: entityType,
      entityId: entityId,
      action: action,
      performedBy: performedBy,
      timestamp: DateTime.now(),
      details: details,
    );
    await repo.addWorkflowLog(log);
  }
}

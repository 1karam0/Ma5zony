// Tests for the Phase 2 email workflow: manufacturing and replenishment
// approval flows that auto-create orders and dispatch emails.
//
// These are pure-Dart unit tests — no Firebase initialisation required.
// Run with: flutter test test/email_workflow_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:ma5zony/models/bill_of_materials.dart';
import 'package:ma5zony/models/production_order.dart';
import 'package:ma5zony/models/raw_material.dart';
import 'package:ma5zony/models/raw_material_order.dart';
import 'package:ma5zony/providers/app_state.dart';
import 'package:ma5zony/services/manufacturing_service.dart';
import 'package:ma5zony/services/inventory_repository.dart';

// ---------------------------------------------------------------------------
// Minimal in-test stub — only the two methods used by ManufacturingService
// are implemented; all others throw [UnimplementedError] via noSuchMethod.
// ---------------------------------------------------------------------------
class _StubRepo implements InventoryRepository {
  int _idCounter = 0;
  final List<RawMaterialOrder> capturedRmOrders = [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());

  @override
  Future<RawMaterialOrder> addRawMaterialOrder(RawMaterialOrder order) async {
    final saved = RawMaterialOrder(
      id: 'rmo_${++_idCounter}',
      productionOrderId: order.productionOrderId,
      rawMaterialId: order.rawMaterialId,
      supplierId: order.supplierId,
      quantity: order.quantity,
      requestedDate: order.requestedDate,
      accessToken: order.accessToken,
    );
    capturedRmOrders.add(saved);
    return saved;
  }

  @override
  Future<ProductionOrder> addProductionOrder(ProductionOrder order) async {
    return ProductionOrder(
      id: 'po_stub',
      finalProductId: order.finalProductId,
      quantity: order.quantity,
      manufacturerId: order.manufacturerId,
      createdAt: order.createdAt,
      estimatedCost: order.estimatedCost,
    );
  }
}

// ---------------------------------------------------------------------------
// Helper factory methods
// ---------------------------------------------------------------------------
ProductionOrder _order({int qty = 10}) => ProductionOrder(
      id: 'po_test',
      finalProductId: 'prod_1',
      quantity: qty,
      manufacturerId: 'mfr_1',
      createdAt: DateTime(2025, 1, 1),
      estimatedCost: 100.0,
    );

RawMaterial _rm(String id, String supplierId) => RawMaterial(
      id: id,
      name: 'Material $id',
      sku: id.toUpperCase(),
      unit: 'pcs',
      unitCost: 1.0,
      supplierId: supplierId,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  // ── ManufacturingService.generateRawMaterialOrders ──────────────────────
  group('ManufacturingService.generateRawMaterialOrders', () {
    late _StubRepo repo;
    late ManufacturingService svc;

    setUp(() {
      repo = _StubRepo();
      svc = ManufacturingService(repo: repo);
    });

    test('creates one order per BOM material', () async {
      final bom = BillOfMaterials(
        id: 'bom_1',
        finalProductId: 'prod_1',
        materials: [
          BomMaterial(rawMaterialId: 'rm_1', quantityPerUnit: 2.0),
          BomMaterial(rawMaterialId: 'rm_2', quantityPerUnit: 1.5),
        ],
      );
      final rms = [_rm('rm_1', 'sup_A'), _rm('rm_2', 'sup_B')];

      final orders = await svc.generateRawMaterialOrders(
        productionOrder: _order(qty: 10),
        bom: bom,
        rawMaterials: rms,
      );

      expect(orders, hasLength(2));
    });

    test('quantity = ceil(quantityPerUnit × productionQty)', () async {
      final bom = BillOfMaterials(
        id: 'bom_1',
        finalProductId: 'prod_1',
        materials: [
          BomMaterial(rawMaterialId: 'rm_1', quantityPerUnit: 2.0), // 2 × 10 = 20
          BomMaterial(rawMaterialId: 'rm_2', quantityPerUnit: 1.5), // ceil(1.5 × 10) = 15
          BomMaterial(rawMaterialId: 'rm_3', quantityPerUnit: 0.7), // ceil(0.7 × 3) = 3
        ],
      );
      final rms = [_rm('rm_1', 's'), _rm('rm_2', 's'), _rm('rm_3', 's')];

      final orders = await svc.generateRawMaterialOrders(
        productionOrder: _order(qty: 10),
        bom: bom,
        rawMaterials: rms,
      );
      expect(orders[0].quantity, 20);
      expect(orders[1].quantity, 15);
      expect(orders[2].quantity, 7); // ceil(0.7 × 10) = 7
    });

    test('assigns supplierId from matching RawMaterial', () async {
      final bom = BillOfMaterials(
        id: 'bom_1',
        finalProductId: 'prod_1',
        materials: [BomMaterial(rawMaterialId: 'rm_1', quantityPerUnit: 1.0)],
      );
      final orders = await svc.generateRawMaterialOrders(
        productionOrder: _order(),
        bom: bom,
        rawMaterials: [_rm('rm_1', 'supplier_X')],
      );
      expect(orders.first.supplierId, 'supplier_X');
    });

    test('supplierId is empty string when raw material not found', () async {
      final bom = BillOfMaterials(
        id: 'bom_1',
        finalProductId: 'prod_1',
        materials: [BomMaterial(rawMaterialId: 'rm_missing', quantityPerUnit: 1.0)],
      );
      final orders = await svc.generateRawMaterialOrders(
        productionOrder: _order(),
        bom: bom,
        rawMaterials: [], // empty list — no match
      );
      expect(orders.first.supplierId, isEmpty);
    });

    test('each order has a unique 32-character access token', () async {
      final bom = BillOfMaterials(
        id: 'bom_1',
        finalProductId: 'prod_1',
        materials: [
          BomMaterial(rawMaterialId: 'rm_1', quantityPerUnit: 1.0),
          BomMaterial(rawMaterialId: 'rm_2', quantityPerUnit: 1.0),
          BomMaterial(rawMaterialId: 'rm_3', quantityPerUnit: 1.0),
        ],
      );
      final rms = [_rm('rm_1', 's'), _rm('rm_2', 's'), _rm('rm_3', 's')];

      final orders = await svc.generateRawMaterialOrders(
        productionOrder: _order(),
        bom: bom,
        rawMaterials: rms,
      );

      for (final o in orders) {
        expect(o.accessToken, hasLength(32));
      }
      final tokens = orders.map((o) => o.accessToken).toSet();
      expect(tokens, hasLength(orders.length), reason: 'tokens must be unique');
    });

    test('productionOrderId on each order matches the production order id', () async {
      final bom = BillOfMaterials(
        id: 'bom_1',
        finalProductId: 'prod_1',
        materials: [BomMaterial(rawMaterialId: 'rm_1', quantityPerUnit: 1.0)],
      );
      final orders = await svc.generateRawMaterialOrders(
        productionOrder: _order(),
        bom: bom,
        rawMaterials: [_rm('rm_1', 's')],
      );
      expect(orders.first.productionOrderId, 'po_test');
    });
  });

  // ── Supplier grouping logic (mirrors _createPerSupplierFactoryOrders) ───
  group('Supplier grouping — mirrors _createPerSupplierFactoryOrders logic', () {
    /// Replicates the grouping logic from AppState._createPerSupplierFactoryOrders.
    Map<String, List<RawMaterialOrder>> groupBySupplier(
        List<RawMaterialOrder> orders) {
      final result = <String, List<RawMaterialOrder>>{};
      for (final o in orders) {
        if (o.supplierId.isEmpty) continue;
        result.putIfAbsent(o.supplierId, () => []).add(o);
      }
      return result;
    }

    test('materials from the same supplier are grouped into one entry', () async {
      final repo = _StubRepo();
      final svc = ManufacturingService(repo: repo);

      final bom = BillOfMaterials(
        id: 'bom_1',
        finalProductId: 'prod_1',
        materials: [
          BomMaterial(rawMaterialId: 'rm_1', quantityPerUnit: 1.0),
          BomMaterial(rawMaterialId: 'rm_2', quantityPerUnit: 1.0),
          BomMaterial(rawMaterialId: 'rm_3', quantityPerUnit: 1.0),
        ],
      );
      // rm_1 and rm_3 share sup_A; rm_2 belongs to sup_B
      final rms = [
        _rm('rm_1', 'sup_A'),
        _rm('rm_2', 'sup_B'),
        _rm('rm_3', 'sup_A'),
      ];

      final orders = await svc.generateRawMaterialOrders(
        productionOrder: _order(),
        bom: bom,
        rawMaterials: rms,
      );

      final grouped = groupBySupplier(orders);
      expect(grouped.keys, containsAll(['sup_A', 'sup_B']));
      expect(grouped['sup_A'], hasLength(2));
      expect(grouped['sup_B'], hasLength(1));
    });

    test('orders with empty supplierId are excluded from groups', () async {
      final repo = _StubRepo();
      final svc = ManufacturingService(repo: repo);

      final bom = BillOfMaterials(
        id: 'bom_1',
        finalProductId: 'prod_1',
        materials: [
          BomMaterial(rawMaterialId: 'rm_known', quantityPerUnit: 1.0),
          BomMaterial(rawMaterialId: 'rm_unknown', quantityPerUnit: 1.0),
        ],
      );
      final rms = [_rm('rm_known', 'sup_A')]; // rm_unknown has no match

      final orders = await svc.generateRawMaterialOrders(
        productionOrder: _order(),
        bom: bom,
        rawMaterials: rms,
      );

      final grouped = groupBySupplier(orders);
      expect(grouped.keys, equals({'sup_A'}));
      expect(grouped['sup_A'], hasLength(1));
    });

    test('returns zero groups when all supplierId values are empty', () async {
      final repo = _StubRepo();
      final svc = ManufacturingService(repo: repo);

      final bom = BillOfMaterials(
        id: 'bom_1',
        finalProductId: 'prod_1',
        materials: [BomMaterial(rawMaterialId: 'rm_missing', quantityPerUnit: 1.0)],
      );

      final orders = await svc.generateRawMaterialOrders(
        productionOrder: _order(),
        bom: bom,
        rawMaterials: [],
      );

      expect(groupBySupplier(orders), isEmpty);
    });
  });

  // ── Exception classes ────────────────────────────────────────────────────
  group('CloudFunctionException', () {
    test('preserves statusCode and message', () {
      final e = CloudFunctionException(404, 'No supplier orders found');
      expect(e.statusCode, 404);
      expect(e.message, 'No supplier orders found');
    });

    test('toString returns the message', () {
      final e = CloudFunctionException(500, 'Internal server error');
      expect(e.toString(), 'Internal server error');
    });
  });

  group('BomMissingException', () {
    test('contains the productId', () {
      final e = BomMissingException('prod_abc');
      expect(e.productId, 'prod_abc');
    });

    test('toString mentions Bills of Materials', () {
      final e = BomMissingException('prod_abc');
      expect(e.toString(), contains('Bill of Materials'));
    });
  });
}

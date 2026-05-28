import 'package:flutter_test/flutter_test.dart';

import 'package:ma5zony/models/demand_record.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/purchase_order.dart';
import 'package:ma5zony/models/supplier.dart';
import 'package:ma5zony/services/supply_chain_insights_service.dart';

List<DomainDemandRecord> _monthlySeries({
  required String productId,
  required List<int> monthlyTotals,
}) {
  final base = DateTime(2025, 1, 1);
  final out = <DomainDemandRecord>[];
  for (int m = 0; m < monthlyTotals.length; m++) {
    final monthStart = DateTime(base.year, base.month + m, 1);
    out.add(DomainDemandRecord(
      id: 'd${productId}_$m',
      productId: productId,
      periodStart: monthStart,
      quantity: monthlyTotals[m],
    ));
  }
  return out;
}

PurchaseOrder _po({
  required String id,
  required DateTime createdAt,
  required String productId,
  required String productName,
  required int qty,
  required OrderStatus status,
  String supplierId = 's1',
}) {
  return PurchaseOrder(
    id: id,
    status: status,
    createdAt: createdAt,
    createdByUid: 'u1',
    createdByName: 'tester',
    items: [
      PurchaseOrderItem(
        productId: productId,
        productName: productName,
        sku: productId.toUpperCase(),
        quantity: qty,
        unitCost: 1.0,
        supplierId: supplierId,
      ),
    ],
    supplierId: supplierId,
  );
}

void main() {
  final service = SupplyChainInsightsService();
  final today = DateTime(2026, 1, 1);

  group('Bullwhip detection', () {
    test('flat demand + flat orders → low bullwhip risk', () {
      final p = Product(
        id: 'p1', sku: 'S1', name: 'Strap', category: 'x',
        unitCost: 1, currentStock: 100,
      );
      final demand = _monthlySeries(
        productId: 'p1',
        monthlyTotals: List.filled(6, 100),
      );
      final orders = List.generate(
        6,
        (i) => _po(
          id: 'po$i',
          createdAt: DateTime(2025, i + 1, 15),
          productId: 'p1',
          productName: 'Strap',
          qty: 100,
          status: OrderStatus.completed,
        ),
      );
      final result = service.analyse(
        products: [p],
        demandByProduct: {'p1': demand},
        purchaseOrders: orders,
        suppliers: {},
        now: today,
      );
      final bw = result.bullwhipByProduct.single;
      expect(bw.risk, BullwhipRisk.low);
      expect(bw.bullwhipRatio, lessThan(1.5));
    });

    test('stable demand + wildly swinging orders → high bullwhip risk', () {
      final p = Product(
        id: 'p2', sku: 'S2', name: 'Strap', category: 'x',
        unitCost: 1, currentStock: 100,
      );
      final demand = _monthlySeries(
        productId: 'p2',
        monthlyTotals: List.filled(6, 100),
      );
      final qtys = [10, 500, 20, 800, 5, 600];
      final orders = List.generate(
        6,
        (i) => _po(
          id: 'po$i',
          createdAt: DateTime(2025, i + 1, 15),
          productId: 'p2',
          productName: 'Strap',
          qty: qtys[i],
          status: OrderStatus.completed,
        ),
      );
      final result = service.analyse(
        products: [p],
        demandByProduct: {'p2': demand},
        purchaseOrders: orders,
        suppliers: {},
        now: today,
      );
      final bw = result.bullwhipByProduct.single;
      expect(bw.risk, BullwhipRisk.high);
      expect(bw.bullwhipRatio, greaterThan(2.0));
    });

    test('no orders → insufficient data', () {
      final p = Product(
        id: 'p3', sku: 'S3', name: 'Strap', category: 'x',
        unitCost: 1, currentStock: 100,
      );
      final demand = _monthlySeries(
        productId: 'p3', monthlyTotals: [100, 110, 90, 105],
      );
      final result = service.analyse(
        products: [p],
        demandByProduct: {'p3': demand},
        purchaseOrders: const [],
        suppliers: {},
        now: today,
      );
      expect(result.bullwhipByProduct.single.risk,
          BullwhipRisk.insufficientData);
    });
  });

  group('Supplier reliability', () {
    test('all-completed supplier scores grade A', () {
      final s = Supplier(
        id: 's1', name: 'Acme', contactEmail: 'a@b.c',
        typicalLeadTimeDays: 14, performanceRating: 5.0,
      );
      final orders = List.generate(
        5,
        (i) => _po(
          id: 'po$i',
          createdAt: DateTime(2025, 6, 1).subtract(Duration(days: 30 * i)),
          productId: 'p1', productName: 'p', qty: 10,
          status: OrderStatus.completed,
        ),
      );
      final result = service.analyse(
        products: const [],
        demandByProduct: const {},
        purchaseOrders: orders,
        suppliers: {'s1': s},
        now: today,
      );
      final r = result.supplierReliability.single;
      expect(r.score, greaterThanOrEqualTo(85));
      expect(r.grade, 'A');
    });

    test('no PO history uses manual rating fallback', () {
      final s = Supplier(
        id: 's1', name: 'New Supplier', contactEmail: 'a@b.c',
        typicalLeadTimeDays: 14, performanceRating: 3.0,
      );
      final result = service.analyse(
        products: const [],
        demandByProduct: const {},
        purchaseOrders: const [],
        suppliers: {'s1': s},
        now: today,
      );
      final r = result.supplierReliability.single;
      expect(r.totalOrders, 0);
      expect(r.score, 60); // 3/5 × 100
      expect(r.explanation, contains('No purchase orders'));
    });
  });

  group('Product movement classification', () {
    test('high velocity + low CV → Fast', () {
      final p = Product(
        id: 'p1', sku: 'S1', name: 'Fast Mover', category: 'x',
        unitCost: 1, currentStock: 1000,
      );
      // ~200 units/month = ~6.7/day, very stable
      final demand = _monthlySeries(
        productId: 'p1', monthlyTotals: [200, 195, 205, 198, 203, 199],
      );
      final result = service.analyse(
        products: [p],
        demandByProduct: {'p1': demand},
        purchaseOrders: const [],
        suppliers: {},
        now: today,
      );
      expect(result.productMovements.single.category, MovementCategory.fast);
    });

    test('high CV → Risky regardless of velocity', () {
      final p = Product(
        id: 'p2', sku: 'S2', name: 'Risky Item', category: 'x',
        unitCost: 1, currentStock: 100,
      );
      // Massively variable demand: CV > 1.0
      final demand = _monthlySeries(
        productId: 'p2', monthlyTotals: [0, 0, 500, 0, 0, 400],
      );
      final result = service.analyse(
        products: [p],
        demandByProduct: {'p2': demand},
        purchaseOrders: const [],
        suppliers: {},
        now: today,
      );
      expect(result.productMovements.single.category, MovementCategory.risky);
    });

    test('empty demand → Slow with explanation', () {
      final p = Product(
        id: 'p3', sku: 'S3', name: 'Untouched', category: 'x',
        unitCost: 1, currentStock: 5,
      );
      final result = service.analyse(
        products: [p],
        demandByProduct: const {},
        purchaseOrders: const [],
        suppliers: {},
        now: today,
      );
      expect(result.productMovements.single.category, MovementCategory.slow);
      expect(result.productMovements.single.recommendation,
          contains('No sales history'));
    });
  });

  group('Alerts & info-sharing', () {
    test('high bullwhip raises an alert', () {
      final p = Product(
        id: 'p1', sku: 'S1', name: 'Strap', category: 'x',
        unitCost: 1, currentStock: 100,
      );
      final demand = _monthlySeries(
        productId: 'p1', monthlyTotals: List.filled(6, 100),
      );
      final qtys = [0, 1000, 0, 1000, 0, 1000];
      final orders = List.generate(
        6,
        (i) => _po(
          id: 'po$i',
          createdAt: DateTime(2025, i + 1, 15),
          productId: 'p1', productName: 'Strap', qty: qtys[i],
          status: OrderStatus.completed,
        ),
      );
      final result = service.analyse(
        products: [p],
        demandByProduct: {'p1': demand},
        purchaseOrders: orders,
        suppliers: {},
        now: today,
      );
      expect(
        result.alerts.any((a) =>
            a.severity == AlertSeverity.high &&
            a.title.contains('Bullwhip')),
        isTrue,
      );
    });

    test('information sharing checklist is always populated', () {
      final result = service.analyse(
        products: const [],
        demandByProduct: const {},
        purchaseOrders: const [],
        suppliers: {},
        now: today,
      );
      expect(result.informationSharingChecklist, isNotEmpty);
    });
  });
}

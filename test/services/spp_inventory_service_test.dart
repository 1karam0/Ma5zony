import 'package:flutter_test/flutter_test.dart';

import 'package:ma5zony/models/demand_record.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/services/spp_inventory_service.dart';

/// Builds a daily demand record list with [perDay] units sold each day
/// across [days] days ending today.
List<DomainDemandRecord> _flatDemand({
  required String productId,
  required int days,
  required int perDay,
}) {
  final today = DateTime(2025, 6, 1);
  return List.generate(
    days,
    (i) => DomainDemandRecord(
      id: 'r$i',
      productId: productId,
      periodStart: today.subtract(Duration(days: days - i)),
      quantity: perDay,
    ),
  );
}

/// Builds a rising-trend daily demand series: starts at [start] units/day
/// and ramps linearly to [end] units/day over [days] days.
List<DomainDemandRecord> _risingDemand({
  required String productId,
  required int days,
  required int start,
  required int end,
}) {
  final today = DateTime(2025, 6, 1);
  return List.generate(days, (i) {
    final qty = (start + (end - start) * (i / (days - 1))).round();
    return DomainDemandRecord(
      id: 'r$i',
      productId: productId,
      periodStart: today.subtract(Duration(days: days - i)),
      quantity: qty,
    );
  });
}

void main() {
  final today = DateTime(2025, 6, 1);
  final service = SppInventoryService();

  group('SppInventoryService.serviceLevelToZ', () {
    test('95% maps to ~1.65', () {
      expect(SppInventoryService.serviceLevelToZ(95), closeTo(1.65, 0.01));
    });
    test('99% maps to ~2.33', () {
      expect(SppInventoryService.serviceLevelToZ(99), closeTo(2.33, 0.01));
    });
    test('90% maps to ~1.28', () {
      expect(SppInventoryService.serviceLevelToZ(90), closeTo(1.28, 0.01));
    });
  });

  group('SppInventoryService.compute — empty/insufficient data', () {
    test('returns zero policy when no demand history', () {
      final p = Product(
        id: 'p1', sku: 'S1', name: 'Widget', category: 'x',
        unitCost: 10, currentStock: 50, leadTimeDays: 7,
      );
      final result = service.compute(
        product: p,
        demandHistory: const [],
        now: today,
      );
      expect(result.averageDailyDemand, 0);
      expect(result.minimumStock, 0);
      expect(result.reorderPoint, 0);
      expect(result.risk, SppRisk.safe);
      expect(result.explanation, contains('No sales history'));
    });
  });

  group('SppInventoryService.compute — flat demand', () {
    test('computes ROP = avgDemand × leadTime when variance is zero', () {
      final p = Product(
        id: 'p2', sku: 'S2', name: 'Strap', category: 'x',
        unitCost: 5, currentStock: 500, leadTimeDays: 10,
      );
      final demand = _flatDemand(productId: 'p2', days: 180, perDay: 5);
      final r = service.compute(
        product: p,
        demandHistory: demand,
        now: today,
      );
      expect(r.averageDailyDemand, closeTo(5.0, 0.01));
      expect(r.demandStdDev, closeTo(0, 0.01));
      expect(r.totalReplenishmentDays, 10);
      expect(r.expectedDemandDuringReplenishment, closeTo(50, 0.01));
      expect(r.safetyStock, 0); // zero variance → zero safety stock
      expect(r.reorderPoint, 50);
      expect(r.risk, SppRisk.safe); // 500 units > 50 ROP
      expect(r.momentumStatus, MomentumStatus.stable);
    });

    test('adds production time to lead time', () {
      final p = Product(
        id: 'p3', sku: 'S3', name: 'Strap', category: 'x',
        unitCost: 5, currentStock: 500, leadTimeDays: 10,
      );
      final demand = _flatDemand(productId: 'p3', days: 180, perDay: 5);
      final r = service.compute(
        product: p,
        demandHistory: demand,
        productionTimeDays: 5,
        now: today,
      );
      expect(r.totalReplenishmentDays, 15); // 10 lead + 5 production
      expect(r.expectedDemandDuringReplenishment, closeTo(75, 0.01));
    });
  });

  group('SppInventoryService.compute — momentum', () {
    test('rising sales lift the minimum stock above the textbook ROP', () {
      final p = Product(
        id: 'p4', sku: 'S4', name: 'Strap', category: 'x',
        unitCost: 5, currentStock: 200, leadTimeDays: 10,
      );
      final demand = _risingDemand(
        productId: 'p4',
        days: 120,
        start: 1,
        end: 10,
      );
      final r = service.compute(
        product: p,
        demandHistory: demand,
        now: today,
      );
      expect(r.momentumStatus, MomentumStatus.rising);
      expect(r.momentumScore, greaterThan(0.10));
      // Minimum should be at least as high as the textbook ROP.
      expect(r.minimumStock, greaterThanOrEqualTo(r.reorderPoint));
    });

    test('minimum never falls below safety stock floor', () {
      final p = Product(
        id: 'p5', sku: 'S5', name: 'Strap', category: 'x',
        unitCost: 5, currentStock: 200, leadTimeDays: 10,
      );
      // Falling demand should reduce the recommendation but never below SS.
      final demand = _risingDemand(
        productId: 'p5',
        days: 120,
        start: 10,
        end: 1,
      );
      final r = service.compute(
        product: p,
        demandHistory: demand,
        now: today,
      );
      expect(r.momentumStatus, MomentumStatus.falling);
      expect(r.minimumStock, greaterThanOrEqualTo(r.safetyStock));
    });
  });

  group('SppInventoryService.compute — risk classification', () {
    test('out-of-stock → critical', () {
      final p = Product(
        id: 'p6', sku: 'S6', name: 'Strap', category: 'x',
        unitCost: 5, currentStock: 0, leadTimeDays: 10,
      );
      final demand = _flatDemand(productId: 'p6', days: 120, perDay: 5);
      final r = service.compute(
        product: p,
        demandHistory: demand,
        now: today,
      );
      expect(r.risk, SppRisk.critical);
      expect(r.explanation, contains('replenishment order now'));
    });

    test('stock below ROP → critical', () {
      final p = Product(
        id: 'p7', sku: 'S7', name: 'Strap', category: 'x',
        unitCost: 5, currentStock: 10, leadTimeDays: 10,
      );
      final demand = _flatDemand(productId: 'p7', days: 120, perDay: 5);
      final r = service.compute(
        product: p,
        demandHistory: demand,
        now: today,
      );
      // ROP = 50, stock = 10 → critical
      expect(r.risk, SppRisk.critical);
    });
  });
}

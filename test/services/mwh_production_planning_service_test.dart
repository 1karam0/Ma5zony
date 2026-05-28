import 'package:flutter_test/flutter_test.dart';

import 'package:ma5zony/models/demand_record.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/services/mwh_production_planning_service.dart';

List<DomainDemandRecord> _monthlyDemand({
  required String productId,
  required int months,
  required int perMonth,
}) {
  final today = DateTime(2025, 6, 1);
  final out = <DomainDemandRecord>[];
  for (int m = 0; m < months; m++) {
    // Spread evenly across the month: one record per day with perMonth/30 qty.
    final monthStart = DateTime(today.year, today.month - months + m, 1);
    for (int d = 0; d < 30; d++) {
      out.add(DomainDemandRecord(
        id: 'r${m}_$d',
        productId: productId,
        periodStart: monthStart.add(Duration(days: d)),
        quantity: (perMonth / 30).round(),
      ));
    }
  }
  return out;
}

void main() {
  final service = MwhProductionPlanningService();
  final today = DateTime(2025, 6, 1);

  group('MwhProductionPlanningService.plan — insufficient data', () {
    test('falls back to naive forecast when <3 months history', () {
      final p = Product(
        id: 'p1', sku: 'S1', name: 'Widget', category: 'x',
        unitCost: 10, currentStock: 0, leadTimeDays: 7,
      );
      final demand = _monthlyDemand(productId: 'p1', months: 1, perMonth: 90);
      final plan = service.plan(
        product: p,
        demandHistory: demand,
        coverageDays: 60,
        now: today,
      );
      expect(plan.algorithmUsed, contains('naive'));
      expect(plan.confidence, MwhConfidence.low);
    });
  });

  group('MwhProductionPlanningService.plan — happy path', () {
    test('computes production = forecast + minStock − currentStock', () {
      final p = Product(
        id: 'p2', sku: 'S2', name: 'Strap', category: 'x',
        unitCost: 5, currentStock: 100, leadTimeDays: 10,
      );
      final demand = _monthlyDemand(
        productId: 'p2', months: 12, perMonth: 90,
      );
      final plan = service.plan(
        product: p,
        demandHistory: demand,
        coverageDays: 60,
        now: today,
      );

      // ~3 units/day × 60 days = ~180 forecast
      // production = forecast + minStock − stock, clamped ≥ 0
      expect(plan.forecastedDemand, greaterThan(150));
      expect(plan.forecastedDemand, lessThan(220));
      expect(
        plan.recommendedProductionQty,
        plan.forecastedDemand + plan.minimumStock - p.currentStock < 0
            ? 0
            : plan.forecastedDemand + plan.minimumStock - p.currentStock,
      );
      expect(plan.algorithmUsed, isNot(contains('naive')));
    });

    test('returns zero production when stock already covers period + min', () {
      final p = Product(
        id: 'p3', sku: 'S3', name: 'Strap', category: 'x',
        unitCost: 5, currentStock: 10000, leadTimeDays: 10,
      );
      final demand = _monthlyDemand(
        productId: 'p3', months: 12, perMonth: 90,
      );
      final plan = service.plan(
        product: p,
        demandHistory: demand,
        coverageDays: 30,
        now: today,
      );
      expect(plan.recommendedProductionQty, 0);
      expect(plan.reason, contains('No production needed'));
    });

    test('growth adjustment increases the forecast proportionally', () {
      final p = Product(
        id: 'p4', sku: 'S4', name: 'Strap', category: 'x',
        unitCost: 5, currentStock: 0, leadTimeDays: 10,
      );
      final demand = _monthlyDemand(
        productId: 'p4', months: 12, perMonth: 90,
      );
      final base = service.plan(
        product: p,
        demandHistory: demand,
        coverageDays: 30,
        now: today,
      );
      final boosted = service.plan(
        product: p,
        demandHistory: demand,
        coverageDays: 30,
        growthAdjustment: 0.20,
        now: today,
      );
      expect(boosted.forecastedDemand,
          greaterThanOrEqualTo((base.forecastedDemand * 1.15).floor()));
    });
  });

  group('MwhProductionPlanningService.planForCatalog', () {
    test('returns one plan per active product', () {
      final products = [
        Product(id: 'a', sku: 'A', name: 'A', category: 'x',
            unitCost: 1, currentStock: 0, leadTimeDays: 5),
        Product(id: 'b', sku: 'B', name: 'B', category: 'x',
            unitCost: 1, currentStock: 0, leadTimeDays: 5),
        Product(id: 'c', sku: 'C', name: 'C', category: 'x',
            unitCost: 1, currentStock: 0, leadTimeDays: 5, isActive: false),
      ];
      final demand = {
        'a': _monthlyDemand(productId: 'a', months: 6, perMonth: 60),
        'b': _monthlyDemand(productId: 'b', months: 6, perMonth: 30),
      };
      final plans = service.planForCatalog(
        products: products,
        demandByProduct: demand,
        coverageDays: 30,
        now: today,
      );
      expect(plans.length, 2); // c is inactive
      expect(plans.map((p) => p.productId), containsAll(['a', 'b']));
    });
  });
}

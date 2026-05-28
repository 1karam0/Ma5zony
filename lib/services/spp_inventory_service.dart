import 'dart:math';

import 'package:ma5zony/models/demand_record.dart';
import 'package:ma5zony/models/product.dart';

/// SPP (Silver–Pyke–Peterson) Inventory Policy Service.
///
/// Reference:
///   Silver, E. A., Pyke, D. F., & Peterson, R. (1998/2017).
///   *Inventory Management and Production Planning and Scheduling*.
///
/// Implements the classical reorder-point engine with three additions that
/// the textbook describes but the codebase did not previously expose:
///
///   1. **Sales momentum** — short-window growth-rate adjustment so that a
///      rising trend lifts the minimum stock and a falling trend lowers it
///      (bounded so it never falls below the textbook safety floor).
///   2. **Total replenishment time** = lead time + production time
///      (the SPP "L" includes manufacturing throughput, not just supplier
///      transit).
///   3. **Plain-English explanation** of *why* the recommendation is what
///      it is, so a non-technical business user can read it.
///
/// All inputs are the data already present in `AppState` (Product,
/// DomainDemandRecord, lead-time fields). No new persistence is required.
class SppInventoryService {
  /// Z-table mapping for the textbook service-level shortcuts.
  /// Defaults to 95 % (Z = 1.65), which is the SPP recommended default.
  static double serviceLevelToZ(double serviceLevelPercent) {
    if (serviceLevelPercent >= 99) return 2.33;
    if (serviceLevelPercent >= 98) return 2.05;
    if (serviceLevelPercent >= 97) return 1.88;
    if (serviceLevelPercent >= 95) return 1.65;
    if (serviceLevelPercent >= 90) return 1.28;
    if (serviceLevelPercent >= 85) return 1.04;
    return 0.84; // ~80 %
  }

  /// Computes the SPP policy for a single product.
  ///
  /// [demandHistory] should be the raw `DomainDemandRecord` list for the
  /// product (already keyed in `AppState.demandByProduct[productId]`).
  /// The service derives average daily demand directly from the records so
  /// callers don't need to pre-aggregate.
  SppPolicy compute({
    required Product product,
    required List<DomainDemandRecord> demandHistory,
    int? supplierLeadTimeDays,
    int productionTimeDays = 0,
    double serviceLevelPercent = 95,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final z = serviceLevelToZ(serviceLevelPercent);
    final leadTime = supplierLeadTimeDays ?? product.leadTimeDays;
    final totalReplenishmentDays = max(1, leadTime + productionTimeDays);

    // ── Daily-demand series (last 180 days, gap-filled with zeros). ────────
    final dailySeries = _dailySeries(demandHistory, today, windowDays: 180);

    if (dailySeries.isEmpty || dailySeries.every((d) => d == 0)) {
      return SppPolicy(
        productId: product.id,
        productName: product.name,
        currentStock: product.currentStock,
        averageDailyDemand: 0,
        demandStdDev: 0,
        momentumScore: 0,
        momentumStatus: MomentumStatus.stable,
        leadTimeDays: leadTime,
        productionTimeDays: productionTimeDays,
        totalReplenishmentDays: totalReplenishmentDays,
        expectedDemandDuringReplenishment: 0,
        safetyStock: 0,
        minimumStock: 0,
        reorderPoint: 0,
        risk: SppRisk.safe,
        serviceLevelPercent: serviceLevelPercent,
        explanation:
            'No sales history yet for ${product.name}. Once we have a few '
            'weeks of demand we can recommend a minimum stock level.',
      );
    }

    final avgDaily =
        dailySeries.reduce((a, b) => a + b) / dailySeries.length;

    // Standard deviation of daily demand.
    final variance = dailySeries
            .map((d) => (d - avgDaily) * (d - avgDaily))
            .fold<double>(0, (a, b) => a + b) /
        dailySeries.length;
    final stdDev = sqrt(variance);

    // ── Sales momentum: last 30d avg vs previous 30d avg. ──────────────────
    final momentum = _momentum(dailySeries);
    final momentumStatus = _classifyMomentum(momentum);

    // ── Expected demand over (lead + production) time. ────────────────────
    final expectedDemand = avgDaily * totalReplenishmentDays;

    // ── Safety stock: σ × √L × Z. (SPP §7.5) ──────────────────────────────
    final safetyStock = stdDev * sqrt(totalReplenishmentDays) * z;

    // ── Momentum-adjusted minimum stock. ──────────────────────────────────
    // Adjustment is bounded to [-25%, +35%] of the base so that a noisy
    // recent month cannot collapse the safety floor (SPP §7.7 — adaptive
    // policies should remain above the variability-derived minimum).
    final baseMinimum = expectedDemand + safetyStock;
    final momentumFactor = momentum.clamp(-0.25, 0.35);
    final adjustedMinimum = baseMinimum * (1 + momentumFactor);
    final minimumStock = max(safetyStock, adjustedMinimum).round();

    // SPP defines ROP = expected demand during replenishment + safety stock.
    // We expose both the textbook ROP and the momentum-adjusted minimum so
    // the UI can show "what theory says" vs "what we recommend".
    final reorderPoint = (expectedDemand + safetyStock).round();

    // ── Risk classification (Safe / Warning / Critical). ──────────────────
    final risk = _classifyRisk(
      currentStock: product.currentStock,
      reorderPoint: reorderPoint,
      minimumStock: minimumStock,
    );

    return SppPolicy(
      productId: product.id,
      productName: product.name,
      currentStock: product.currentStock,
      averageDailyDemand: avgDaily,
      demandStdDev: stdDev,
      momentumScore: momentum,
      momentumStatus: momentumStatus,
      leadTimeDays: leadTime,
      productionTimeDays: productionTimeDays,
      totalReplenishmentDays: totalReplenishmentDays,
      expectedDemandDuringReplenishment: expectedDemand,
      safetyStock: safetyStock.round(),
      minimumStock: minimumStock,
      reorderPoint: reorderPoint,
      risk: risk,
      serviceLevelPercent: serviceLevelPercent,
      explanation: _explain(
        product: product,
        avgDaily: avgDaily,
        momentum: momentumStatus,
        totalReplenishmentDays: totalReplenishmentDays,
        minimumStock: minimumStock,
        currentStock: product.currentStock,
        risk: risk,
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────────────────────────────

  /// Builds a gap-filled daily demand series for the last [windowDays] days.
  List<double> _dailySeries(
    List<DomainDemandRecord> records,
    DateTime today, {
    required int windowDays,
  }) {
    if (records.isEmpty) return const [];
    final start = today.subtract(Duration(days: windowDays));
    final buckets = <String, double>{};
    for (final r in records) {
      if (r.periodStart.isBefore(start)) continue;
      final key = '${r.periodStart.year}-${r.periodStart.month}-${r.periodStart.day}';
      buckets[key] = (buckets[key] ?? 0) + r.quantity;
    }
    if (buckets.isEmpty) return const [];

    final out = <double>[];
    for (int i = 0; i < windowDays; i++) {
      final d = start.add(Duration(days: i));
      final key = '${d.year}-${d.month}-${d.day}';
      out.add(buckets[key] ?? 0);
    }
    return out;
  }

  /// Momentum = (avg of last 30 days − avg of previous 30 days) / previous avg.
  /// Returns 0.0 when there isn't enough history.
  double _momentum(List<double> dailySeries) {
    if (dailySeries.length < 60) return 0;
    final recent = dailySeries.sublist(dailySeries.length - 30);
    final previous =
        dailySeries.sublist(dailySeries.length - 60, dailySeries.length - 30);
    final recentAvg = recent.reduce((a, b) => a + b) / 30.0;
    final prevAvg = previous.reduce((a, b) => a + b) / 30.0;
    if (prevAvg <= 0) return recentAvg > 0 ? 0.25 : 0;
    return (recentAvg - prevAvg) / prevAvg;
  }

  MomentumStatus _classifyMomentum(double m) {
    if (m >= 0.10) return MomentumStatus.rising;
    if (m <= -0.10) return MomentumStatus.falling;
    return MomentumStatus.stable;
  }

  SppRisk _classifyRisk({
    required int currentStock,
    required int reorderPoint,
    required int minimumStock,
  }) {
    if (currentStock <= 0) return SppRisk.critical;
    if (currentStock < reorderPoint) return SppRisk.critical;
    if (currentStock < minimumStock) return SppRisk.warning;
    return SppRisk.safe;
  }

  String _explain({
    required Product product,
    required double avgDaily,
    required MomentumStatus momentum,
    required int totalReplenishmentDays,
    required int minimumStock,
    required int currentStock,
    required SppRisk risk,
  }) {
    final trendWord = switch (momentum) {
      MomentumStatus.rising => 'rising',
      MomentumStatus.falling => 'falling',
      MomentumStatus.stable => 'stable',
    };
    final daily = avgDaily.toStringAsFixed(avgDaily >= 10 ? 0 : 1);
    final cover = (avgDaily > 0)
        ? '~${(currentStock / avgDaily).round()} days of cover'
        : 'no recent sales';

    final base =
        '${product.name} has $trendWord sales momentum (about $daily units/day). '
        'Combined lead + production time is $totalReplenishmentDays days, so '
        'the system recommends keeping at least $minimumStock units in stock '
        '($cover at today\'s pace).';

    return switch (risk) {
      SppRisk.critical =>
        '$base You are below the reorder point — place a replenishment order now.',
      SppRisk.warning =>
        '$base Stock is approaching the minimum — plan the next order soon.',
      SppRisk.safe => '$base Stock levels are healthy.',
    };
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Result objects
// ════════════════════════════════════════════════════════════════════════════

enum MomentumStatus { rising, stable, falling }

enum SppRisk { safe, warning, critical }

class SppPolicy {
  final String productId;
  final String productName;
  final int currentStock;
  final double averageDailyDemand;
  final double demandStdDev;
  final double momentumScore; // e.g. 0.18 = +18 %
  final MomentumStatus momentumStatus;
  final int leadTimeDays;
  final int productionTimeDays;
  final int totalReplenishmentDays;
  final double expectedDemandDuringReplenishment;
  final int safetyStock;
  final int minimumStock;
  final int reorderPoint;
  final SppRisk risk;
  final double serviceLevelPercent;
  final String explanation;

  const SppPolicy({
    required this.productId,
    required this.productName,
    required this.currentStock,
    required this.averageDailyDemand,
    required this.demandStdDev,
    required this.momentumScore,
    required this.momentumStatus,
    required this.leadTimeDays,
    required this.productionTimeDays,
    required this.totalReplenishmentDays,
    required this.expectedDemandDuringReplenishment,
    required this.safetyStock,
    required this.minimumStock,
    required this.reorderPoint,
    required this.risk,
    required this.serviceLevelPercent,
    required this.explanation,
  });
}

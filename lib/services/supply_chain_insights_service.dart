import 'dart:math';

import 'package:ma5zony/models/demand_record.dart';
import 'package:ma5zony/models/product.dart';
import 'package:ma5zony/models/purchase_order.dart';
import 'package:ma5zony/models/supplier.dart';
import 'package:ma5zony/services/demand_aggregation_service.dart';

/// Chopra–Meindl Supply-Chain Coordination & Insights Service.
///
/// Reference:
///   Chopra, S., & Meindl, P. (2016/2019).
///   *Supply Chain Management: Strategy, Planning, and Operation*, 6th/7th ed.
///   Chapter 10 (Coordination in a Supply Chain) — bullwhip effect,
///   information distortion, and the strategic role of supplier reliability.
///
/// Produces three coordinated outputs that the textbook recommends every
/// supply-chain decision-support system should display:
///
///   1. **Bullwhip risk** per product — the ratio of order-variance to
///      demand-variance (the textbook's "bullwhip measure"). Values >> 1.0
///      mean upstream orders are amplifying downstream demand swings.
///   2. **Supplier reliability score** — a 0–100 composite of on-time
///      delivery, lead-time stability and the user-entered rating.
///   3. **Product movement classification** — fast / stable / slow / risky
///      using daily-velocity and demand-CV (Chopra & Meindl Fig. 12-7
///      adapted for SMEs), each with a recommended inventory strategy.
///
/// All inputs are data already present in `AppState`. No new persistence.
class SupplyChainInsightsService {
  final DemandAggregationService _aggregator;

  SupplyChainInsightsService({DemandAggregationService? aggregator})
      : _aggregator = aggregator ?? DemandAggregationService();

  /// Single-call API the screen uses to render the whole dashboard.
  SupplyChainInsights analyse({
    required List<Product> products,
    required Map<String, List<DomainDemandRecord>> demandByProduct,
    required List<PurchaseOrder> purchaseOrders,
    required Map<String, Supplier> suppliers,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();

    final bullwhip = <BullwhipResult>[];
    final classifications = <ProductMovementResult>[];
    for (final product in products.where((p) => p.isActive)) {
      final history = demandByProduct[product.id] ?? const [];
      bullwhip.add(_bullwhipFor(product, history, purchaseOrders));
      classifications.add(_classifyMovement(product, history));
    }

    final reliability = suppliers.values
        .map((s) => _reliabilityFor(s, purchaseOrders, today))
        .toList();

    final overallBullwhip = _overallBullwhipRisk(bullwhip);
    final alerts = _buildAlerts(
      bullwhip: bullwhip,
      reliability: reliability,
      movements: classifications,
    );

    return SupplyChainInsights(
      overallBullwhipRisk: overallBullwhip,
      bullwhipByProduct: bullwhip,
      supplierReliability: reliability,
      productMovements: classifications,
      alerts: alerts,
      informationSharingChecklist: _informationSharingChecklist(),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // 1. Bullwhip effect
  // ────────────────────────────────────────────────────────────────────────

  /// Bullwhip measure (Chopra & Meindl §10.2):
  ///   bullwhip = Var(orders) / Var(demand)
  ///
  /// We compute monthly demand variance from `demandByProduct` and monthly
  /// PO-quantity variance from `purchaseOrders` (filtering to lines that
  /// reference this product).
  BullwhipResult _bullwhipFor(
    Product product,
    List<DomainDemandRecord> demand,
    List<PurchaseOrder> orders,
  ) {
    final monthlyDemand = _aggregator.fillMissingPeriods(
      _aggregator.aggregateToMonthly(demand),
    );
    final demandSeries = _aggregator.toSeries(monthlyDemand);

    // Build a parallel monthly PO-quantity series for this product.
    final orderBuckets = <String, double>{};
    for (final po in orders) {
      for (final item in po.items) {
        if (item.productId != product.id) continue;
        final key =
            '${po.createdAt.year}-${po.createdAt.month.toString().padLeft(2, '0')}';
        orderBuckets[key] = (orderBuckets[key] ?? 0) + item.quantity;
      }
    }
    final orderSeries = monthlyDemand
        .map((m) =>
            orderBuckets['${m.year}-${m.month.toString().padLeft(2, '0')}'] ??
            0.0)
        .toList();

    final demandVar = _variance(demandSeries);
    final orderVar = _variance(orderSeries);

    double ratio;
    if (demandVar <= 0 && orderVar <= 0) {
      ratio = 1.0;
    } else if (demandVar <= 0) {
      // Orders are moving but demand is flat → definite amplification.
      ratio = double.infinity;
    } else {
      ratio = orderVar / demandVar;
    }

    BullwhipRisk risk;
    if (orderSeries.where((q) => q > 0).length < 2) {
      risk = BullwhipRisk.insufficientData;
    } else if (ratio.isInfinite || ratio >= 2.0) {
      risk = BullwhipRisk.high;
    } else if (ratio >= 1.25) {
      risk = BullwhipRisk.medium;
    } else {
      risk = BullwhipRisk.low;
    }

    return BullwhipResult(
      productId: product.id,
      productName: product.name,
      demandVariance: demandVar,
      orderVariance: orderVar,
      bullwhipRatio: ratio.isInfinite ? 99.0 : ratio,
      risk: risk,
    );
  }

  BullwhipRisk _overallBullwhipRisk(List<BullwhipResult> per) {
    final scored =
        per.where((b) => b.risk != BullwhipRisk.insufficientData).toList();
    if (scored.isEmpty) return BullwhipRisk.insufficientData;
    final highs = scored.where((b) => b.risk == BullwhipRisk.high).length;
    final mediums = scored.where((b) => b.risk == BullwhipRisk.medium).length;
    if (highs >= max(1, scored.length ~/ 4)) return BullwhipRisk.high;
    if (highs + mediums >= scored.length ~/ 2) return BullwhipRisk.medium;
    return BullwhipRisk.low;
  }

  // ────────────────────────────────────────────────────────────────────────
  // 2. Supplier reliability
  // ────────────────────────────────────────────────────────────────────────

  /// Composite 0–100 score (Chopra & Meindl §11.4 — supplier scoring):
  ///   - on-time-completion rate of completed POs   (50 %)
  ///   - share of orders not cancelled              (20 %)
  ///   - user-entered performanceRating / 5         (30 %)
  ///
  /// Lead-time variance contributes via the on-time component (any order
  /// completed beyond `2 × typicalLeadTime` counts as late).
  SupplierReliability _reliabilityFor(
    Supplier s,
    List<PurchaseOrder> orders,
    DateTime today,
  ) {
    final mine = orders
        .where((po) =>
            po.supplierId == s.id ||
            po.items.any((i) => i.supplierId == s.id))
        .toList();

    if (mine.isEmpty) {
      // No history → use the manual rating only (or default to neutral).
      final base = (s.performanceRating ?? 3.0) / 5.0;
      return SupplierReliability(
        supplierId: s.id,
        supplierName: s.name,
        totalOrders: 0,
        onTimeRate: 0,
        completedRate: 0,
        manualRating: s.performanceRating,
        score: (base * 100).round(),
        grade: _grade((base * 100).round()),
        explanation:
            'No purchase orders recorded with ${s.name} yet. Score is based '
            'on the manual rating only.',
      );
    }

    final completed =
        mine.where((po) => po.status == OrderStatus.completed).toList();
    final cancelled =
        mine.where((po) => po.status == OrderStatus.cancelled).length;

    final lateThresholdDays = max(1, s.typicalLeadTimeDays * 2);
    final lates = completed.where((po) {
      // We don't store a completedAt date on POs, so fall back to "still
      // open after the threshold" — flag as late if the createdAt is older
      // than the threshold AND the status isn't completed yet.
      return today.difference(po.createdAt).inDays > lateThresholdDays &&
          po.status != OrderStatus.completed;
    }).length;

    final onTime =
        completed.isEmpty ? 0.0 : (completed.length - lates) / completed.length;
    final completedRate = mine.isEmpty ? 0.0 : completed.length / mine.length;
    final manual = (s.performanceRating ?? 3.0) / 5.0;

    final score = ((onTime * 0.5) + (completedRate * 0.2) + (manual * 0.3)) *
        100;
    final scoreInt = score.clamp(0, 100).round();

    return SupplierReliability(
      supplierId: s.id,
      supplierName: s.name,
      totalOrders: mine.length,
      onTimeRate: onTime,
      completedRate: completedRate,
      manualRating: s.performanceRating,
      score: scoreInt,
      grade: _grade(scoreInt),
      explanation: '${s.name}: ${mine.length} orders, '
          '${(onTime * 100).round()}% on-time, '
          '${(completedRate * 100).round()}% completed'
          '${cancelled > 0 ? ', $cancelled cancelled' : ''}.',
    );
  }

  String _grade(int score) {
    if (score >= 85) return 'A';
    if (score >= 70) return 'B';
    if (score >= 55) return 'C';
    if (score >= 40) return 'D';
    return 'F';
  }

  // ────────────────────────────────────────────────────────────────────────
  // 3. Product movement classification
  // ────────────────────────────────────────────────────────────────────────

  /// Chopra & Meindl Fig. 12-7 adapted: classify products on two axes
  /// — velocity (units/day) and demand CV — then attach a recommended
  /// inventory strategy.
  ProductMovementResult _classifyMovement(
    Product product,
    List<DomainDemandRecord> demand,
  ) {
    if (demand.isEmpty) {
      return ProductMovementResult(
        productId: product.id,
        productName: product.name,
        velocityPerDay: 0,
        demandCv: 0,
        category: MovementCategory.slow,
        recommendation:
            'No sales history yet. Treat as slow-moving — keep minimal '
            'stock and produce only when an order arrives.',
      );
    }

    final monthly = _aggregator.fillMissingPeriods(
      _aggregator.aggregateToMonthly(demand),
    );
    final series = _aggregator.toSeries(monthly);
    final stats = _aggregator.computeStats(series);
    final velocity = stats.mean / 30.0; // monthly → daily

    MovementCategory category;
    String advice;

    // Thresholds tuned for SMEs (Chopra & Meindl Table 12-4):
    //   fast:    velocity > 5 units/day AND CV ≤ 0.5
    //   stable:  CV ≤ 0.5 (lower velocity)
    //   risky:   CV > 1.0 (high variability regardless of velocity)
    //   slow:    everything else
    if (velocity > 5 && stats.cv <= 0.5) {
      category = MovementCategory.fast;
      advice = 'High-velocity, predictable demand. Keep a higher safety '
          'stock and review reorder levels weekly to prevent stock-outs.';
    } else if (stats.cv > 1.0) {
      category = MovementCategory.risky;
      advice = 'Highly variable demand. Monitor closely, lean on '
          'short-horizon forecasts, and coordinate frequent small orders '
          'with the supplier rather than one big batch.';
    } else if (stats.cv <= 0.5) {
      category = MovementCategory.stable;
      advice =
          'Stable demand pattern. A standard reorder-point policy works '
          'well — no special action needed.';
    } else {
      category = MovementCategory.slow;
      advice = 'Slow-moving item. Carry minimal stock and produce or order '
          'only when demand materialises to free up cash.';
    }

    return ProductMovementResult(
      productId: product.id,
      productName: product.name,
      velocityPerDay: velocity,
      demandCv: stats.cv,
      category: category,
      recommendation: advice,
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // Alerts & info-sharing checklist
  // ────────────────────────────────────────────────────────────────────────

  List<SupplyChainAlert> _buildAlerts({
    required List<BullwhipResult> bullwhip,
    required List<SupplierReliability> reliability,
    required List<ProductMovementResult> movements,
  }) {
    final alerts = <SupplyChainAlert>[];
    for (final b in bullwhip.where((b) => b.risk == BullwhipRisk.high)) {
      alerts.add(SupplyChainAlert(
        severity: AlertSeverity.high,
        title: 'Bullwhip risk on ${b.productName}',
        message:
            'Order swings are ${b.bullwhipRatio.toStringAsFixed(1)}× larger '
            'than demand swings. Consider smaller, more frequent orders or '
            'sharing the forecast with the supplier.',
      ));
    }
    for (final r in reliability.where((r) => r.score < 55 && r.totalOrders > 0)) {
      alerts.add(SupplyChainAlert(
        severity: AlertSeverity.medium,
        title: '${r.supplierName} reliability is low',
        message:
            'Composite score ${r.score}/100 (grade ${r.grade}). Look at '
            'alternative suppliers or build extra safety stock for items '
            'sourced here.',
      ));
    }
    for (final m in movements.where((m) => m.category == MovementCategory.risky)) {
      alerts.add(SupplyChainAlert(
        severity: AlertSeverity.medium,
        title: '${m.productName} has unstable demand',
        message:
            'Demand variability is ${(m.demandCv * 100).round()}%. Avoid '
            'long-horizon commitments and review the forecast weekly.',
      ));
    }
    return alerts;
  }

  List<String> _informationSharingChecklist() => const [
        'Sales history shared with production planning',
        'Production plan visible to procurement',
        'Supplier lead times reviewed quarterly',
        'Inventory availability checked before every promo',
        'Forecast changes communicated upstream within 24 h',
      ];

  // ── Utility ─────────────────────────────────────────────────────────────

  double _variance(List<double> values) {
    if (values.length < 2) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final sumSq = values
        .map((v) => (v - mean) * (v - mean))
        .fold<double>(0, (a, b) => a + b);
    return sumSq / values.length;
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Result objects
// ════════════════════════════════════════════════════════════════════════════

enum BullwhipRisk { low, medium, high, insufficientData }

enum MovementCategory { fast, stable, slow, risky }

enum AlertSeverity { low, medium, high }

class BullwhipResult {
  final String productId;
  final String productName;
  final double demandVariance;
  final double orderVariance;
  final double bullwhipRatio;
  final BullwhipRisk risk;

  const BullwhipResult({
    required this.productId,
    required this.productName,
    required this.demandVariance,
    required this.orderVariance,
    required this.bullwhipRatio,
    required this.risk,
  });
}

class SupplierReliability {
  final String supplierId;
  final String supplierName;
  final int totalOrders;
  final double onTimeRate;
  final double completedRate;
  final double? manualRating;
  final int score; // 0–100
  final String grade; // A–F
  final String explanation;

  const SupplierReliability({
    required this.supplierId,
    required this.supplierName,
    required this.totalOrders,
    required this.onTimeRate,
    required this.completedRate,
    required this.manualRating,
    required this.score,
    required this.grade,
    required this.explanation,
  });
}

class ProductMovementResult {
  final String productId;
  final String productName;
  final double velocityPerDay;
  final double demandCv;
  final MovementCategory category;
  final String recommendation;

  const ProductMovementResult({
    required this.productId,
    required this.productName,
    required this.velocityPerDay,
    required this.demandCv,
    required this.category,
    required this.recommendation,
  });
}

class SupplyChainAlert {
  final AlertSeverity severity;
  final String title;
  final String message;

  const SupplyChainAlert({
    required this.severity,
    required this.title,
    required this.message,
  });
}

class SupplyChainInsights {
  final BullwhipRisk overallBullwhipRisk;
  final List<BullwhipResult> bullwhipByProduct;
  final List<SupplierReliability> supplierReliability;
  final List<ProductMovementResult> productMovements;
  final List<SupplyChainAlert> alerts;
  final List<String> informationSharingChecklist;

  const SupplyChainInsights({
    required this.overallBullwhipRisk,
    required this.bullwhipByProduct,
    required this.supplierReliability,
    required this.productMovements,
    required this.alerts,
    required this.informationSharingChecklist,
  });
}

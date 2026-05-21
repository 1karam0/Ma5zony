import 'dart:math';

import 'package:ma5zony/models/demand_record.dart';
import 'package:ma5zony/models/product.dart';

/// ABC-XYZ inventory classification service.
///
/// Based on Silver, Pyke & Peterson's framework:
/// - **ABC** classifies products by annual consumption value (Pareto / 80-20 rule)
/// - **XYZ** classifies products by demand variability (coefficient of variation)
///
/// The combined 9-cell matrix (AX, AY, AZ, BX, BY, BZ, CX, CY, CZ) drives
/// differentiated inventory policies — e.g. tight control for AX items,
/// generous safety stock for AZ items.
class AbcXyzService {
  // ══════════════════════════════════════════════════════════════════════════
  // ABC CLASSIFICATION (Value-based)
  // ══════════════════════════════════════════════════════════════════════════

  /// Classifies products into A, B, C categories by annual consumption value.
  ///
  /// A = top ~80% of cumulative value (typically 10-20% of items)
  /// B = next ~15% of cumulative value
  /// C = remaining ~5% of cumulative value
  ///
  /// Returns a map from productId → ABCClass.
  Map<String, ABCClass> classifyABC({
    required List<Product> products,
    required Map<String, List<DomainDemandRecord>> demandByProduct,
    double aThreshold = 0.80,
    double bThreshold = 0.95,
  }) {
    // Calculate annual consumption value for each product
    final valueEntries = <_ValueEntry>[];

    for (final product in products) {
      final records = demandByProduct[product.id] ?? [];
      final totalDemand = records.fold<int>(0, (sum, r) => sum + r.quantity);

      // Annualise: if we have N months of data, scale to 12
      final months = _distinctMonths(records);
      final annualDemand =
          months > 0 ? (totalDemand / months) * 12 : totalDemand.toDouble();

      final annualValue = annualDemand * product.unitCost;

      valueEntries.add(_ValueEntry(
        productId: product.id,
        annualValue: annualValue,
      ));
    }

    // Sort descending by annual value
    valueEntries.sort((a, b) => b.annualValue.compareTo(a.annualValue));

    final totalValue =
        valueEntries.fold<double>(0, (sum, e) => sum + e.annualValue);

    // Assign classes based on cumulative value
    final result = <String, ABCClass>{};
    double cumulative = 0;

    for (final entry in valueEntries) {
      cumulative += entry.annualValue;
      final ratio = totalValue > 0 ? cumulative / totalValue : 1.0;

      if (ratio <= aThreshold) {
        result[entry.productId] = ABCClass.A;
      } else if (ratio <= bThreshold) {
        result[entry.productId] = ABCClass.B;
      } else {
        result[entry.productId] = ABCClass.C;
      }
    }

    // Ensure products with no demand get class C
    for (final product in products) {
      result.putIfAbsent(product.id, () => ABCClass.C);
    }

    return result;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // XYZ CLASSIFICATION (Demand variability)
  // ══════════════════════════════════════════════════════════════════════════

  /// Classifies products into X, Y, Z categories by coefficient of variation
  /// (CV = σ / μ) of their demand series.
  ///
  /// X = CV < 0.5  (stable, predictable demand)
  /// Y = 0.5 ≤ CV < 1.0  (moderate variability)
  /// Z = CV ≥ 1.0  (erratic, unpredictable demand)
  ///
  /// Returns a map from productId → XYZClass.
  Map<String, XYZClass> classifyXYZ({
    required List<Product> products,
    required Map<String, List<DomainDemandRecord>> demandByProduct,
    double xThreshold = 0.5,
    double yThreshold = 1.0,
  }) {
    final result = <String, XYZClass>{};

    for (final product in products) {
      final records = demandByProduct[product.id] ?? [];

      if (records.length < 2) {
        // Not enough data to compute variability — treat as Z (unpredictable)
        result[product.id] = XYZClass.Z;
        continue;
      }

      // Aggregate to monthly demand series
      final monthlySeries = _aggregateMonthly(records);

      if (monthlySeries.length < 2) {
        result[product.id] = XYZClass.Z;
        continue;
      }

      final mean =
          monthlySeries.reduce((a, b) => a + b) / monthlySeries.length;

      if (mean == 0) {
        result[product.id] = XYZClass.Z;
        continue;
      }

      final variance = monthlySeries
              .map((v) => (v - mean) * (v - mean))
              .reduce((a, b) => a + b) /
          monthlySeries.length;
      final stdDev = sqrt(variance);
      final cv = stdDev / mean;

      if (cv < xThreshold) {
        result[product.id] = XYZClass.X;
      } else if (cv < yThreshold) {
        result[product.id] = XYZClass.Y;
      } else {
        result[product.id] = XYZClass.Z;
      }
    }

    return result;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // COMBINED ABC-XYZ MATRIX
  // ══════════════════════════════════════════════════════════════════════════

  /// Builds the combined 9-cell ABC-XYZ classification matrix.
  ///
  /// Returns a map from productId → [ProductClassification] containing:
  /// - ABC class (A, B, or C)
  /// - XYZ class (X, Y, or Z)
  /// - Combined label (e.g. "AX", "BY", "CZ")
  /// - Recommended strategy description
  /// - Recommended forecasting method
  Map<String, ProductClassification> buildMatrix({
    required List<Product> products,
    required Map<String, List<DomainDemandRecord>> demandByProduct,
  }) {
    final abc = classifyABC(
      products: products,
      demandByProduct: demandByProduct,
    );
    final xyz = classifyXYZ(
      products: products,
      demandByProduct: demandByProduct,
    );

    final result = <String, ProductClassification>{};

    for (final product in products) {
      final abcClass = abc[product.id] ?? ABCClass.C;
      final xyzClass = xyz[product.id] ?? XYZClass.Z;
      final label = '${abcClass.name}${xyzClass.name}';

      result[product.id] = ProductClassification(
        productId: product.id,
        abcClass: abcClass,
        xyzClass: xyzClass,
        label: label,
        strategy: _strategyFor(abcClass, xyzClass),
        recommendedAlgorithm: _algorithmFor(abcClass, xyzClass),
      );
    }

    return result;
  }

  /// Summary counts for the 9-cell matrix.
  Map<String, int> matrixSummary(Map<String, ProductClassification> matrix) {
    final counts = <String, int>{};
    for (final entry in matrix.values) {
      counts[entry.label] = (counts[entry.label] ?? 0) + 1;
    }
    return counts;
  }

  // ── Strategy recommendations per cell ─────────────────────────────────

  static String _strategyFor(ABCClass abc, XYZClass xyz) {
    switch ('${abc.name}${xyz.name}') {
      case 'AX':
        return 'Tight control, frequent review, minimal safety stock. '
            'Use precise forecasting (SES/SMA). Negotiate with suppliers for JIT delivery.';
      case 'AY':
        return 'Close monitoring with moderate safety stock. '
            'Use trend-aware forecasting (Holt\'s method). Regular demand review.';
      case 'AZ':
        return 'High risk — generous safety stock required. '
            'Use adaptive forecasting (Holt-Winters). Consider strategic buffer inventory.';
      case 'BX':
        return 'Standard control with lean safety stock. '
            'Simple forecasting (SMA) is sufficient. Periodic review.';
      case 'BY':
        return 'Moderate control with reasonable safety stock. '
            'Use exponential smoothing (SES). Quarterly review.';
      case 'BZ':
        return 'Watch for demand spikes. Maintain buffer stock. '
            'Consider make-to-order for volatile items.';
      case 'CX':
        return 'Minimal oversight. Automate reordering with fixed EOQ. '
            'Simple rules-based replenishment.';
      case 'CY':
        return 'Low priority, standard rules. Review annually. '
            'Consider bulk ordering to reduce per-unit costs.';
      case 'CZ':
        return 'Monitor for obsolescence risk. Consider dropping slow movers. '
            'Minimal or no safety stock.';
      default:
        return 'Standard inventory management.';
    }
  }

  static String _algorithmFor(ABCClass abc, XYZClass xyz) {
    switch ('${abc.name}${xyz.name}') {
      case 'AX':
      case 'BX':
      case 'CX':
        return 'SMA'; // Stable demand → simple methods work well
      case 'AY':
      case 'BY':
        return 'Holt'; // Moderate variability → capture trends
      case 'AZ':
        return 'HoltWinters'; // High value + erratic → advanced method
      case 'BZ':
      case 'CY':
        return 'SES'; // Moderate complexity → exponential smoothing
      case 'CZ':
        return 'SMA'; // Low value → keep it simple
      default:
        return 'SMA';
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  /// Counts distinct year-month combinations in the demand records.
  int _distinctMonths(List<DomainDemandRecord> records) {
    final months = <String>{};
    for (final r in records) {
      months.add('${r.periodStart.year}-${r.periodStart.month}');
    }
    return months.length;
  }

  /// Aggregates demand records into monthly totals (double values).
  List<double> _aggregateMonthly(List<DomainDemandRecord> records) {
    final monthly = <String, double>{};
    for (final r in records) {
      final key = '${r.periodStart.year}-${r.periodStart.month.toString().padLeft(2, '0')}';
      monthly[key] = (monthly[key] ?? 0) + r.quantity.toDouble();
    }
    // Sort by key (chronological) and return values
    final sortedKeys = monthly.keys.toList()..sort();
    return sortedKeys.map((k) => monthly[k]!).toList();
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// DATA CLASSES
// ══════════════════════════════════════════════════════════════════════════════

enum ABCClass { A, B, C }
enum XYZClass { X, Y, Z }

/// Full classification result for a single product.
class ProductClassification {
  final String productId;
  final ABCClass abcClass;
  final XYZClass xyzClass;
  final String label; // e.g. "AX", "BY", "CZ"
  final String strategy; // Human-readable strategy recommendation
  final String recommendedAlgorithm; // Best forecast method for this class

  const ProductClassification({
    required this.productId,
    required this.abcClass,
    required this.xyzClass,
    required this.label,
    required this.strategy,
    required this.recommendedAlgorithm,
  });

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'abc': abcClass.name,
        'xyz': xyzClass.name,
        'label': label,
        'strategy': strategy,
        'recommendedAlgorithm': recommendedAlgorithm,
      };
}

class _ValueEntry {
  final String productId;
  final double annualValue;
  _ValueEntry({required this.productId, required this.annualValue});
}

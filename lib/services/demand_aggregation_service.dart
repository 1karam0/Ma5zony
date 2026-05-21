import 'dart:math';

import 'package:ma5zony/models/demand_record.dart';

/// Demand data pre-processing service.
///
/// Handles the critical step between raw transactional data (individual
/// Shopify orders) and the clean time-series format needed by forecasting
/// algorithms. As described in the interim report Section 3.6 (Data Flow):
///
///   Raw transactions → Aggregate → Clean → Forecast
///
/// Key capabilities:
///   - Aggregate raw demand records into consistent monthly buckets
///   - Fill gaps (months with zero demand)
///   - Detect statistical outliers using IQR method
///   - Detect seasonality pattern presence
class DemandAggregationService {
  // ══════════════════════════════════════════════════════════════════════════
  // MONTHLY AGGREGATION
  // ══════════════════════════════════════════════════════════════════════════

  /// Aggregates a list of [DomainDemandRecord] into monthly demand totals.
  ///
  /// Each Shopify order produces one demand record with the order date.
  /// This method groups them by year-month and sums the quantities.
  ///
  /// Returns a list of [MonthlyDemand] sorted chronologically.
  List<MonthlyDemand> aggregateToMonthly(List<DomainDemandRecord> records) {
    if (records.isEmpty) return [];

    final monthly = <String, int>{};
    for (final r in records) {
      final key =
          '${r.periodStart.year}-${r.periodStart.month.toString().padLeft(2, '0')}';
      monthly[key] = (monthly[key] ?? 0) + r.quantity;
    }

    final sortedKeys = monthly.keys.toList()..sort();
    return sortedKeys.map((key) {
      final parts = key.split('-');
      return MonthlyDemand(
        year: int.parse(parts[0]),
        month: int.parse(parts[1]),
        quantity: monthly[key]!,
      );
    }).toList();
  }

  /// Extracts the demand quantities as a [List] of doubles from monthly aggregates.
  List<double> toSeries(List<MonthlyDemand> monthly) {
    return monthly.map((m) => m.quantity.toDouble()).toList();
  }

  /// Extracts the period start dates from monthly aggregates.
  List<DateTime> toPeriods(List<MonthlyDemand> monthly) {
    return monthly.map((m) => DateTime(m.year, m.month, 1)).toList();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // GAP FILLING
  // ══════════════════════════════════════════════════════════════════════════

  /// Fills missing months with zero demand, ensuring a continuous time series.
  ///
  /// For example, if data exists for Jan, Feb, Apr, May — March is inserted
  /// with quantity = 0. This is essential for seasonal algorithms that
  /// require equally spaced observations.
  List<MonthlyDemand> fillMissingPeriods(List<MonthlyDemand> monthly) {
    if (monthly.length < 2) return List.from(monthly);

    final result = <MonthlyDemand>[];
    final first = monthly.first;
    final last = monthly.last;

    // Create a map for quick lookup
    final lookup = <String, int>{};
    for (final m in monthly) {
      lookup['${m.year}-${m.month}'] = m.quantity;
    }

    // Iterate from first to last month
    int year = first.year;
    int month = first.month;
    final endYear = last.year;
    final endMonth = last.month;

    while (year < endYear || (year == endYear && month <= endMonth)) {
      final qty = lookup['$year-$month'] ?? 0;
      result.add(MonthlyDemand(year: year, month: month, quantity: qty));

      month++;
      if (month > 12) {
        month = 1;
        year++;
      }
    }

    return result;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // OUTLIER DETECTION (IQR Method)
  // ══════════════════════════════════════════════════════════════════════════

  /// Detects outliers in the demand series using the Interquartile Range
  /// (IQR) method. A value is an outlier if it falls outside:
  ///   Q1 - 1.5 × IQR  or  Q3 + 1.5 × IQR
  ///
  /// Returns indices of outlier periods for user review.
  List<OutlierInfo> detectOutliers(List<MonthlyDemand> monthly) {
    if (monthly.length < 4) return []; // Need enough data for quartiles

    final values = monthly.map((m) => m.quantity.toDouble()).toList()..sort();
    final n = values.length;

    final q1 = values[(n * 0.25).floor()];
    final q3 = values[(n * 0.75).floor()];
    final iqr = q3 - q1;
    final lowerBound = q1 - 1.5 * iqr;
    final upperBound = q3 + 1.5 * iqr;

    final outliers = <OutlierInfo>[];
    for (int i = 0; i < monthly.length; i++) {
      final qty = monthly[i].quantity.toDouble();
      if (qty < lowerBound || qty > upperBound) {
        outliers.add(OutlierInfo(
          index: i,
          period: monthly[i],
          value: qty,
          lowerBound: lowerBound,
          upperBound: upperBound,
          type: qty < lowerBound ? OutlierType.low : OutlierType.high,
        ));
      }
    }

    return outliers;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SEASONALITY DETECTION
  // ══════════════════════════════════════════════════════════════════════════

  /// Detects whether the demand series exhibits seasonal patterns.
  ///
  /// Uses autocorrelation at lag = [seasonLength] (default 12 for monthly).
  /// If autocorrelation > 0.3, seasonality is considered present.
  ///
  /// Returns a [SeasonalityResult] with the autocorrelation coefficient
  /// and a recommendation on which algorithm to use.
  SeasonalityResult detectSeasonality(
    List<double> series, {
    int seasonLength = 12,
  }) {
    if (series.length < seasonLength * 2) {
      return SeasonalityResult(
        hasSeasonality: false,
        autocorrelation: 0,
        seasonLength: seasonLength,
        recommendation:
            'Insufficient data for seasonal analysis. Need at least ${seasonLength * 2} periods.',
      );
    }

    // Compute autocorrelation at lag = seasonLength
    final n = series.length;
    final mean = series.reduce((a, b) => a + b) / n;

    double numerator = 0;
    double denominator = 0;

    for (int i = 0; i < n; i++) {
      denominator += (series[i] - mean) * (series[i] - mean);
      if (i >= seasonLength) {
        numerator +=
            (series[i] - mean) * (series[i - seasonLength] - mean);
      }
    }

    final acf = denominator > 0 ? numerator / denominator : 0.0;
    final hasSeason = acf > 0.3;

    return SeasonalityResult(
      hasSeasonality: hasSeason,
      autocorrelation: acf,
      seasonLength: seasonLength,
      recommendation: hasSeason
          ? 'Seasonal pattern detected (ACF=${acf.toStringAsFixed(2)}). '
              'Recommend Holt-Winters Triple Exponential Smoothing.'
          : 'No significant seasonality (ACF=${acf.toStringAsFixed(2)}). '
              'Recommend SES or Holt\'s method for trend-aware forecasting.',
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DEMAND STATISTICS
  // ══════════════════════════════════════════════════════════════════════════

  /// Computes summary statistics for a demand series.
  DemandStats computeStats(List<double> series) {
    if (series.isEmpty) {
      return DemandStats(
        mean: 0, median: 0, stdDev: 0, cv: 0,
        min: 0, max: 0, total: 0, periods: 0,
      );
    }

    final sorted = List<double>.from(series)..sort();
    final n = series.length;
    final total = series.reduce((a, b) => a + b);
    final mean = total / n;
    final median = n.isOdd
        ? sorted[n ~/ 2]
        : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;

    final variance =
        series.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / n;
    final stdDev = sqrt(variance);
    final double cv = mean > 0 ? stdDev / mean : 0.0;

    return DemandStats(
      mean: mean,
      median: median,
      stdDev: stdDev,
      cv: cv,
      min: sorted.first,
      max: sorted.last,
      total: total,
      periods: n,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// DATA CLASSES
// ══════════════════════════════════════════════════════════════════════════════

class MonthlyDemand {
  final int year;
  final int month;
  final int quantity;

  const MonthlyDemand({
    required this.year,
    required this.month,
    required this.quantity,
  });

  String get label =>
      '$year-${month.toString().padLeft(2, '0')}';

  DateTime get periodStart => DateTime(year, month, 1);
}

enum OutlierType { low, high }

class OutlierInfo {
  final int index;
  final MonthlyDemand period;
  final double value;
  final double lowerBound;
  final double upperBound;
  final OutlierType type;

  const OutlierInfo({
    required this.index,
    required this.period,
    required this.value,
    required this.lowerBound,
    required this.upperBound,
    required this.type,
  });
}

class SeasonalityResult {
  final bool hasSeasonality;
  final double autocorrelation;
  final int seasonLength;
  final String recommendation;

  const SeasonalityResult({
    required this.hasSeasonality,
    required this.autocorrelation,
    required this.seasonLength,
    required this.recommendation,
  });
}

class DemandStats {
  final double mean;
  final double median;
  final double stdDev;
  final double cv; // coefficient of variation
  final double min;
  final double max;
  final double total;
  final int periods;

  const DemandStats({
    required this.mean,
    required this.median,
    required this.stdDev,
    required this.cv,
    required this.min,
    required this.max,
    required this.total,
    required this.periods,
  });
}

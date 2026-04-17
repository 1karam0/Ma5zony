import 'dart:math';

import 'package:ma5zony/models/forecast_result.dart';

/// Pure-Dart forecasting service. No Flutter dependencies.
class ForecastingService {
  // ── Simple Moving Average ──────────────────────────────────────────────────

  /// Returns the last SMA value over the provided [windowSize].
  /// Returns 0 if there is not enough data.
  double simpleMovingAverage(List<double> demand, int windowSize) {
    if (demand.length < windowSize) return 0;
    final window = demand.sublist(demand.length - windowSize);
    return window.reduce((a, b) => a + b) / windowSize;
  }

  /// Returns the full SMA series.
  /// First [windowSize - 1] entries are 0 (not enough history yet).
  List<double> simpleMovingAverageSeries(List<double> demand, int windowSize) {
    final result = <double>[];
    for (int i = 0; i < demand.length; i++) {
      if (i < windowSize - 1) {
        result.add(0);
      } else {
        final window = demand.sublist(i - windowSize + 1, i + 1);
        result.add(window.reduce((a, b) => a + b) / windowSize);
      }
    }
    return result;
  }

  // ── Single Exponential Smoothing ───────────────────────────────────────────

  /// Returns the final SES forecast value.
  /// Initial forecast = first demand value.
  double singleExponentialSmoothing(List<double> demand, double alpha) {
    if (demand.isEmpty) return 0;
    double forecast = demand.first;
    for (int i = 1; i < demand.length; i++) {
      forecast = alpha * demand[i] + (1 - alpha) * forecast;
    }
    return forecast;
  }

  /// Returns the full SES series (same length as [demand]).
  List<double> singleExponentialSmoothingSeries(
    List<double> demand,
    double alpha,
  ) {
    if (demand.isEmpty) return [];
    final result = <double>[];
    double forecast = demand.first;
    result.add(forecast);
    for (int i = 1; i < demand.length; i++) {
      forecast = alpha * demand[i] + (1 - alpha) * forecast;
      result.add(forecast);
    }
    return result;
  }

  // ── ForecastResult Builder ─────────────────────────────────────────────────

  /// Generates a [ForecastResult] from historical demand.
  /// Appends one future-period forecast at the end.
  ///
  /// When [leadTimeDays] > 0, also computes:
  /// - [demandDuringLeadTime]: next-period forecast scaled to lead time
  /// - [safetyStockForecast]: z × σ × √(LT in periods)
  /// - [reorderPointForecast]: demand during LT + safety stock
  ForecastResult generateForecast({
    required String productId,
    required List<DateTime> periods,
    required List<double> demand,
    required String algorithm,
    int smaWindow = 3,
    double alpha = 0.3,
    int leadTimeDays = 0,
    double serviceLevelZ = 1.65,
  }) {
    if (demand.isEmpty) {
      return ForecastResult(
        productId: productId,
        periods: periods,
        actualDemand: demand,
        forecast: [],
        algorithm: algorithm,
      );
    }

    List<double> forecastSeries;
    if (algorithm == 'SES') {
      forecastSeries = singleExponentialSmoothingSeries(demand, alpha);
    } else {
      forecastSeries = simpleMovingAverageSeries(demand, smaWindow);
    }

    // Append the next-period prediction
    final nextForecast = algorithm == 'SES'
        ? singleExponentialSmoothing(demand, alpha)
        : simpleMovingAverage(demand, smaWindow);
    final nextPeriod = periods.isNotEmpty
        ? periods.last.add(const Duration(days: 30))
        : DateTime.now();

    final allPeriods = [...periods, nextPeriod];
    final allActual = [...demand, 0.0]; // 0 = future (unknown)
    final allForecast = [...forecastSeries, nextForecast];

    // Compute MAE and MAPE over historical periods where forecast is non-zero
    final pairs = <_ErrorPair>[];
    for (int i = 0; i < demand.length; i++) {
      if (allForecast[i] > 0) {
        pairs.add(_ErrorPair(demand[i], allForecast[i]));
      }
    }

    double? mae;
    double? mape;
    if (pairs.isNotEmpty) {
      mae =
          pairs
              .map((p) => (p.actual - p.forecast).abs())
              .reduce((a, b) => a + b) /
          pairs.length;
      mape =
          pairs
              .map(
                (p) =>
                    p.actual > 0 ? (p.actual - p.forecast).abs() / p.actual : 0,
              )
              .reduce((a, b) => a + b) /
          pairs.length;
    }

    // ── Lead-time-adjusted metrics ──────────────────────────────────────────
    int? ltDays;
    double? demandDuringLT;
    int? safetyStockFC;
    int? ropFC;

    if (leadTimeDays > 0 && nextForecast > 0) {
      ltDays = leadTimeDays;
      final ltInPeriods = leadTimeDays / 30.0; // periods are ~monthly
      demandDuringLT = nextForecast * ltInPeriods;

      // Std deviation of historical demand
      final avg = demand.reduce((a, b) => a + b) / demand.length;
      final variance =
          demand.map((d) => (d - avg) * (d - avg)).reduce((a, b) => a + b) /
          demand.length;
      final stdDev = sqrt(variance);

      safetyStockFC = (serviceLevelZ * stdDev * sqrt(ltInPeriods)).round();
      ropFC = demandDuringLT.round() + safetyStockFC;
    }

    return ForecastResult(
      productId: productId,
      periods: allPeriods,
      actualDemand: allActual,
      forecast: allForecast,
      mae: mae,
      mape: mape,
      algorithm: algorithm,
      leadTimeDays: ltDays,
      demandDuringLeadTime: demandDuringLT,
      safetyStockForecast: safetyStockFC,
      reorderPointForecast: ropFC,
    );
  }
}

class _ErrorPair {
  final double actual;
  final double forecast;
  _ErrorPair(this.actual, this.forecast);
}

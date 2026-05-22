import 'dart:math';

import 'package:ma5zony/models/forecast_result.dart';

/// Pure-Dart forecasting service implementing multiple demand forecasting
/// algorithms from the academic literature (Silver, Pyke & Peterson;
/// Makridakis, Wheelwright & Hyndman).
///
/// Supported algorithms:
///   - SMA  — Simple Moving Average
///   - WMA  — Weighted Moving Average
///   - SES  — Single Exponential Smoothing
///   - Holt — Holt's Double Exponential Smoothing (linear trend)
///   - HW   — Holt-Winters Triple Exponential Smoothing (trend + seasonality)
class ForecastingService {
  // ══════════════════════════════════════════════════════════════════════════
  // 1. SIMPLE MOVING AVERAGE (SMA)
  // ══════════════════════════════════════════════════════════════════════════

  /// Returns the last SMA value over the provided [windowSize].
  /// When there is less data than [windowSize], averages all the data
  /// available instead of returning 0 — gives a usable estimate for
  /// short demand histories (e.g. 1–2 months of Shopify imports).
  double simpleMovingAverage(List<double> demand, int windowSize) {
    if (demand.isEmpty || windowSize <= 0) return 0;
    final effectiveWindow =
        demand.length < windowSize ? demand.length : windowSize;
    final window = demand.sublist(demand.length - effectiveWindow);
    return window.reduce((a, b) => a + b) / effectiveWindow;
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

  // ══════════════════════════════════════════════════════════════════════════
  // 2. WEIGHTED MOVING AVERAGE (WMA)
  // ══════════════════════════════════════════════════════════════════════════

  /// Returns the last WMA value using the given [weights].
  /// The length of [weights] determines the window size.
  /// Weights are applied in order: weights[0] → oldest, weights[last] → newest.
  /// Weights are normalised internally so they don't need to sum to 1.
  double weightedMovingAverage(List<double> demand, List<double> weights) {
    final n = weights.length;
    if (demand.length < n || n == 0) return 0;
    final window = demand.sublist(demand.length - n);
    final wSum = weights.reduce((a, b) => a + b);
    if (wSum == 0) return 0;
    double total = 0;
    for (int i = 0; i < n; i++) {
      total += window[i] * weights[i];
    }
    return total / wSum;
  }

  /// Returns the full WMA series.
  List<double> weightedMovingAverageSeries(
      List<double> demand, List<double> weights) {
    final n = weights.length;
    final result = <double>[];
    final wSum = weights.reduce((a, b) => a + b);
    for (int i = 0; i < demand.length; i++) {
      if (i < n - 1 || wSum == 0) {
        result.add(0);
      } else {
        final window = demand.sublist(i - n + 1, i + 1);
        double total = 0;
        for (int j = 0; j < n; j++) {
          total += window[j] * weights[j];
        }
        result.add(total / wSum);
      }
    }
    return result;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 3. SINGLE EXPONENTIAL SMOOTHING (SES)
  // ══════════════════════════════════════════════════════════════════════════

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

  // ══════════════════════════════════════════════════════════════════════════
  // 4. HOLT'S DOUBLE EXPONENTIAL SMOOTHING (Linear Trend)
  //    Reference: Makridakis, Wheelwright & Hyndman, Ch. 4
  // ══════════════════════════════════════════════════════════════════════════

  /// Returns the final Holt forecast for the next period.
  ///
  /// [alpha] smooths the level (0 < α ≤ 1).
  /// [beta]  smooths the trend (0 < β ≤ 1).
  double holtDoubleSmoothing(List<double> demand, double alpha, double beta) {
    if (demand.length < 2) return demand.isNotEmpty ? demand.first : 0;

    // Initialise: level = first data point, trend = second minus first
    double level = demand[0];
    double trend = demand[1] - demand[0];

    for (int i = 1; i < demand.length; i++) {
      final prevLevel = level;
      level = alpha * demand[i] + (1 - alpha) * (prevLevel + trend);
      trend = beta * (level - prevLevel) + (1 - beta) * trend;
    }

    // One-step-ahead forecast
    return level + trend;
  }

  /// Returns the full Holt series plus a one-step-ahead forecast.
  List<double> holtDoubleSmoothingSeries(
      List<double> demand, double alpha, double beta) {
    if (demand.isEmpty) return [];
    if (demand.length == 1) return [demand.first];

    final result = <double>[];
    double level = demand[0];
    double trend = demand[1] - demand[0];
    result.add(level); // F(0) = level

    for (int i = 1; i < demand.length; i++) {
      final prevLevel = level;
      level = alpha * demand[i] + (1 - alpha) * (prevLevel + trend);
      trend = beta * (level - prevLevel) + (1 - beta) * trend;
      result.add(prevLevel + trend); // one-step-ahead from previous state
    }

    return result;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 5. HOLT-WINTERS TRIPLE EXPONENTIAL SMOOTHING (Additive Seasonality)
  //    Reference: Makridakis, Wheelwright & Hyndman, Ch. 4
  // ══════════════════════════════════════════════════════════════════════════

  /// Returns the next-period forecast using Holt-Winters additive model.
  ///
  /// Requires at least 2 full seasonal cycles of data.
  /// [seasonLength] = number of periods in one cycle (e.g. 12 for monthly).
  /// [alpha] smooths the level, [beta] smooths the trend, [gamma] smooths
  /// the seasonal component.
  double holtWintersSmoothing(
    List<double> demand,
    double alpha,
    double beta,
    double gamma,
    int seasonLength,
  ) {
    if (demand.length < seasonLength * 2) {
      // Not enough data for seasonal decomposition — fall back to Holt
      return holtDoubleSmoothing(demand, alpha, beta);
    }

    final result = _holtWintersInternal(demand, alpha, beta, gamma, seasonLength);
    return result.nextForecast;
  }

  /// Returns the full Holt-Winters fitted series.
  List<double> holtWintersSmoothingSeries(
    List<double> demand,
    double alpha,
    double beta,
    double gamma,
    int seasonLength,
  ) {
    if (demand.length < seasonLength * 2) {
      return holtDoubleSmoothingSeries(demand, alpha, beta);
    }

    final result = _holtWintersInternal(demand, alpha, beta, gamma, seasonLength);
    return result.fitted;
  }

  /// Internal Holt-Winters computation returning both fitted series and
  /// next-period forecast.
  _HoltWintersResult _holtWintersInternal(
    List<double> demand,
    double alpha,
    double beta,
    double gamma,
    int seasonLength,
  ) {
    final n = demand.length;

    // ── Initialisation ──────────────────────────────────────────────────
    // Level: average of first season
    double level = 0;
    for (int i = 0; i < seasonLength; i++) {
      level += demand[i];
    }
    level /= seasonLength;

    // Trend: average difference between first two seasons
    double trend = 0;
    for (int i = 0; i < seasonLength; i++) {
      trend += (demand[seasonLength + i] - demand[i]);
    }
    trend /= (seasonLength * seasonLength);

    // Seasonal indices: deviation from initial level
    final seasonal = List<double>.filled(n + seasonLength, 0);
    for (int i = 0; i < seasonLength; i++) {
      seasonal[i] = demand[i] - level;
    }

    // ── Iteration ───────────────────────────────────────────────────────
    final fitted = List<double>.filled(n, 0.0);
    fitted[0] = level + trend + seasonal[0];

    for (int i = 1; i < n; i++) {
      final prevLevel = level;
      level = alpha * (demand[i] - seasonal[i]) + (1 - alpha) * (prevLevel + trend);
      trend = beta * (level - prevLevel) + (1 - beta) * trend;
      seasonal[i + seasonLength] =
          gamma * (demand[i] - level) + (1 - gamma) * seasonal[i];
      fitted[i] = level + trend + seasonal[i];
    }

    // One-step-ahead forecast
    final nextForecast = level + trend + seasonal[n];

    return _HoltWintersResult(fitted: fitted, nextForecast: nextForecast);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // AUTO-SELECT BEST ALGORITHM
  // ══════════════════════════════════════════════════════════════════════════

  /// Runs all available algorithms on the given demand series and returns
  /// the [ForecastResult] with the lowest MAPE. Falls back to SMA(3) if
  /// MAPE cannot be computed for any method.
  ForecastResult autoSelectBestForecast({
    required String productId,
    required List<DateTime> periods,
    required List<double> demand,
    int leadTimeDays = 0,
    double serviceLevelZ = 1.65,
  }) {
    final candidates = <ForecastResult>[];

    // SMA with window sizes 3 and 5
    for (final w in [3, 5]) {
      if (demand.length >= w) {
        candidates.add(generateForecast(
          productId: productId,
          periods: periods,
          demand: demand,
          algorithm: 'SMA',
          smaWindow: w,
          leadTimeDays: leadTimeDays,
          serviceLevelZ: serviceLevelZ,
        ));
      }
    }

    // WMA (linearly increasing weights for window=3)
    if (demand.length >= 3) {
      candidates.add(generateForecast(
        productId: productId,
        periods: periods,
        demand: demand,
        algorithm: 'WMA',
        wmaWeights: [1, 2, 3],
        leadTimeDays: leadTimeDays,
        serviceLevelZ: serviceLevelZ,
      ));
    }

    // SES with alpha values
    for (final a in [0.2, 0.3, 0.5]) {
      candidates.add(generateForecast(
        productId: productId,
        periods: periods,
        demand: demand,
        algorithm: 'SES',
        alpha: a,
        leadTimeDays: leadTimeDays,
        serviceLevelZ: serviceLevelZ,
      ));
    }

    // Holt's Double Exponential
    if (demand.length >= 3) {
      candidates.add(generateForecast(
        productId: productId,
        periods: periods,
        demand: demand,
        algorithm: 'Holt',
        alpha: 0.3,
        beta: 0.1,
        leadTimeDays: leadTimeDays,
        serviceLevelZ: serviceLevelZ,
      ));
    }

    // Holt-Winters (monthly seasonality, need ≥ 24 data points)
    if (demand.length >= 24) {
      candidates.add(generateForecast(
        productId: productId,
        periods: periods,
        demand: demand,
        algorithm: 'HoltWinters',
        alpha: 0.3,
        beta: 0.1,
        gamma: 0.2,
        seasonLength: 12,
        leadTimeDays: leadTimeDays,
        serviceLevelZ: serviceLevelZ,
      ));
    }

    // Pick the one with the lowest MAPE
    candidates.sort((a, b) {
      final mA = a.mape ?? double.infinity;
      final mB = b.mape ?? double.infinity;
      return mA.compareTo(mB);
    });

    return candidates.isNotEmpty
        ? candidates.first
        : generateForecast(
            productId: productId,
            periods: periods,
            demand: demand,
            algorithm: 'SMA',
            smaWindow: 3,
            leadTimeDays: leadTimeDays,
            serviceLevelZ: serviceLevelZ,
          );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FORECAST RESULT BUILDER
  // ══════════════════════════════════════════════════════════════════════════

  /// Generates a [ForecastResult] from historical demand.
  /// Appends one future-period forecast at the end.
  ///
  /// Supported [algorithm] values: 'SMA', 'WMA', 'SES', 'Holt', 'HoltWinters'.
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
    List<double> wmaWeights = const [1, 2, 3],
    double alpha = 0.3,
    double beta = 0.1,
    double gamma = 0.2,
    int seasonLength = 12,
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

    // ── Generate forecast series ──────────────────────────────────────────
    List<double> forecastSeries;
    double nextForecast;
    Map<String, double> params;

    switch (algorithm) {
      case 'WMA':
        forecastSeries = weightedMovingAverageSeries(demand, wmaWeights);
        nextForecast = weightedMovingAverage(demand, wmaWeights);
        params = {
          for (int i = 0; i < wmaWeights.length; i++)
            'w${i + 1}': wmaWeights[i],
        };
        break;
      case 'SES':
        forecastSeries = singleExponentialSmoothingSeries(demand, alpha);
        nextForecast = singleExponentialSmoothing(demand, alpha);
        params = {'alpha': alpha};
        break;
      case 'Holt':
        forecastSeries = holtDoubleSmoothingSeries(demand, alpha, beta);
        nextForecast = holtDoubleSmoothing(demand, alpha, beta);
        params = {'alpha': alpha, 'beta': beta};
        break;
      case 'HoltWinters':
        forecastSeries =
            holtWintersSmoothingSeries(demand, alpha, beta, gamma, seasonLength);
        nextForecast =
            holtWintersSmoothing(demand, alpha, beta, gamma, seasonLength);
        params = {
          'alpha': alpha,
          'beta': beta,
          'gamma': gamma,
          'seasonLength': seasonLength.toDouble(),
        };
        break;
      case 'SMA':
      default:
        forecastSeries = simpleMovingAverageSeries(demand, smaWindow);
        nextForecast = simpleMovingAverage(demand, smaWindow);
        params = {'windowSize': smaWindow.toDouble()};
        break;
    }

    // Append the next-period prediction
    final nextPeriod = periods.isNotEmpty
        ? periods.last.add(const Duration(days: 30))
        : DateTime.now();

    final allPeriods = [...periods, nextPeriod];
    final allActual = [...demand, 0.0]; // 0 = future (unknown)
    final allForecast = [...forecastSeries, nextForecast];

    // ── Compute error metrics over historical periods ────────────────────
    final pairs = <_ErrorPair>[];
    for (int i = 0; i < demand.length; i++) {
      if (allForecast[i] > 0) {
        pairs.add(_ErrorPair(demand[i], allForecast[i]));
      }
    }

    double? mae;
    double? mape;
    double? rmse;
    if (pairs.isNotEmpty) {
      mae = pairs
              .map((p) => (p.actual - p.forecast).abs())
              .reduce((a, b) => a + b) /
          pairs.length;
      mape = pairs
              .map(
                (p) =>
                    p.actual > 0 ? (p.actual - p.forecast).abs() / p.actual : 0,
              )
              .reduce((a, b) => a + b) /
          pairs.length;
      rmse = sqrt(
        pairs
                .map((p) => pow(p.actual - p.forecast, 2).toDouble())
                .reduce((a, b) => a + b) /
            pairs.length,
      );
    }

    // ── Confidence intervals (95% CI = ±1.96 × σ of residuals) ──────────
    List<double>? ciUpper;
    List<double>? ciLower;
    if (pairs.length >= 3) {
      final residuals =
          pairs.map((p) => p.actual - p.forecast).toList();
      final resAvg = residuals.reduce((a, b) => a + b) / residuals.length;
      final resVar = residuals
              .map((r) => (r - resAvg) * (r - resAvg))
              .reduce((a, b) => a + b) /
          residuals.length;
      final resStd = sqrt(resVar);
      final margin = 1.96 * resStd;

      ciUpper = allForecast.map((f) => f + margin).toList();
      ciLower = allForecast.map((f) {
        final v = f - margin;
        return v < 0 ? 0.0 : v;
      }).toList();
    }

    // ── Lead-time-adjusted metrics ──────────────────────────────────────
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
      rmse: rmse,
      algorithm: algorithm,
      algorithmParams: params,
      leadTimeDays: ltDays,
      demandDuringLeadTime: demandDuringLT,
      safetyStockForecast: safetyStockFC,
      reorderPointForecast: ropFC,
      confidenceUpper: ciUpper,
      confidenceLower: ciLower,
    );
  }
}

class _ErrorPair {
  final double actual;
  final double forecast;
  _ErrorPair(this.actual, this.forecast);
}

class _HoltWintersResult {
  final List<double> fitted;
  final double nextForecast;
  _HoltWintersResult({required this.fitted, required this.nextForecast});
}

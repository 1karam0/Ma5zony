/// Result of a demand forecasting run for a single product.
///
/// Stores the historical demand, forecasted values, accuracy metrics,
/// algorithm configuration, and optional lead-time-adjusted inventory metrics.
class ForecastResult {
  final String productId;
  final List<DateTime> periods;
  final List<double> actualDemand;
  final List<double> forecast;
  final double? mae;
  final double? mape;
  final double? rmse;
  final String algorithm; // 'SMA', 'SES', 'WMA', 'Holt', 'HoltWinters'
  final Map<String, double> algorithmParams; // e.g. {'alpha': 0.3, 'beta': 0.1}
  final int? leadTimeDays;
  final double? demandDuringLeadTime;
  final int? safetyStockForecast;
  final int? reorderPointForecast;

  /// Upper/lower confidence bounds (±1.96×σ ≈ 95% CI) for forecast values.
  final List<double>? confidenceUpper;
  final List<double>? confidenceLower;

  ForecastResult({
    required this.productId,
    required this.periods,
    required this.actualDemand,
    required this.forecast,
    this.mae,
    this.mape,
    this.rmse,
    required this.algorithm,
    this.algorithmParams = const {},
    this.leadTimeDays,
    this.demandDuringLeadTime,
    this.safetyStockForecast,
    this.reorderPointForecast,
    this.confidenceUpper,
    this.confidenceLower,
  });

  /// Next-period forecast (last value in the forecast list).
  double get nextPeriodForecast => forecast.isNotEmpty ? forecast.last : 0;

  factory ForecastResult.fromJson(Map<String, dynamic> json) {
    return ForecastResult(
      productId: json['productId'] as String,
      periods: (json['periods'] as List<dynamic>)
          .map((e) => DateTime.parse(e as String))
          .toList(),
      actualDemand: (json['actualDemand'] as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList(),
      forecast: (json['forecast'] as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList(),
      mae: (json['mae'] as num?)?.toDouble(),
      mape: (json['mape'] as num?)?.toDouble(),
      rmse: (json['rmse'] as num?)?.toDouble(),
      algorithm: json['algorithm'] as String,
      algorithmParams: (json['algorithmParams'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
          const {},
      leadTimeDays: (json['leadTimeDays'] as num?)?.toInt(),
      demandDuringLeadTime: (json['demandDuringLeadTime'] as num?)?.toDouble(),
      safetyStockForecast: (json['safetyStockForecast'] as num?)?.toInt(),
      reorderPointForecast: (json['reorderPointForecast'] as num?)?.toInt(),
      confidenceUpper: (json['confidenceUpper'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble())
          .toList(),
      confidenceLower: (json['confidenceLower'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'periods': periods.map((d) => d.toIso8601String()).toList(),
      'actualDemand': actualDemand,
      'forecast': forecast,
      'mae': mae,
      'mape': mape,
      'rmse': rmse,
      'algorithm': algorithm,
      'algorithmParams': algorithmParams,
      'leadTimeDays': leadTimeDays,
      'demandDuringLeadTime': demandDuringLeadTime,
      'safetyStockForecast': safetyStockForecast,
      'reorderPointForecast': reorderPointForecast,
      if (confidenceUpper != null) 'confidenceUpper': confidenceUpper,
      if (confidenceLower != null) 'confidenceLower': confidenceLower,
    };
  }
}

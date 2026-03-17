class ForecastResult {
  final String productId;
  final List<DateTime> periods;
  final List<double> actualDemand;
  final List<double> forecast;
  final double? mae;
  final double? mape;
  final String algorithm; // 'SMA' or 'SES'

  ForecastResult({
    required this.productId,
    required this.periods,
    required this.actualDemand,
    required this.forecast,
    this.mae,
    this.mape,
    required this.algorithm,
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
      algorithm: json['algorithm'] as String,
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
      'algorithm': algorithm,
    };
  }
}

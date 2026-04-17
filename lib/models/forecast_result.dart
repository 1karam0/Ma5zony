class ForecastResult {
  final String productId;
  final List<DateTime> periods;
  final List<double> actualDemand;
  final List<double> forecast;
  final double? mae;
  final double? mape;
  final String algorithm; // 'SMA' or 'SES'
  final int? leadTimeDays;
  final double? demandDuringLeadTime;
  final int? safetyStockForecast;
  final int? reorderPointForecast;

  ForecastResult({
    required this.productId,
    required this.periods,
    required this.actualDemand,
    required this.forecast,
    this.mae,
    this.mape,
    required this.algorithm,
    this.leadTimeDays,
    this.demandDuringLeadTime,
    this.safetyStockForecast,
    this.reorderPointForecast,
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
      leadTimeDays: (json['leadTimeDays'] as num?)?.toInt(),
      demandDuringLeadTime: (json['demandDuringLeadTime'] as num?)?.toDouble(),
      safetyStockForecast: (json['safetyStockForecast'] as num?)?.toInt(),
      reorderPointForecast: (json['reorderPointForecast'] as num?)?.toInt(),
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
      'leadTimeDays': leadTimeDays,
      'demandDuringLeadTime': demandDuringLeadTime,
      'safetyStockForecast': safetyStockForecast,
      'reorderPointForecast': reorderPointForecast,
    };
  }
}

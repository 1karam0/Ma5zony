/// A single replenishment recommendation for a product.
///
/// Contains the analysis results from the forecasting and inventory policy
/// pipeline, along with actionable ordering guidance.
class ReplenishmentRecommendation {
  final String productId;
  final String productName;
  final String sku;
  final int currentStock;
  final int forecastNextPeriod;
  final int reorderPoint;
  final int suggestedOrderQty;
  final DateTime recommendedOrderDate;

  /// Urgency level: 'Critical', 'Warning', or 'Normal'
  final String urgency;

  /// ABC-XYZ classification label (e.g. 'AX', 'BY', 'CZ')
  final String? abcXyzClass;

  /// Which forecasting algorithm was used
  final String? algorithmUsed;

  /// Safety stock component
  final int? safetyStock;

  /// EOQ value used
  final double? eoq;

  ReplenishmentRecommendation({
    required this.productId,
    required this.productName,
    required this.sku,
    required this.currentStock,
    required this.forecastNextPeriod,
    required this.reorderPoint,
    required this.suggestedOrderQty,
    required this.recommendedOrderDate,
    this.urgency = 'Normal',
    this.abcXyzClass,
    this.algorithmUsed,
    this.safetyStock,
    this.eoq,
  });

  String get status {
    if (currentStock == 0) return 'Critical';
    if (currentStock <= reorderPoint) return 'Order Now';
    return 'Monitor';
  }

  double estimatedCost(double unitCost) => suggestedOrderQty * unitCost;

  ReplenishmentRecommendation copyWith({int? suggestedOrderQty}) {
    return ReplenishmentRecommendation(
      productId: productId,
      productName: productName,
      sku: sku,
      currentStock: currentStock,
      forecastNextPeriod: forecastNextPeriod,
      reorderPoint: reorderPoint,
      suggestedOrderQty: suggestedOrderQty ?? this.suggestedOrderQty,
      recommendedOrderDate: recommendedOrderDate,
      urgency: urgency,
      abcXyzClass: abcXyzClass,
      algorithmUsed: algorithmUsed,
      safetyStock: safetyStock,
      eoq: eoq,
    );
  }

  factory ReplenishmentRecommendation.fromJson(Map<String, dynamic> json) {
    return ReplenishmentRecommendation(
      productId: json['productId'] as String,
      productName: json['productName'] as String,
      sku: json['sku'] as String,
      currentStock: (json['currentStock'] as num).toInt(),
      forecastNextPeriod: (json['forecastNextPeriod'] as num).toInt(),
      reorderPoint: (json['reorderPoint'] as num).toInt(),
      suggestedOrderQty: (json['suggestedOrderQty'] as num).toInt(),
      recommendedOrderDate: DateTime.parse(
        json['recommendedOrderDate'] as String,
      ),
      urgency: json['urgency'] as String? ?? 'Normal',
      abcXyzClass: json['abcXyzClass'] as String?,
      algorithmUsed: json['algorithmUsed'] as String?,
      safetyStock: (json['safetyStock'] as num?)?.toInt(),
      eoq: (json['eoq'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'productName': productName,
      'sku': sku,
      'currentStock': currentStock,
      'forecastNextPeriod': forecastNextPeriod,
      'reorderPoint': reorderPoint,
      'suggestedOrderQty': suggestedOrderQty,
      'recommendedOrderDate': recommendedOrderDate.toIso8601String(),
      'urgency': urgency,
      if (abcXyzClass != null) 'abcXyzClass': abcXyzClass,
      if (algorithmUsed != null) 'algorithmUsed': algorithmUsed,
      if (safetyStock != null) 'safetyStock': safetyStock,
      if (eoq != null) 'eoq': eoq,
    };
  }
}

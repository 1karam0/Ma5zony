class ReplenishmentRecommendation {
  final String productId;
  final String productName;
  final String sku;
  final int currentStock;
  final int forecastNextPeriod;
  final int reorderPoint;
  final int suggestedOrderQty;
  final DateTime recommendedOrderDate;

  ReplenishmentRecommendation({
    required this.productId,
    required this.productName,
    required this.sku,
    required this.currentStock,
    required this.forecastNextPeriod,
    required this.reorderPoint,
    required this.suggestedOrderQty,
    required this.recommendedOrderDate,
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
    };
  }
}

class InventoryPolicy {
  final String productId;
  final double eoq;
  final int reorderPoint;
  final int safetyStock;
  final double annualDemand;
  final double orderingCost;
  final double holdingCost;

  InventoryPolicy({
    required this.productId,
    required this.eoq,
    required this.reorderPoint,
    required this.safetyStock,
    required this.annualDemand,
    required this.orderingCost,
    required this.holdingCost,
  });

  factory InventoryPolicy.fromJson(Map<String, dynamic> json) {
    return InventoryPolicy(
      productId: json['productId'] as String,
      eoq: (json['eoq'] as num).toDouble(),
      reorderPoint: (json['reorderPoint'] as num).toInt(),
      safetyStock: (json['safetyStock'] as num).toInt(),
      annualDemand: (json['annualDemand'] as num).toDouble(),
      orderingCost: (json['orderingCost'] as num).toDouble(),
      holdingCost: (json['holdingCost'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'eoq': eoq,
      'reorderPoint': reorderPoint,
      'safetyStock': safetyStock,
      'annualDemand': annualDemand,
      'orderingCost': orderingCost,
      'holdingCost': holdingCost,
    };
  }
}

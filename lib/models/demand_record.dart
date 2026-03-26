class DomainDemandRecord {
  final String id;
  final String productId;
  final DateTime periodStart;
  final int quantity;
  final String source; // 'manual' or 'shopify'
  final String? shopifyOrderId;

  DomainDemandRecord({
    required this.id,
    required this.productId,
    required this.periodStart,
    required this.quantity,
    this.source = 'manual',
    this.shopifyOrderId,
  });

  factory DomainDemandRecord.fromJson(Map<String, dynamic> json) {
    return DomainDemandRecord(
      id: json['id'] as String,
      productId: json['productId'] as String,
      periodStart: DateTime.parse(json['periodStart'] as String),
      quantity: (json['quantity'] as num).toInt(),
      source: json['source'] as String? ?? 'manual',
      shopifyOrderId: json['shopifyOrderId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'productId': productId,
      'periodStart': periodStart.toIso8601String(),
      'quantity': quantity,
      'source': source,
      if (shopifyOrderId != null) 'shopifyOrderId': shopifyOrderId,
    };
  }
}

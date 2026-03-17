class DomainDemandRecord {
  final String id;
  final String productId;
  final DateTime periodStart;
  final int quantity;

  DomainDemandRecord({
    required this.id,
    required this.productId,
    required this.periodStart,
    required this.quantity,
  });

  factory DomainDemandRecord.fromJson(Map<String, dynamic> json) {
    return DomainDemandRecord(
      id: json['id'] as String,
      productId: json['productId'] as String,
      periodStart: DateTime.parse(json['periodStart'] as String),
      quantity: (json['quantity'] as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'productId': productId,
      'periodStart': periodStart.toIso8601String(),
      'quantity': quantity,
    };
  }
}

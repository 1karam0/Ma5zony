import 'package:cloud_firestore/cloud_firestore.dart';

class SupplierOrderItem {
  final String productId;
  final String productName;
  final String sku;
  final int quantity;
  final double unitCost;

  SupplierOrderItem({
    required this.productId,
    required this.productName,
    required this.sku,
    required this.quantity,
    required this.unitCost,
  });

  double get estimatedCost => quantity * unitCost;

  factory SupplierOrderItem.fromJson(Map<String, dynamic> json) {
    return SupplierOrderItem(
      productId: json['productId'] as String,
      productName: json['productName'] as String,
      sku: json['sku'] as String,
      quantity: (json['quantity'] as num).toInt(),
      unitCost: (json['unitCost'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'productName': productName,
        'sku': sku,
        'quantity': quantity,
        'unitCost': unitCost,
      };
}

class SupplierResponse {
  final int? estimatedDeliveryDays;
  final double? totalCost;
  final String? notes;
  final DateTime respondedAt;

  SupplierResponse({
    this.estimatedDeliveryDays,
    this.totalCost,
    this.notes,
    required this.respondedAt,
  });

  factory SupplierResponse.fromJson(Map<String, dynamic> json) {
    return SupplierResponse(
      estimatedDeliveryDays: (json['estimatedDeliveryDays'] as num?)?.toInt(),
      totalCost: (json['totalCost'] as num?)?.toDouble(),
      notes: json['notes'] as String?,
      respondedAt: json['respondedAt'] is Timestamp
          ? (json['respondedAt'] as Timestamp).toDate()
          : DateTime.parse(json['respondedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'estimatedDeliveryDays': estimatedDeliveryDays,
        'totalCost': totalCost,
        'notes': notes,
        'respondedAt': Timestamp.fromDate(respondedAt),
      };
}

class SupplierOrder {
  final String id;
  final String purchaseOrderId;
  final String ownerUid;
  final String supplierId;
  final String supplierName;
  final String supplierEmail;
  String status; // pending, acknowledged, in_progress, shipped, delivered
  final DateTime createdAt;
  final List<SupplierOrderItem> items;
  SupplierResponse? response;
  final String accessToken;

  SupplierOrder({
    required this.id,
    required this.purchaseOrderId,
    required this.ownerUid,
    required this.supplierId,
    required this.supplierName,
    required this.supplierEmail,
    this.status = 'pending',
    required this.createdAt,
    required this.items,
    this.response,
    required this.accessToken,
  });

  double get totalEstimatedCost =>
      items.fold(0.0, (sum, i) => sum + i.estimatedCost);

  factory SupplierOrder.fromFirestore(String id, Map<String, dynamic> data) {
    final itemsList = (data['items'] as List<dynamic>?)
            ?.map((e) =>
                SupplierOrderItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return SupplierOrder(
      id: id,
      purchaseOrderId: data['purchaseOrderId'] as String,
      ownerUid: data['ownerUid'] as String,
      supplierId: data['supplierId'] as String,
      supplierName: data['supplierName'] as String,
      supplierEmail: data['supplierEmail'] as String,
      status: data['status'] as String? ?? 'pending',
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.parse(data['createdAt'] as String),
      items: itemsList,
      response: data['response'] != null
          ? SupplierResponse.fromJson(
              data['response'] as Map<String, dynamic>)
          : null,
      accessToken: data['accessToken'] as String,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'purchaseOrderId': purchaseOrderId,
        'ownerUid': ownerUid,
        'supplierId': supplierId,
        'supplierName': supplierName,
        'supplierEmail': supplierEmail,
        'status': status,
        'createdAt': Timestamp.fromDate(createdAt),
        'items': items.map((i) => i.toJson()).toList(),
        'response': response?.toJson(),
        'accessToken': accessToken,
      };
}

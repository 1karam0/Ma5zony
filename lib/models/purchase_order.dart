import 'package:cloud_firestore/cloud_firestore.dart';

enum OrderStatus { draft, confirmed, sent, partiallyFulfilled, completed, cancelled }

class PurchaseOrderItem {
  final String productId;
  final String productName;
  final String sku;
  final String? supplierId;
  final String? supplierName;
  final String? supplierEmail;
  int quantity;
  final double unitCost;

  PurchaseOrderItem({
    required this.productId,
    required this.productName,
    required this.sku,
    this.supplierId,
    this.supplierName,
    this.supplierEmail,
    required this.quantity,
    required this.unitCost,
  });

  double get estimatedCost => quantity * unitCost;

  factory PurchaseOrderItem.fromJson(Map<String, dynamic> json) {
    return PurchaseOrderItem(
      productId: json['productId'] as String,
      productName: json['productName'] as String,
      sku: json['sku'] as String,
      supplierId: json['supplierId'] as String?,
      supplierName: json['supplierName'] as String?,
      supplierEmail: json['supplierEmail'] as String?,
      quantity: (json['quantity'] as num).toInt(),
      unitCost: (json['unitCost'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'productName': productName,
        'sku': sku,
        'supplierId': supplierId,
        'supplierName': supplierName,
        'supplierEmail': supplierEmail,
        'quantity': quantity,
        'unitCost': unitCost,
      };
}

class PurchaseOrder {
  final String id;
  OrderStatus status;
  final DateTime createdAt;
  final String createdByUid;
  final String createdByName;
  final List<PurchaseOrderItem> items;
  String? notes;

  PurchaseOrder({
    required this.id,
    this.status = OrderStatus.draft,
    required this.createdAt,
    required this.createdByUid,
    required this.createdByName,
    required this.items,
    this.notes,
  });

  double get totalEstimatedCost =>
      items.fold(0.0, (acc, i) => acc + i.estimatedCost);

  int get totalItems => items.length;

  int get totalQuantity => items.fold(0, (acc, i) => acc + i.quantity);

  /// Group items by supplierId for splitting into supplier orders.
  Map<String?, List<PurchaseOrderItem>> get itemsBySupplier {
    final map = <String?, List<PurchaseOrderItem>>{};
    for (final item in items) {
      map.putIfAbsent(item.supplierId, () => []).add(item);
    }
    return map;
  }

  factory PurchaseOrder.fromFirestore(String id, Map<String, dynamic> data) {
    final itemsList = (data['items'] as List<dynamic>?)
            ?.map((e) =>
                PurchaseOrderItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return PurchaseOrder(
      id: id,
      status: OrderStatus.values.firstWhere(
        (e) => e.name == (data['status'] as String? ?? 'draft'),
        orElse: () => OrderStatus.draft,
      ),
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.parse(data['createdAt'] as String),
      createdByUid: data['createdByUid'] as String,
      createdByName: data['createdByName'] as String,
      items: itemsList,
      notes: data['notes'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'status': status.name,
        'createdAt': Timestamp.fromDate(createdAt),
        'createdByUid': createdByUid,
        'createdByName': createdByName,
        'items': items.map((i) => i.toJson()).toList(),
        'notes': notes,
      };
}

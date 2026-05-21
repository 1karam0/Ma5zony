import 'package:cloud_firestore/cloud_firestore.dart';

class RawMaterialLineItem {
  final String rawMaterialId;
  final String rawMaterialName;
  final double quantityOrdered;
  final String unitOfMeasure;
  final double unitCost;

  RawMaterialLineItem({
    required this.rawMaterialId,
    required this.rawMaterialName,
    required this.quantityOrdered,
    required this.unitOfMeasure,
    required this.unitCost,
  });

  double get totalCost => quantityOrdered * unitCost;

  factory RawMaterialLineItem.fromJson(Map<String, dynamic> json) {
    return RawMaterialLineItem(
      rawMaterialId: json['rawMaterialId'] as String,
      rawMaterialName: json['rawMaterialName'] as String? ?? '',
      quantityOrdered: (json['quantityOrdered'] as num).toDouble(),
      unitOfMeasure: json['unitOfMeasure'] as String? ?? 'units',
      unitCost: (json['unitCost'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'rawMaterialId': rawMaterialId,
        'rawMaterialName': rawMaterialName,
        'quantityOrdered': quantityOrdered,
        'unitOfMeasure': unitOfMeasure,
        'unitCost': unitCost,
      };
}

class RawMaterialPurchaseOrder {
  final String id;
  final String supplierId;
  final String supplierName;
  final String? productionOrderId;
  final String? forecastProductId;
  final List<RawMaterialLineItem> items;
  String status; // draft | sent | received | cancelled
  final DateTime createdAt;
  final String? ownerUid;

  RawMaterialPurchaseOrder({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    this.productionOrderId,
    this.forecastProductId,
    required this.items,
    this.status = 'draft',
    required this.createdAt,
    this.ownerUid,
  });

  double get totalCost => items.fold(0, (acc, i) => acc + i.totalCost);

  factory RawMaterialPurchaseOrder.fromFirestore(
      String id, Map<String, dynamic> data) {
    final itemsList = (data['items'] as List<dynamic>?)
            ?.map((e) => RawMaterialLineItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return RawMaterialPurchaseOrder(
      id: id,
      supplierId: data['supplierId'] as String? ?? '',
      supplierName: data['supplierName'] as String? ?? '',
      productionOrderId: data['productionOrderId'] as String?,
      forecastProductId: data['forecastProductId'] as String?,
      items: itemsList,
      status: data['status'] as String? ?? 'draft',
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.tryParse(data['createdAt'] as String? ?? '') ??
              DateTime.now(),
      ownerUid: data['ownerUid'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'supplierId': supplierId,
      'supplierName': supplierName,
      if (productionOrderId != null) 'productionOrderId': productionOrderId,
      if (forecastProductId != null) 'forecastProductId': forecastProductId,
      'items': items.map((i) => i.toJson()).toList(),
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      if (ownerUid != null) 'ownerUid': ownerUid,
    };
  }
}

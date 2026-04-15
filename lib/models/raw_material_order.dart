import 'package:cloud_firestore/cloud_firestore.dart';

class RawMaterialOrder {
  final String id;
  final String productionOrderId;
  final String rawMaterialId;
  final String supplierId;
  final int quantity;
  String status; // pending, accepted, in_progress, completed
  final DateTime requestedDate;
  DateTime? completedDate;
  final String accessToken;

  RawMaterialOrder({
    required this.id,
    required this.productionOrderId,
    required this.rawMaterialId,
    required this.supplierId,
    required this.quantity,
    this.status = 'pending',
    required this.requestedDate,
    this.completedDate,
    required this.accessToken,
  });

  factory RawMaterialOrder.fromFirestore(
      String id, Map<String, dynamic> data) {
    return RawMaterialOrder(
      id: id,
      productionOrderId: data['productionOrderId'] as String? ?? '',
      rawMaterialId: data['rawMaterialId'] as String? ?? '',
      supplierId: data['supplierId'] as String? ?? '',
      quantity: (data['quantity'] as num?)?.toInt() ?? 0,
      status: data['status'] as String? ?? 'pending',
      requestedDate: data['requestedDate'] is Timestamp
          ? (data['requestedDate'] as Timestamp).toDate()
          : DateTime.parse(data['requestedDate'] as String),
      completedDate: data['completedDate'] != null
          ? (data['completedDate'] is Timestamp
              ? (data['completedDate'] as Timestamp).toDate()
              : DateTime.parse(data['completedDate'] as String))
          : null,
      accessToken: data['accessToken'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'productionOrderId': productionOrderId,
      'rawMaterialId': rawMaterialId,
      'supplierId': supplierId,
      'quantity': quantity,
      'status': status,
      'requestedDate': Timestamp.fromDate(requestedDate),
      if (completedDate != null)
        'completedDate': Timestamp.fromDate(completedDate!),
      'accessToken': accessToken,
    };
  }
}

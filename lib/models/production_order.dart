import 'package:cloud_firestore/cloud_firestore.dart';

enum ProductionOrderStatus {
  draft,
  approved,
  materialsOrdered,
  materialsReady,
  inProduction,
  completed,
}

class ProductionOrder {
  final String id;
  final String finalProductId;
  final int quantity;
  ProductionOrderStatus status;
  final String manufacturerId;
  final List<String> rawMaterialOrderIds;
  final DateTime createdAt;
  DateTime? completedAt;
  final double estimatedCost;
  DateTime? estimatedCompletionDate;

  ProductionOrder({
    required this.id,
    required this.finalProductId,
    required this.quantity,
    this.status = ProductionOrderStatus.draft,
    required this.manufacturerId,
    this.rawMaterialOrderIds = const [],
    required this.createdAt,
    this.completedAt,
    required this.estimatedCost,
    this.estimatedCompletionDate,
  });

  factory ProductionOrder.fromFirestore(
      String id, Map<String, dynamic> data) {
    return ProductionOrder(
      id: id,
      finalProductId: data['finalProductId'] as String? ?? '',
      quantity: (data['quantity'] as num?)?.toInt() ?? 0,
      status: _parseStatus(data['status'] as String? ?? 'draft'),
      manufacturerId: data['manufacturerId'] as String? ?? '',
      rawMaterialOrderIds:
          (data['rawMaterialOrderIds'] as List<dynamic>?)
                  ?.map((e) => e as String)
                  .toList() ??
              [],
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.parse(data['createdAt'] as String),
      completedAt: data['completedAt'] != null
          ? (data['completedAt'] is Timestamp
              ? (data['completedAt'] as Timestamp).toDate()
              : DateTime.parse(data['completedAt'] as String))
          : null,
      estimatedCost: (data['estimatedCost'] as num?)?.toDouble() ?? 0,
      estimatedCompletionDate: data['estimatedCompletionDate'] != null
          ? (data['estimatedCompletionDate'] is Timestamp
              ? (data['estimatedCompletionDate'] as Timestamp).toDate()
              : DateTime.parse(data['estimatedCompletionDate'] as String))
          : null,
    );
  }

  static const _statusToFirestore = {
    ProductionOrderStatus.draft: 'draft',
    ProductionOrderStatus.approved: 'approved',
    ProductionOrderStatus.materialsOrdered: 'materials_ordered',
    ProductionOrderStatus.materialsReady: 'materials_ready',
    ProductionOrderStatus.inProduction: 'in_production',
    ProductionOrderStatus.completed: 'completed',
  };

  static const _statusFromFirestore = {
    'draft': ProductionOrderStatus.draft,
    'approved': ProductionOrderStatus.approved,
    'materials_ordered': ProductionOrderStatus.materialsOrdered,
    'materials_ready': ProductionOrderStatus.materialsReady,
    'in_production': ProductionOrderStatus.inProduction,
    'completed': ProductionOrderStatus.completed,
  };

  static ProductionOrderStatus _parseStatus(String value) =>
      _statusFromFirestore[value] ?? ProductionOrderStatus.draft;

  Map<String, dynamic> toFirestore() {
    return {
      'finalProductId': finalProductId,
      'quantity': quantity,
      'status': _statusToFirestore[status] ?? 'draft',
      'manufacturerId': manufacturerId,
      'rawMaterialOrderIds': rawMaterialOrderIds,
      'createdAt': Timestamp.fromDate(createdAt),
      if (completedAt != null)
        'completedAt': Timestamp.fromDate(completedAt!),
      'estimatedCost': estimatedCost,
      if (estimatedCompletionDate != null)
        'estimatedCompletionDate':
            Timestamp.fromDate(estimatedCompletionDate!),
    };
  }
}

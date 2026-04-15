import 'package:cloud_firestore/cloud_firestore.dart';

class WorkflowLog {
  final String id;
  final String entityType;
  final String entityId;
  final String action;
  final String performedBy;
  final DateTime timestamp;
  final String? details;

  WorkflowLog({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.performedBy,
    required this.timestamp,
    this.details,
  });

  factory WorkflowLog.fromFirestore(String id, Map<String, dynamic> data) {
    return WorkflowLog(
      id: id,
      entityType: data['entityType'] as String? ?? '',
      entityId: data['entityId'] as String? ?? '',
      action: data['action'] as String? ?? '',
      performedBy: data['performedBy'] as String? ?? '',
      timestamp: data['timestamp'] is Timestamp
          ? (data['timestamp'] as Timestamp).toDate()
          : DateTime.parse(data['timestamp'] as String),
      details: data['details'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'entityType': entityType,
      'entityId': entityId,
      'action': action,
      'performedBy': performedBy,
      'timestamp': Timestamp.fromDate(timestamp),
      if (details != null) 'details': details,
    };
  }
}

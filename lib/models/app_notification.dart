import 'package:cloud_firestore/cloud_firestore.dart';

/// Types of notifications the system generates.
enum NotificationType {
  lowStock,
  stockout,
  orderApproved,
  shopifySync,
  forecastReady,
  general,
}

/// A single notification stored in Firestore `users/{uid}/notifications/{id}`.
class AppNotification {
  final String id;
  final NotificationType type;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool isRead;
  /// Optional deep-link path (e.g. '/products', '/replenishment').
  final String? actionRoute;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.createdAt,
    this.isRead = false,
    this.actionRoute,
  });

  factory AppNotification.fromFirestore(String id, Map<String, dynamic> data) {
    return AppNotification(
      id: id,
      type: _parseType(data['type'] as String?),
      title: data['title'] as String? ?? '',
      message: data['message'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRead: data['isRead'] as bool? ?? false,
      actionRoute: data['actionRoute'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'type': type.name,
      'title': title,
      'message': message,
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': isRead,
      if (actionRoute != null) 'actionRoute': actionRoute,
    };
  }

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      type: type,
      title: title,
      message: message,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
      actionRoute: actionRoute,
    );
  }

  static NotificationType _parseType(String? value) {
    switch (value) {
      case 'lowStock':
        return NotificationType.lowStock;
      case 'stockout':
        return NotificationType.stockout;
      case 'orderApproved':
        return NotificationType.orderApproved;
      case 'shopifySync':
        return NotificationType.shopifySync;
      case 'forecastReady':
        return NotificationType.forecastReady;
      default:
        return NotificationType.general;
    }
  }
}

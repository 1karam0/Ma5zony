import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ma5zony/models/app_notification.dart';

/// Manages reading, writing, and listening to Firestore notifications.
///
/// Path: `users/{uid}/notifications/{notifId}`
class NotificationService {
  final String uid;
  late final CollectionReference<Map<String, dynamic>> _collection;

  NotificationService({required this.uid}) {
    _collection = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications');
  }

  /// Real-time stream of the 50 most recent notifications.
  Stream<List<AppNotification>> stream() {
    return _collection
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => AppNotification.fromFirestore(doc.id, doc.data()))
            .toList());
  }

  /// Add a notification.
  Future<void> add(AppNotification notification) async {
    await _collection.add(notification.toFirestore());
  }

  /// Mark a single notification as read.
  Future<void> markRead(String notifId) async {
    await _collection.doc(notifId).update({'isRead': true});
  }

  /// Mark all unread notifications as read.
  Future<void> markAllRead() async {
    final unread =
        await _collection.where('isRead', isEqualTo: false).get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  /// Delete a single notification.
  Future<void> delete(String notifId) async {
    await _collection.doc(notifId).delete();
  }

  /// Create a low-stock notification for a product.
  Future<void> notifyLowStock(String productName, int currentStock) async {
    await add(AppNotification(
      id: '',
      type: NotificationType.lowStock,
      title: 'Low Stock Alert',
      message: '$productName is running low ($currentStock units remaining).',
      createdAt: DateTime.now(),
      actionRoute: '/replenishment',
    ));
  }

  /// Create a stockout notification.
  Future<void> notifyStockout(String productName) async {
    await add(AppNotification(
      id: '',
      type: NotificationType.stockout,
      title: 'Stockout Warning',
      message: '$productName is out of stock!',
      createdAt: DateTime.now(),
      actionRoute: '/replenishment',
    ));
  }

  /// Create a Shopify sync completion notification.
  Future<void> notifyShopifySync(int importedCount) async {
    await add(AppNotification(
      id: '',
      type: NotificationType.shopifySync,
      title: 'Shopify Sync Complete',
      message: 'Imported $importedCount order records from Shopify.',
      createdAt: DateTime.now(),
      actionRoute: '/demand-data',
    ));
  }
}

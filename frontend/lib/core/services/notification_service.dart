import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/app_notification.dart';

/// manages in-app notifications (reminders, alerts) for owner/client/employee recipients
class NotificationService {
  NotificationService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _collection =
      _firestore.collection('notifications');

  /// stream all notifications for one recipient, newest first
  static Stream<List<AppNotification>> watchForRecipient(String recipientRole, String recipientId) {
    return _collection
        .where('recipientRole', isEqualTo: recipientRole)
        .where('recipientId', isEqualTo: recipientId)
        .snapshots()
        .map((snapshot) {
      final notifications =
          snapshot.docs.map((doc) => AppNotification.fromMap({...doc.data(), 'id': doc.id})).toList();
      notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return notifications;
    });
  }

  static Future<void> create({
    required String recipientRole,
    required String recipientId,
    required String type,
    required String title,
    required String body,
    String? relatedId,
  }) async {
    final doc = _collection.doc();
    final notification = AppNotification(
      id: doc.id,
      recipientRole: recipientRole,
      recipientId: recipientId,
      type: type,
      title: title,
      body: body,
      relatedId: relatedId,
      createdAt: DateTime.now(),
    );
    await doc.set(notification.toMap());
  }

  static Future<void> markRead(String id) async {
    await _collection.doc(id).set({'isRead': true}, SetOptions(merge: true));
  }

  static Future<void> markAllRead(String recipientRole, String recipientId) async {
    final snapshot = await _collection
        .where('recipientRole', isEqualTo: recipientRole)
        .where('recipientId', isEqualTo: recipientId)
        .where('isRead', isEqualTo: false)
        .get();
    if (snapshot.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.set(doc.reference, {'isRead': true}, SetOptions(merge: true));
    }
    await batch.commit();
  }
}

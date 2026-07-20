import 'package:cloud_firestore/cloud_firestore.dart';

/// an in-app notification (reminder, alert) for a specific recipient
class AppNotification {
  const AppNotification({
    required this.id,
    required this.recipientRole,
    required this.recipientId,
    required this.type,
    required this.title,
    required this.body,
    this.relatedId,
    required this.createdAt,
    this.isRead = false,
  });

  final String id;
  /// 'owner', 'client', or 'employee'
  final String recipientRole;
  /// clientId/employeeId for client/employee recipients; a constant id for the owner
  final String recipientId;
  final String type;
  final String title;
  final String body;
  /// the workId/invoiceId this notification deep-links to, if any
  final String? relatedId;
  final DateTime createdAt;
  final bool isRead;

  /// create notification instance from firestore map data
  factory AppNotification.fromMap(Map<String, dynamic> map) {
    DateTime readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      return DateTime.now();
    }

    return AppNotification(
      id: (map['id'] as String? ?? '').trim(),
      recipientRole: (map['recipientRole'] as String? ?? '').trim(),
      recipientId: (map['recipientId'] as String? ?? '').trim(),
      type: (map['type'] as String? ?? '').trim(),
      title: (map['title'] as String? ?? '').trim(),
      body: (map['body'] as String? ?? '').trim(),
      relatedId: (map['relatedId'] as String?)?.trim(),
      createdAt: readDate(map['createdAt']),
      isRead: map['isRead'] as bool? ?? false,
    );
  }

  /// convert notification instance to firestore map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'recipientRole': recipientRole,
      'recipientId': recipientId,
      'type': type,
      'title': title,
      'body': body,
      'relatedId': relatedId,
      'createdAt': createdAt,
      'isRead': isRead,
    };
  }
}

/// plain string constants for notification types, matching this codebase's
/// InvoiceStatus/ScheduledWorkStatus convention
class NotificationType {
  static const appointmentReminder = 'appointmentReminder';
  static const invoiceOverdue = 'invoiceOverdue';
  static const serviceDue = 'serviceDue';
  static const lowStock = 'lowStock';
}

/// constant recipientId used for owner-targeted notifications (the owner has
/// no per-user id anywhere else in this app either — see the hardcoded owner
/// password/session pattern)
const String ownerNotificationRecipientId = 'owner';

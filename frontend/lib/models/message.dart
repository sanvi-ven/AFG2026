import 'package:cloud_firestore/cloud_firestore.dart';

class MessageLog {
  const MessageLog({
    required this.id,
    required this.broadcastId,
    required this.senderRole,
    required this.targetClientId,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
    this.readAt,
  });

  final String id;
  final String broadcastId;
  final String senderRole;
  final String targetClientId;
  final String title;
  final String body;
  final bool read;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => !read;

  factory MessageLog.fromMap(Map<String, dynamic> map) {
    DateTime readDate(dynamic value) {
      if (value is Timestamp) {
        return value.toDate();
      }
      if (value is String) {
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    DateTime? readOptionalDate(dynamic value) {
      if (value == null) {
        return null;
      }
      if (value is Timestamp) {
        return value.toDate();
      }
      if (value is String) {
        return DateTime.tryParse(value);
      }
      return null;
    }

    return MessageLog(
      id: (map['id'] as String? ?? '').trim(),
      broadcastId: (map['broadcastId'] as String? ?? '').trim(),
      senderRole: (map['senderRole'] as String? ?? 'owner').trim(),
      targetClientId: (map['targetClientId'] as String? ?? '').trim(),
      title: (map['title'] as String? ?? '').trim(),
      body: (map['body'] as String? ?? '').trim(),
      read: map['read'] as bool? ?? false,
      createdAt: readDate(map['createdAt']),
      readAt: readOptionalDate(map['readAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'broadcastId': broadcastId,
      'senderRole': senderRole,
      'targetClientId': targetClientId,
      'title': title,
      'body': body,
      'read': read,
      'createdAt': createdAt,
      'readAt': readAt,
    };
  }
}

class OwnerBroadcastSummary {
  const OwnerBroadcastSummary({
    required this.broadcastId,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.recipientCount,
    required this.readCount,
  });

  final String broadcastId;
  final String title;
  final String body;
  final DateTime createdAt;
  final int recipientCount;
  final int readCount;
}

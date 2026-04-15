import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/message.dart';

class MessageService {
  MessageService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _collection =
      _firestore.collection('client_messages');

  static Stream<List<MessageLog>> watchClientMessages({required String clientId}) {
    return _collection.where('targetClientId', isEqualTo: clientId.trim()).snapshots().map((snapshot) {
      final messages = snapshot.docs.map((doc) {
        final data = doc.data();
        return MessageLog.fromMap({...data, 'id': doc.id});
      }).toList();
      messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return messages;
    });
  }

  static Stream<List<OwnerBroadcastSummary>> watchOwnerBroadcasts() {
    return _collection.where('senderRole', isEqualTo: 'owner').snapshots().map((snapshot) {
      final grouped = <String, List<MessageLog>>{};
      for (final doc in snapshot.docs) {
        final message = MessageLog.fromMap({...doc.data(), 'id': doc.id});
        grouped.putIfAbsent(message.broadcastId, () => <MessageLog>[]).add(message);
      }

      final summaries = grouped.entries.map((entry) {
        final logs = entry.value;
        logs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final first = logs.first;
        final readCount = logs.where((item) => item.read).length;
        return OwnerBroadcastSummary(
          broadcastId: entry.key,
          title: first.title,
          body: first.body,
          createdAt: first.createdAt,
          recipientCount: logs.length,
          readCount: readCount,
        );
      }).toList();

      summaries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return summaries;
    });
  }
//learned through chatgpt prompt: i have a list of firestore message documents in flutter. how can i group them by a category (broadcastId) and create a summary object with counts
  static Future<int> sendBroadcast({
    required String title,
    required String body,
    required List<String> clientIds,
  }) async {
    final normalized = clientIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet().toList();
    if (normalized.isEmpty) {
      throw Exception('At least one valid client ID is required.');
    }

    final now = DateTime.now();
    final broadcastId = _collection.doc().id;
    final batch = _firestore.batch();

    for (final clientId in normalized) {
      final doc = _collection.doc();
      final message = MessageLog(
        id: doc.id,
        broadcastId: broadcastId,
        senderRole: 'owner',
        targetClientId: clientId,
        title: title.trim(),
        body: body.trim(),
        read: false,
        createdAt: now,
      );
      batch.set(doc, message.toMap());
    }

    await batch.commit();
    return normalized.length;
  }

  static Future<void> markAsRead({required String messageId}) async {
    await _collection.doc(messageId).set(
      {
        'read': true,
        'readAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> markAllAsRead({required String clientId}) async {
    final snapshot = await _collection
        .where('targetClientId', isEqualTo: clientId.trim())
        .where('read', isEqualTo: false)
        .get();

    if (snapshot.docs.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.set(
        doc.reference,
        {
          'read': true,
          'readAt': now,
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }
}

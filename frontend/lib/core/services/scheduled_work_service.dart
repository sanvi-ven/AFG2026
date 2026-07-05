import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/invoice.dart';
import '../../models/scheduled_work.dart';

/// manages scheduled work orders from approved estimates
class ScheduledWorkService {
  ScheduledWorkService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _collection =
      _firestore.collection('scheduled_work');

  /// listen to real-time scheduled work updates, filtered by role and clientId/teamId
  static Stream<List<ScheduledWork>> watchScheduledWork({
    required String role,
    String? clientId,
    String? teamId,
  }) {
    Query<Map<String, dynamic>> query = _collection;
    if (role == 'client' && clientId != null && clientId.trim().isNotEmpty) {
      query = query.where('clientId', isEqualTo: clientId.trim());
    }
    if (role == 'employee' && teamId != null && teamId.trim().isNotEmpty) {
      query = query.where('teamId', isEqualTo: teamId.trim());
    }

    return query.snapshots().map((snapshot) {
      var items = snapshot.docs.map((doc) {
        final data = doc.data();
        return ScheduledWork.fromMap({...data, 'id': doc.id});
      }).where((item) => role == 'owner' || !item.isArchived).toList();

      if (role == 'employee') {
        final now = DateTime.now();
        final startOfToday = DateTime(now.year, now.month, now.day);
        items = items.where((item) => !item.scheduledDate.isBefore(startOfToday)).toList();
      }

      items.sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
      return items;
    });
  }

  /// jobs scheduled for exactly [day] (calendar-day match on scheduledDate),
  /// optionally restricted to one team; omit [teamId] for a cross-team view.
  static Stream<List<ScheduledWork>> watchJobsForDay({
    required DateTime day,
    required String role,
    String? teamId,
  }) {
    Query<Map<String, dynamic>> query = _collection;
    if (teamId != null && teamId.trim().isNotEmpty) {
      query = query.where('teamId', isEqualTo: teamId.trim());
    }

    final startOfDay = DateTime(day.year, day.month, day.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return query.snapshots().map((snapshot) {
      var items = snapshot.docs.map((doc) {
        final data = doc.data();
        return ScheduledWork.fromMap({...data, 'id': doc.id});
      }).where((item) => role == 'owner' || !item.isArchived).toList();

      items = items
          .where((item) =>
              !item.scheduledDate.isBefore(startOfDay) && item.scheduledDate.isBefore(endOfDay))
          .toList();
      items.sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
      return items;
    });
  }

  /// mint a shared group key to stamp on every job created in one recurring
  /// batch — not a real doc, just a unique string.
  static String newRecurringGroupId() => _collection.doc().id;

  /// all jobs belonging to one recurring batch, sorted by date
  static Stream<List<ScheduledWork>> watchSeries(String recurringGroupId) {
    return _collection.where('recurringGroupId', isEqualTo: recurringGroupId.trim()).snapshots().map((snapshot) {
      final items = snapshot.docs.map((doc) => ScheduledWork.fromMap({...doc.data(), 'id': doc.id})).toList();
      items.sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
      return items;
    });
  }

  /// owner action: archive every not-yet-completed, not-yet-archived occurrence
  /// in a series scheduled today or later; returns how many were cancelled
  static Future<int> cancelRemainingInSeries(String recurringGroupId) async {
    final normalizedId = recurringGroupId.trim();
    final snapshot = await _collection.where('recurringGroupId', isEqualTo: normalizedId).get();
    final now = DateTime.now();
    final toCancel = snapshot.docs.where((doc) {
      final work = ScheduledWork.fromMap({...doc.data(), 'id': doc.id});
      return work.isScheduled && !work.isArchived && !work.scheduledDate.isBefore(now);
    }).toList();
    if (toCancel.isEmpty) return 0;

    final batch = _firestore.batch();
    for (final doc in toCancel) {
      batch.set(doc.reference, {'archived': true, 'updatedAt': now}, SetOptions(merge: true));
    }
    await batch.commit();
    return toCancel.length;
  }

  /// jobs scheduled within [start] (inclusive) through [end] (exclusive) —
  /// e.g. a Mon-through-Sun week — optionally restricted to one team.
  static Stream<List<ScheduledWork>> watchJobsForRange({
    required DateTime start,
    required DateTime end,
    required String role,
    String? teamId,
  }) {
    Query<Map<String, dynamic>> query = _collection;
    if (teamId != null && teamId.trim().isNotEmpty) {
      query = query.where('teamId', isEqualTo: teamId.trim());
    }

    return query.snapshots().map((snapshot) {
      var items = snapshot.docs.map((doc) {
        final data = doc.data();
        return ScheduledWork.fromMap({...data, 'id': doc.id});
      }).where((item) => role == 'owner' || !item.isArchived).toList();

      items = items
          .where((item) => !item.scheduledDate.isBefore(start) && item.scheduledDate.isBefore(end))
          .toList();
      items.sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
      return items;
    });
  }

  /// create a new scheduled work order from an estimate and return work id
  static Future<String> createScheduledWork({
    required String estimateId,
    required String estimateNumber,
    required String clientId,
    required List<InvoiceServiceItem> services,
    required double total,
    required DateTime scheduledDate,
    String? teamId,
    String address = '',
    String phoneNumber = '',
    String? recurringGroupId,
  }) async {
    final now = DateTime.now();
    final doc = _collection.doc();

    final work = ScheduledWork(
      id: doc.id,
      estimateId: estimateId.trim(),
      estimateNumber: estimateNumber.trim(),
      clientId: clientId.trim(),
      services: services,
      total: total,
      scheduledDate: scheduledDate,
      status: ScheduledWorkStatus.scheduled,
      teamId: teamId,
      address: address,
      phoneNumber: phoneNumber,
      createdAt: now,
      updatedAt: now,
      recurringGroupId: recurringGroupId,
    );

    await doc.set(work.toMap());
    return doc.id;
  }

  /// owner action: move a job's scheduled date/time, regardless of status
  static Future<void> rescheduleWork({required String workId, required DateTime newDate}) async {
    await _collection.doc(workId).set(
      {'scheduledDate': newDate, 'updatedAt': DateTime.now()},
      SetOptions(merge: true),
    );
  }

  /// owner action: hide a job from active use without deleting its history
  static Future<void> archiveWork(String workId) async {
    await _collection.doc(workId).set(
      {'archived': true, 'updatedAt': DateTime.now()},
      SetOptions(merge: true),
    );
  }

  /// owner action: permanently remove an archived job, refusing if it's
  /// already been invoiced or has a submitted completion form on file
  static Future<void> deleteWorkPermanently(String workId) async {
    final normalizedId = workId.trim();
    final doc = _collection.doc(normalizedId);

    final snapshot = await doc.get();
    final data = snapshot.data();
    if (data != null) {
      final work = ScheduledWork.fromMap({...data, 'id': snapshot.id});
      if (work.status == ScheduledWorkStatus.invoiced || work.invoiceId != null) {
        throw Exception("This job has already been invoiced and can't be permanently deleted.");
      }
    }

    // job_completion_forms is keyed directly by workId, not queried by a
    // foreign-key field, so this is a direct existence check rather than
    // the `.where().limit(1)` pattern used by the other delete guards.
    final completionDoc = await _firestore.collection('job_completion_forms').doc(normalizedId).get();
    if (completionDoc.exists) {
      throw Exception(
        "This job has a submitted completion form on file and can't be permanently deleted.",
      );
    }

    await doc.delete();
  }

  /// owner action: assign (or clear) the crew responsible for a job
  static Future<void> assignTeam({required String workId, String? teamId}) async {
    await _collection.doc(workId).set(
      {
        'teamId': teamId,
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );
  }

  /// mark a scheduled work order as completed
  static Future<void> markCompleted({required String workId}) async {
    await _collection.doc(workId).set(
      {
        'status': ScheduledWorkStatus.completed,
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );
  }

  /// mark scheduled work as invoiced and link to invoice id
  static Future<void> markInvoiced({
    required String workId,
    required String invoiceId,
  }) async {
    await _collection.doc(workId).set(
      {
        'status': ScheduledWorkStatus.invoiced,
        'invoiceId': invoiceId.trim(),
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );
  }
}

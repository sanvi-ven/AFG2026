import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../models/checklist_template.dart';
import '../../models/invoice.dart';
import '../../models/scheduled_work.dart';
import 'client_profile_service.dart';
import 'comms_service.dart';
import 'employee_profile_service.dart';
import 'owner_settings_service.dart';

/// manages scheduled work orders from approved estimates
class ScheduledWorkService {
  ScheduledWorkService._();

  /// best-effort SMS to the client on a job-status change, gated on their
  /// own [ClientProfile.smsOptIn] — mirrors the business-name + STOP format
  /// registered with Twilio's A2P campaign (see reminder_check_service.dart).
  /// Centralized here rather than in each calling page so every trigger
  /// point (Appointments tab, Jobs tab drag-reschedule, etc.) gets it once,
  /// instead of needing to be wired up per call site. Never throws — a
  /// failed/skipped send must never block the status write it follows.
  static Future<void> _notifyClient(String clientId, String Function(String businessName) buildBody) async {
    try {
      final client = await ClientProfileService.fetchBySignupId(clientId);
      if (client == null) return;
      final phone = client.phoneNumber.trim();
      if (phone.isEmpty || !client.smsOptIn) return;

      final ownerSettings = await OwnerSettingsService.fetch();
      final businessName =
          ownerSettings.companyName.trim().isEmpty ? 'Your service provider' : ownerSettings.companyName.trim();

      await CommsService.sendSms(to: phone, body: buildBody(businessName));
    } catch (_) {
      // best-effort, same reasoning as every other fire-and-forget comms
      // call in this app (see CommsService's own doc comment)
    }
  }

  /// same as [_notifyClient] but for a single employee, gated on their own
  /// [EmployeeProfile.smsOptIn].
  static Future<void> _notifyEmployee(String employeeId, String Function(String businessName) buildBody) async {
    try {
      final employee = await EmployeeProfileService.fetchBySignupId(employeeId);
      if (employee == null) return;
      final phone = employee.phoneNumber.trim();
      if (phone.isEmpty || !employee.smsOptIn) return;

      final ownerSettings = await OwnerSettingsService.fetch();
      final businessName =
          ownerSettings.companyName.trim().isEmpty ? 'Your employer' : ownerSettings.companyName.trim();

      await CommsService.sendSms(to: phone, body: buildBody(businessName));
    } catch (_) {
      // best-effort, same reasoning as _notifyClient above
    }
  }

  /// notifies every opted-in employee on [teamId] — team membership is
  /// tracked on EmployeeProfile.teamId (the reverse of what you'd expect
  /// from the "teams" collection itself, which only stores id/name), so
  /// this fetches the full roster and filters client-side rather than
  /// querying a member list that doesn't exist.
  static Future<void> _notifyTeam(String teamId, String Function(String businessName) buildBody) async {
    try {
      final employees = await EmployeeProfileService.watchAllProfiles().first;
      final members = employees.where((e) => e.teamId == teamId && !e.archived);
      for (final member in members) {
        await _notifyEmployee(member.employeeId, buildBody);
      }
    } catch (_) {
      // best-effort, same reasoning as _notifyClient above
    }
  }

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _collection =
      _firestore.collection('scheduled_work');

  /// true if [item] is visible to an employee on [teamId] and/or [employeeId]
  /// — a job matches if it's assigned to that team OR that employee individually.
  static bool _matchesEmployee(ScheduledWork item, String? teamId, String? employeeId) {
    final matchesTeam = teamId != null && teamId.trim().isNotEmpty && item.teamId == teamId.trim();
    final matchesEmployee =
        employeeId != null && employeeId.trim().isNotEmpty && item.employeeIds.contains(employeeId.trim());
    return matchesTeam || matchesEmployee;
  }

  /// listen to real-time scheduled work updates, filtered by role and clientId/teamId/employeeId.
  /// team-or-employee matching can't be expressed as a single Firestore query, so for the
  /// employee role this fetches the full collection and filters client-side.
  static Stream<List<ScheduledWork>> watchScheduledWork({
    required String role,
    String? clientId,
    String? teamId,
    String? employeeId,
  }) {
    Query<Map<String, dynamic>> query = _collection;
    if (role == 'client' && clientId != null && clientId.trim().isNotEmpty) {
      query = query.where('clientId', isEqualTo: clientId.trim());
    }

    return query.snapshots().map((snapshot) {
      var items = snapshot.docs.map((doc) {
        final data = doc.data();
        return ScheduledWork.fromMap({...data, 'id': doc.id});
      }).where((item) => role == 'owner' || !item.isArchived).toList();

      if (role == 'employee') {
        final now = DateTime.now();
        final startOfToday = DateTime(now.year, now.month, now.day);
        items = items
            .where((item) =>
                !item.scheduledDate.isBefore(startOfToday) && _matchesEmployee(item, teamId, employeeId))
            .toList();
      }

      items.sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
      return items;
    });
  }

  /// jobs scheduled for exactly [day] (calendar-day match on scheduledDate),
  /// optionally restricted to one team and/or employee; omit both for a
  /// cross-team, cross-employee view (used by the owner).
  static Stream<List<ScheduledWork>> watchJobsForDay({
    required DateTime day,
    required String role,
    String? teamId,
    String? employeeId,
  }) {
    final startOfDay = DateTime(day.year, day.month, day.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _collection.snapshots().map((snapshot) {
      var items = snapshot.docs.map((doc) {
        final data = doc.data();
        return ScheduledWork.fromMap({...data, 'id': doc.id});
      }).where((item) => role == 'owner' || !item.isArchived).toList();

      items = items
          .where((item) =>
              !item.scheduledDate.isBefore(startOfDay) && item.scheduledDate.isBefore(endOfDay))
          .toList();

      if (role == 'employee') {
        items = items.where((item) => _matchesEmployee(item, teamId, employeeId)).toList();
      }

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
    List<ChecklistItem> checklistItems = const [],
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
      checklistItems: checklistItems,
    );

    await doc.set(work.toMap());
    return doc.id;
  }

  /// employee action: toggle one checklist item's done state on a job.
  /// [index] is the item's position in checklistItems, since items don't
  /// have their own ids — the whole (small) list is snapshotted and rewritten.
  static Future<void> updateChecklistItem({
    required String workId,
    required int index,
    required bool done,
  }) async {
    final doc = _collection.doc(workId);
    final snapshot = await doc.get();
    final data = snapshot.data();
    if (data == null) return;

    final work = ScheduledWork.fromMap({...data, 'id': workId});
    if (index < 0 || index >= work.checklistItems.length) return;

    final updatedItems = [...work.checklistItems];
    updatedItems[index] = updatedItems[index].copyWith(done: done);

    await doc.set(
      {'checklistItems': updatedItems.map((item) => item.toMap()).toList(), 'updatedAt': DateTime.now()},
      SetOptions(merge: true),
    );
  }

  /// owner action: move a job's scheduled date/time, regardless of status
  static Future<void> rescheduleWork({required String workId, required DateTime newDate}) async {
    await _collection.doc(workId).set(
      {'scheduledDate': newDate, 'updatedAt': DateTime.now()},
      SetOptions(merge: true),
    );

    final snapshot = await _collection.doc(workId).get();
    final data = snapshot.data();
    if (data == null) return;
    final work = ScheduledWork.fromMap({...data, 'id': workId});
    unawaited(_notifyClient(
      work.clientId,
      (businessName) => '$businessName: Your appointment (Est #${work.estimateNumber}) has been rescheduled to '
          '${DateFormat('MM/dd/yyyy').format(work.scheduledDate)} at '
          '${DateFormat('h:mm a').format(work.scheduledDate)}. Reply STOP to opt out.',
    ));
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

  /// owner action: assign (or clear) the crew responsible for a job.
  /// mutually exclusive with individual employee assignment — this clears
  /// any previously assigned employees.
  static Future<void> assignTeam({required String workId, String? teamId}) async {
    await _collection.doc(workId).set(
      {
        'teamId': teamId,
        'employeeIds': <String>[],
        // routeOrder is only meaningful within the bucket (team, or
        // individual-assignment) it was set in — reassigning to a different
        // bucket must drop it, or it silently jumps the job to the front of
        // whatever unrelated sequence happens to share that number.
        'routeOrder': null,
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );

    if (teamId != null && teamId.trim().isNotEmpty) {
      final snapshot = await _collection.doc(workId).get();
      final data = snapshot.data();
      if (data == null) return;
      final work = ScheduledWork.fromMap({...data, 'id': workId});
      unawaited(_notifyTeam(
        teamId.trim(),
        (businessName) => "$businessName: You've been assigned to a job (Est #${work.estimateNumber}) "
            'scheduled for ${DateFormat('MM/dd/yyyy').format(work.scheduledDate)} at '
            '${DateFormat('h:mm a').format(work.scheduledDate)}. Reply STOP to opt out.',
      ));
    }
  }

  /// owner action: assign (or clear) the specific employees responsible for
  /// a job. mutually exclusive with team assignment — this clears any
  /// previously assigned team.
  static Future<void> assignEmployees({required String workId, required List<String> employeeIds}) async {
    await _collection.doc(workId).set(
      {
        'teamId': null,
        'employeeIds': employeeIds,
        // see assignTeam's comment — routeOrder doesn't carry across buckets.
        'routeOrder': null,
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );

    if (employeeIds.isNotEmpty) {
      final snapshot = await _collection.doc(workId).get();
      final data = snapshot.data();
      if (data == null) return;
      final work = ScheduledWork.fromMap({...data, 'id': workId});
      for (final employeeId in employeeIds) {
        unawaited(_notifyEmployee(
          employeeId,
          (businessName) => "$businessName: You've been assigned to a job (Est #${work.estimateNumber}) "
              'scheduled for ${DateFormat('MM/dd/yyyy').format(work.scheduledDate)} at '
              '${DateFormat('h:mm a').format(work.scheduledDate)}. Reply STOP to opt out.',
        ));
      }
    }
  }

  /// stamp that an upcoming-appointment reminder notification has been
  /// created for this job, so [ReminderCheckService] doesn't create a duplicate
  static Future<void> markReminderSent(String workId) async {
    await _collection.doc(workId).set(
      {'reminderSentAt': DateTime.now()},
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

    final snapshot = await _collection.doc(workId).get();
    final data = snapshot.data();
    if (data == null) return;
    final work = ScheduledWork.fromMap({...data, 'id': workId});
    unawaited(_notifyClient(
      work.clientId,
      (businessName) => '$businessName: Your appointment (Est #${work.estimateNumber}) has been completed. '
          'Thank you for choosing $businessName! Reply STOP to opt out.',
    ));
  }

  /// owner action: persist a manual route sequence for a set of jobs, stamping
  /// `routeOrder` 0..n-1 on each id in the order given. callers pass a team's
  /// full job list for the day in the new desired order; the whole write is one
  /// batch so the sequence lands atomically.
  static Future<void> reorderJobs({required List<String> workIdsInOrder}) async {
    final batch = _firestore.batch();
    for (var i = 0; i < workIdsInOrder.length; i++) {
      batch.set(_collection.doc(workIdsInOrder[i]), {'routeOrder': i}, SetOptions(merge: true));
    }
    await batch.commit();
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

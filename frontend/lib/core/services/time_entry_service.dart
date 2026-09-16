import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../models/time_entry.dart';

/// manages employee shift clock in/out records
/// one doc per employee per calendar day, keyed by a deterministic id
class TimeEntryService {
  TimeEntryService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _collection =
      _firestore.collection('time_entries');
  static final DateFormat _dateFormat = DateFormat('yyyyMMdd');
  static final DateFormat _isoDateFormat = DateFormat('yyyy-MM-dd');

  static String _docIdFor(String employeeId, DateTime date) =>
      '${employeeId}_${_dateFormat.format(date)}';

  /// One employee's entry for one day, addressed by an employeeId-scoped
  /// QUERY rather than by document id.
  ///
  /// This is load-bearing, not a style preference. `firestore.rules` gates a
  /// time_entries read on `isOwnEmployee(resource.data.employeeId)`, and on a
  /// document that does not exist yet `resource` is null — so that expression
  /// errors and the rule DENIES, which the SDK surfaces as the generic
  /// "Missing or insufficient permissions." A direct `.doc(id).get()` /
  /// `.snapshots()` therefore fails for every employee on the first clock-in
  /// of any given day, before the (perfectly legal) write is even attempted.
  /// A query matching zero documents has no document to evaluate the rule
  /// against, so it comes back as a clean empty result — while still being
  /// denied outright if it ever asked for another employee's rows.
  ///
  /// Both filters are equality-only, which Firestore serves from the
  /// single-field indexes via a zig-zag merge join — no composite index is
  /// needed. Verified against the live deployed rules on 2026-09-16.
  static Query<Map<String, dynamic>> _entryQueryFor(String employeeId, DateTime date) {
    return _collection
        .where('employeeId', isEqualTo: employeeId)
        .where('date', isEqualTo: _isoDateFormat.format(date))
        .limit(1);
  }

  static Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _entryFor(
    String employeeId,
    DateTime date,
  ) async {
    final snapshot = await _entryQueryFor(employeeId, date).get();
    return snapshot.docs.isEmpty ? null : snapshot.docs.first;
  }

  /// The Firestore Web SDK's internal credential cache can lag a freshly
  /// minted ID token by a beat, so a legitimate write fired right after
  /// landing on the dashboard can come back `permission-denied` once and then
  /// succeed on its own (see CLAUDE.md, Auth model). Retry that one specific
  /// code a bounded number of times. Every other failure — and an exhausted
  /// retry — propagates unchanged, so a genuine rules problem still reaches
  /// the employee as an error instead of being silently swallowed.
  static Future<void> _write(Future<void> Function() write) async {
    const delays = [Duration(milliseconds: 400), Duration(milliseconds: 900)];
    for (var attempt = 0;; attempt++) {
      try {
        await write();
        return;
      } on FirebaseException catch (error) {
        if (error.code != 'permission-denied' || attempt >= delays.length) {
          rethrow;
        }
        debugPrint(
          'TimeEntryService: write denied on attempt ${attempt + 1} of '
          '${delays.length + 1}; retrying in ${delays[attempt].inMilliseconds}ms',
        );
        await Future<void>.delayed(delays[attempt]);
      }
    }
  }

  /// stream today's clock in/out entry for an employee (null if not clocked in yet)
  static Stream<TimeEntry?> watchTodayEntry(String employeeId) {
    return _entryQueryFor(employeeId, DateTime.now()).snapshots().map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      final doc = snapshot.docs.first;
      return TimeEntry.fromMap({...doc.data(), 'id': doc.id});
    });
  }

  static Future<void> clockIn(String employeeId) async {
    final now = DateTime.now();
    final existing = await _entryFor(employeeId, now);
    if (existing != null && existing.data()['clockInAt'] != null) {
      throw Exception('Already clocked in today.');
    }

    if (existing == null) {
      final docId = _docIdFor(employeeId, now);
      await _write(() => _collection.doc(docId).set({
            'id': docId,
            'employeeId': employeeId,
            'date': _isoDateFormat.format(now),
            'clockInAt': now,
            'clockOutAt': null,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true)));
      return;
    }

    // A row already exists for today but carries no clock-in (e.g. the owner
    // opened the day's shift from the Employees tab). Only clockInAt /
    // clockOutAt / updatedAt may change on an employee's own update per
    // firestore.rules — re-sending id/employeeId/date/createdAt here would
    // trip onlyChanged() and be denied.
    await _write(() => existing.reference.update({
          'clockInAt': now,
          'updatedAt': FieldValue.serverTimestamp(),
        }));
  }

  static Future<void> clockOut(String employeeId) async {
    final now = DateTime.now();
    final existing = await _entryFor(employeeId, now);
    if (existing == null || existing.data()['clockInAt'] == null) {
      throw Exception('Not clocked in yet today.');
    }

    await _write(() => existing.reference.update({
          'clockOutAt': now,
          'updatedAt': FieldValue.serverTimestamp(),
        }));
  }

  /// owner action: correct a shift's clock times, set a one-off wage
  /// override for that day, leave a comment, and/or mark it paid.
  /// only the time-of-day changes here — [id] (and the date it's keyed to)
  /// never changes, so callers must combine the entry's existing date with
  /// a newly picked time before passing clockInAt/clockOutAt in.
  ///
  /// Deliberately `update()` and not `set(..., merge: true)`: this payload has
  /// no id/employeeId/date/createdAt in it, so a merge-set against an id with
  /// no document behind it would happily CREATE a row missing every field the
  /// rest of this service keys on — invisible to the employee's own
  /// employeeId-scoped queries, and enough to block that employee's clock-in
  /// for the day it lands on. `update()` raises `not-found` instead, which the
  /// caller already surfaces. The owner is the only caller and always edits an
  /// entry that exists, so this is a guard rail rather than a behavior change.
  static Future<void> updateEntry({
    required String id,
    DateTime? clockInAt,
    DateTime? clockOutAt,
    double? wageOverride,
    String notes = '',
    required bool isPaid,
  }) async {
    await _collection.doc(id).update({
      'clockInAt': clockInAt,
      'clockOutAt': clockOutAt,
      'wageOverride': wageOverride,
      'notes': notes.trim(),
      'isPaid': isPaid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// owner review: entries for a specific employee, most recent first
  static Stream<List<TimeEntry>> watchEntriesForEmployee(String employeeId) {
    return _collection
        .where('employeeId', isEqualTo: employeeId)
        .snapshots()
        .map((snapshot) {
      final entries = snapshot.docs.map((doc) => TimeEntry.fromMap(doc.data())).toList();
      entries.sort((a, b) => b.date.compareTo(a.date));
      return entries;
    });
  }

  /// owner review: all entries within an inclusive yyyy-MM-dd date range
  static Stream<List<TimeEntry>> watchEntriesInRange(String startDate, String endDate) {
    return _collection
        .where('date', isGreaterThanOrEqualTo: startDate)
        .where('date', isLessThanOrEqualTo: endDate)
        .snapshots()
        .map((snapshot) {
      final entries = snapshot.docs.map((doc) => TimeEntry.fromMap(doc.data())).toList();
      entries.sort((a, b) => b.date.compareTo(a.date));
      return entries;
    });
  }
}

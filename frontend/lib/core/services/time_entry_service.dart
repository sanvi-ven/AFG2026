import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../models/time_entry.dart';

/// manages employee shift clock in/out records
/// one doc PER SHIFT (auto-generated id) — an employee can clock in/out
/// multiple times in a calendar day (e.g. morning + afternoon shifts), so
/// unlike the original design this is no longer one doc per employee per
/// day. `date` stays a plain field for range queries; it is not part of any
/// doc's identity.
class TimeEntryService {
  TimeEntryService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _collection =
      _firestore.collection('time_entries');
  static final DateFormat _isoDateFormat = DateFormat('yyyy-MM-dd');

  /// All of one employee's shifts for one day, addressed by an
  /// employeeId-scoped QUERY rather than by document id.
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
  static Query<Map<String, dynamic>> _entriesQueryFor(String employeeId, DateTime date) {
    return _collection
        .where('employeeId', isEqualTo: employeeId)
        .where('date', isEqualTo: _isoDateFormat.format(date));
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _entriesFor(
    String employeeId,
    DateTime date,
  ) async {
    final snapshot = await _entriesQueryFor(employeeId, date).get();
    return snapshot.docs;
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

  /// stream all of today's shifts for an employee, earliest first — an
  /// employee can clock in/out more than once in a day (e.g. morning and
  /// afternoon shifts), so this is a list rather than a single entry.
  static Stream<List<TimeEntry>> watchTodayEntries(String employeeId) {
    return _entriesQueryFor(employeeId, DateTime.now()).snapshots().map((snapshot) {
      final entries = snapshot.docs
          .map((doc) => TimeEntry.fromMap({...doc.data(), 'id': doc.id}))
          .toList();
      entries.sort((a, b) => (a.clockInAt ?? DateTime(0)).compareTo(b.clockInAt ?? DateTime(0)));
      return entries;
    });
  }

  static Future<void> clockIn(String employeeId) async {
    final now = DateTime.now();
    final todaysEntries = await _entriesFor(employeeId, now);

    // an "open" row is one with no clockOutAt yet — either a real in-progress
    // shift, or (defensively) a blank placeholder with no clockInAt either,
    // in case one is ever created some other way (e.g. directly by the
    // owner). Either way an employee can have at most one open row at a
    // time, so clocking in again means starting a brand-new shift doc, never
    // reusing an already-completed one.
    final open = todaysEntries.where((doc) => doc.data()['clockOutAt'] == null).toList();
    if (open.isNotEmpty) {
      final doc = open.first;
      if (doc.data()['clockInAt'] != null) {
        throw Exception('Already clocked in. Clock out first to start a new shift.');
      }
      // Only clockInAt/clockOutAt/updatedAt may change on an employee's own
      // update per firestore.rules — re-sending id/employeeId/date/createdAt
      // here would trip onlyChanged() and be denied.
      await _write(() => doc.reference.update({
            'clockInAt': now,
            'updatedAt': FieldValue.serverTimestamp(),
          }));
      return;
    }

    final doc = _collection.doc();
    await _write(() => doc.set({
          'id': doc.id,
          'employeeId': employeeId,
          'date': _isoDateFormat.format(now),
          'clockInAt': now,
          'clockOutAt': null,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }));
  }

  static Future<void> clockOut(String employeeId) async {
    final now = DateTime.now();
    final todaysEntries = await _entriesFor(employeeId, now);
    final open = todaysEntries
        .where((doc) => doc.data()['clockInAt'] != null && doc.data()['clockOutAt'] == null)
        .toList();
    if (open.isEmpty) {
      throw Exception('Not clocked in yet today.');
    }

    await _write(() => open.first.reference.update({
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

  /// most-recent-first comparator that also orders same-day shifts
  /// sensibly (latest shift of the day first) now that a day can hold more
  /// than one entry.
  static int _newestFirst(TimeEntry a, TimeEntry b) {
    final byDate = b.date.compareTo(a.date);
    if (byDate != 0) return byDate;
    return (b.clockInAt ?? DateTime(0)).compareTo(a.clockInAt ?? DateTime(0));
  }

  /// owner review: entries for a specific employee, most recent first
  static Stream<List<TimeEntry>> watchEntriesForEmployee(String employeeId) {
    return _collection
        .where('employeeId', isEqualTo: employeeId)
        .snapshots()
        .map((snapshot) {
      final entries = snapshot.docs.map((doc) => TimeEntry.fromMap(doc.data())).toList();
      entries.sort(_newestFirst);
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
      entries.sort(_newestFirst);
      return entries;
    });
  }
}

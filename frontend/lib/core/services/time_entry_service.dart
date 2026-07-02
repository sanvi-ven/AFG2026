import 'package:cloud_firestore/cloud_firestore.dart';
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

  /// stream today's clock in/out entry for an employee (null if not clocked in yet)
  static Stream<TimeEntry?> watchTodayEntry(String employeeId) {
    final docId = _docIdFor(employeeId, DateTime.now());
    return _collection.doc(docId).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return null;
      return TimeEntry.fromMap({...data, 'id': docId});
    });
  }

  static Future<void> clockIn(String employeeId) async {
    final now = DateTime.now();
    final docId = _docIdFor(employeeId, now);
    final doc = _collection.doc(docId);
    final existing = await doc.get();
    if (existing.exists && existing.data()?['clockInAt'] != null) {
      throw Exception('Already clocked in today.');
    }

    await doc.set({
      'id': docId,
      'employeeId': employeeId,
      'date': _isoDateFormat.format(now),
      'clockInAt': now,
      'clockOutAt': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> clockOut(String employeeId) async {
    final now = DateTime.now();
    final docId = _docIdFor(employeeId, now);
    final doc = _collection.doc(docId);
    final existing = await doc.get();
    if (!existing.exists || existing.data()?['clockInAt'] == null) {
      throw Exception('Not clocked in yet today.');
    }

    await doc.set({
      'clockOutAt': now,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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

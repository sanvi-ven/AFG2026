import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../models/employee_availability.dart';

/// manages employee day-by-day work-availability markers
/// one doc per employee per calendar day, keyed by a deterministic id
class EmployeeAvailabilityService {
  EmployeeAvailabilityService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _collection =
      _firestore.collection('employee_availability');
  static final DateFormat _idDateFormat = DateFormat('yyyyMMdd');
  static final DateFormat _isoDateFormat = DateFormat('yyyy-MM-dd');

  static String _docIdFor(String employeeId, DateTime date) =>
      '${employeeId}_${_idDateFormat.format(date)}';

  /// stream every day an employee has marked, for their own calendar
  static Stream<List<EmployeeAvailability>> watchForEmployee(String employeeId) {
    return _collection.where('employeeId', isEqualTo: employeeId).snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => EmployeeAvailability.fromMap({...doc.data(), 'id': doc.id}))
          .toList();
    });
  }

  /// stream every availability marker across all employees, for the owner's
  /// day-by-day browse view to filter client-side by date (matches this
  /// app's convention of avoiding composite-index per-day queries).
  static Stream<List<EmployeeAvailability>> watchAll() {
    return _collection.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => EmployeeAvailability.fromMap({...doc.data(), 'id': doc.id}))
          .toList();
    });
  }

  /// mark [date] available for [employeeId]. Leave both times null for
  /// "all day"; set either or both for a specific window.
  static Future<void> setAvailability({
    required String employeeId,
    required DateTime date,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final docId = _docIdFor(employeeId, date);
    await _collection.doc(docId).set({
      'id': docId,
      'employeeId': employeeId,
      'date': _isoDateFormat.format(date),
      'startTime': startTime,
      'endTime': endTime,
    }, SetOptions(merge: true));
  }

  /// un-mark [date] entirely for [employeeId]
  static Future<void> clearAvailability({
    required String employeeId,
    required DateTime date,
  }) async {
    await _collection.doc(_docIdFor(employeeId, date)).delete();
  }
}

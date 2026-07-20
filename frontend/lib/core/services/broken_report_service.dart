import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/broken_report.dart';
import '../../models/equipment.dart';
import 'equipment_service.dart';

/// manages broken-equipment incidents and their embedded repair attempts.
/// Follows this codebase's static-service + direct-Firestore convention.
/// Embedded [RepairAttempt] lists are always read-modify-write (this codebase
/// does not use FieldValue.arrayUnion). Unit-status side effects are delegated
/// to [EquipmentService.setUnitStatus].
class BrokenReportService {
  BrokenReportService._();

  static final CollectionReference<Map<String, dynamic>> _collection =
      FirebaseFirestore.instance.collection('broken_reports');

  static String newBrokenReportId() => _collection.doc().id;

  /// owner-wide "what's broken right now" — all open reports, newest first.
  static Stream<List<BrokenReport>> watchOpenReports() {
    return _collection
        .where('status', isEqualTo: BrokenReportStatus.open)
        .snapshots()
        .map((snapshot) {
      final reports = snapshot.docs
          .map((doc) => BrokenReport.fromMap({...doc.data(), 'id': doc.id}))
          .toList();
      reports.sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
      return reports;
    });
  }

  /// every report (open + repaired), newest first. Used by reporting to count
  /// how often each item has broken historically, not just what's open now.
  static Stream<List<BrokenReport>> watchAllReports() {
    return _collection.snapshots().map((snapshot) {
      final reports = snapshot.docs
          .map((doc) => BrokenReport.fromMap({...doc.data(), 'id': doc.id}))
          .toList();
      reports.sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
      return reports;
    });
  }

  /// all reports (open + repaired) for one equipment item, newest first.
  static Stream<List<BrokenReport>> watchForEquipment(String equipmentId) {
    return _collection
        .where('equipmentId', isEqualTo: equipmentId)
        .snapshots()
        .map((snapshot) {
      final reports = snapshot.docs
          .map((doc) => BrokenReport.fromMap({...doc.data(), 'id': doc.id}))
          .toList();
      reports.sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
      return reports;
    });
  }

  /// mark a specific unit broken. Blocks a duplicate open report on the same
  /// unit, then writes the report and flips the unit to broken (stamping its
  /// currentBrokenReportId).
  static Future<void> reportBroken({
    required String equipmentId,
    required int unitNumber,
    required String note,
    required String employeeId,
    required String employeeName,
  }) async {
    final existing = await _collection
        .where('equipmentId', isEqualTo: equipmentId)
        .where('unitNumber', isEqualTo: unitNumber)
        .where('status', isEqualTo: BrokenReportStatus.open)
        .get();
    if (existing.docs.isNotEmpty) {
      throw Exception('This unit is already marked broken.');
    }

    final id = newBrokenReportId();
    final report = BrokenReport(
      id: id,
      equipmentId: equipmentId,
      unitNumber: unitNumber,
      note: note.trim(),
      reportedByEmployeeId: employeeId,
      reportedByEmployeeName: employeeName,
      reportedAt: DateTime.now(),
      status: BrokenReportStatus.open,
      repairAttempts: const [],
    );
    await _collection.doc(id).set(report.toMap());

    await EquipmentService.setUnitStatus(
      equipmentId: equipmentId,
      unitNumber: unitNumber,
      status: EquipmentUnitStatus.broken,
      currentBrokenReportId: id,
    );
  }

  /// append a repair attempt to a report (read-modify-write of the embedded
  /// list). On the FIRST attempt, also flips the unit to inRepair.
  static Future<void> logRepairAttempt({
    required String brokenReportId,
    required String note,
    required String employeeId,
    required String employeeName,
  }) async {
    final doc = await _collection.doc(brokenReportId).get();
    if (!doc.exists) {
      throw Exception('This broken report no longer exists.');
    }
    final report = BrokenReport.fromMap({...?doc.data(), 'id': doc.id});
    if (!report.isOpen) {
      throw Exception(
          'This report has already been resolved. Close and reopen the unit sheet.');
    }
    final wasEmpty = report.repairAttempts.isEmpty;

    final attempts = List<RepairAttempt>.from(report.repairAttempts)
      ..add(RepairAttempt(
        note: note.trim(),
        employeeId: employeeId,
        employeeName: employeeName,
        attemptedAt: DateTime.now(),
      ));

    await _collection.doc(brokenReportId).set(
      {'repairAttempts': attempts.map((a) => a.toMap()).toList()},
      SetOptions(merge: true),
    );

    if (wasEmpty) {
      await EquipmentService.setUnitStatus(
        equipmentId: report.equipmentId,
        unitNumber: report.unitNumber,
        status: EquipmentUnitStatus.inRepair,
      );
    }
  }

  /// resolve a report: mark it repaired, then flip the unit back to active and
  /// clear its currentBrokenReportId.
  static Future<void> markFixed({
    required String brokenReportId,
    String resolvedNote = '',
  }) async {
    final doc = await _collection.doc(brokenReportId).get();
    if (!doc.exists) {
      throw Exception('This broken report no longer exists.');
    }
    final report = BrokenReport.fromMap({...?doc.data(), 'id': doc.id});
    if (!report.isOpen) {
      throw Exception('This report has already been resolved.');
    }

    await _collection.doc(brokenReportId).set(
      {
        'status': BrokenReportStatus.repaired,
        'resolvedAt': DateTime.now(),
        'resolvedNote': resolvedNote.trim(),
      },
      SetOptions(merge: true),
    );

    await EquipmentService.setUnitStatus(
      equipmentId: report.equipmentId,
      unitNumber: report.unitNumber,
      status: EquipmentUnitStatus.active,
      currentBrokenReportId: null,
    );
  }
}

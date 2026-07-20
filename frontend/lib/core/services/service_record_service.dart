import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/service_record.dart';
import 'equipment_service.dart';

/// manages service/maintenance records for Equipment units. Follows this
/// codebase's static-service + direct-Firestore convention. Writing a record
/// also stamps the parent unit's service fields (delegated to
/// [EquipmentService.updateUnitServiceInfo]) so the due-soon check has a single
/// place to look.
class ServiceRecordService {
  ServiceRecordService._();

  static final CollectionReference<Map<String, dynamic>> _collection =
      FirebaseFirestore.instance.collection('service_records');

  static String newServiceRecordId() => _collection.doc().id;

  /// all service records for one equipment item, newest first (sorted
  /// client-side to avoid a composite index, matching the other services).
  static Stream<List<ServiceRecord>> watchForEquipment(String equipmentId) {
    return _collection
        .where('equipmentId', isEqualTo: equipmentId)
        .snapshots()
        .map((snapshot) {
      final records = snapshot.docs
          .map((doc) => ServiceRecord.fromMap({...doc.data(), 'id': doc.id}))
          .toList();
      records.sort((a, b) => b.servicedDate.compareTo(a.servicedDate));
      return records;
    });
  }

  /// log a service event on a unit. Computes [ServiceRecord.nextServiceDueDate]
  /// from the chosen mode, writes the record, then stamps the unit's service
  /// fields via [EquipmentService.updateUnitServiceInfo] (which also resets any
  /// prior due/snooze/notified state).
  ///
  /// Throws if the companion argument for the chosen [mode] is missing
  /// ([intervalDays] for intervalDays, [explicitNextDate] for explicitDate).
  static Future<void> logService({
    required String equipmentId,
    required int unitNumber,
    required DateTime servicedDate,
    required String note,
    required String mode,
    DateTime? explicitNextDate,
    int? intervalDays,
    required String recordedByRole,
    required String recordedById,
    required String recordedByName,
  }) async {
    final DateTime nextServiceDueDate;
    if (mode == ServiceDueMode.intervalDays) {
      if (intervalDays == null) {
        throw Exception(
            'An interval in days is required when logging service by interval.');
      }
      nextServiceDueDate = servicedDate.add(Duration(days: intervalDays));
    } else if (mode == ServiceDueMode.explicitDate) {
      if (explicitNextDate == null) {
        throw Exception(
            'A next-service date is required when logging service by date.');
      }
      nextServiceDueDate = explicitNextDate;
    } else {
      throw Exception('Unknown service-due mode "$mode".');
    }

    final id = newServiceRecordId();
    final record = ServiceRecord(
      id: id,
      equipmentId: equipmentId,
      unitNumber: unitNumber,
      servicedDate: servicedDate,
      note: note.trim(),
      nextServiceMode: mode,
      nextServiceExplicitDate:
          mode == ServiceDueMode.explicitDate ? explicitNextDate : null,
      nextServiceIntervalDays:
          mode == ServiceDueMode.intervalDays ? intervalDays : null,
      nextServiceDueDate: nextServiceDueDate,
      recordedByRole: recordedByRole,
      recordedById: recordedById,
      recordedByName: recordedByName,
      createdAt: DateTime.now(),
    );
    await _collection.doc(id).set(record.toMap());

    await EquipmentService.updateUnitServiceInfo(
      equipmentId: equipmentId,
      unitNumber: unitNumber,
      lastServiceDate: servicedDate,
      nextServiceDueDate: nextServiceDueDate,
      // only persist a recurring interval on the unit when service was logged
      // by interval; an explicit one-off date leaves the interval untouched.
      serviceIntervalDays:
          mode == ServiceDueMode.intervalDays ? intervalDays : null,
      clearSnooze: true,
    );
  }
}

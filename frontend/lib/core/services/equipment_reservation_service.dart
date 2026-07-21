import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../models/equipment.dart';
import '../../models/equipment_reservation.dart';
import 'equipment_service.dart';

/// manages auto-approved equipment reservations with same-day conflict
/// checking. Follows this codebase's static-service + direct-Firestore
/// convention. All queries are equality-only and sorted client-side (no
/// composite indexes), matching every existing service.
class EquipmentReservationService {
  EquipmentReservationService._();

  static final CollectionReference<Map<String, dynamic>> _collection =
      FirebaseFirestore.instance.collection('equipment_reservations');

  static String newReservationId() => _collection.doc().id;

  /// every reservation, soonest first — used by the owner schedule (Phase 5).
  static Stream<List<EquipmentReservation>> watchAllReservations() {
    return _collection.snapshots().map((snapshot) {
      final reservations = snapshot.docs
          .map((doc) =>
              EquipmentReservation.fromMap({...doc.data(), 'id': doc.id}))
          .toList();
      reservations.sort((a, b) => a.startTime.compareTo(b.startTime));
      return reservations;
    });
  }

  /// all reservations for one equipment item, most recent first — this powers
  /// the detail-page reservation-history list.
  static Stream<List<EquipmentReservation>> watchForEquipment(
      String equipmentId) {
    return _collection
        .where('equipmentId', isEqualTo: equipmentId)
        .snapshots()
        .map((snapshot) {
      final reservations = snapshot.docs
          .map((doc) =>
              EquipmentReservation.fromMap({...doc.data(), 'id': doc.id}))
          .toList();
      reservations.sort((a, b) => b.startTime.compareTo(a.startTime));
      return reservations;
    });
  }

  /// all reservations for one employee, soonest first — used by "my equipment"
  /// (Phase 5).
  static Stream<List<EquipmentReservation>> watchForEmployee(
      String employeeId) {
    return _collection
        .where('employeeId', isEqualTo: employeeId)
        .snapshots()
        .map((snapshot) {
      final reservations = snapshot.docs
          .map((doc) =>
              EquipmentReservation.fromMap({...doc.data(), 'id': doc.id}))
          .toList();
      reservations.sort((a, b) => a.startTime.compareTo(b.startTime));
      return reservations;
    });
  }

  /// all reservations linked to one job ([workId]), soonest first — powers the
  /// job detail page's Equipment section.
  static Stream<List<EquipmentReservation>> watchForWork(String workId) {
    return _collection
        .where('workId', isEqualTo: workId)
        .snapshots()
        .map((snapshot) {
      final reservations = snapshot.docs
          .map((doc) =>
              EquipmentReservation.fromMap({...doc.data(), 'id': doc.id}))
          .toList();
      reservations.sort((a, b) => a.startTime.compareTo(b.startTime));
      return reservations;
    });
  }

  /// reserve [quantity] free units of [equipment] for the [startTime]–[endTime]
  /// window, auto-approved. Picks the lowest-numbered active units that have no
  /// overlapping active reservation that same day, then batch-creates one
  /// reservation doc per chosen unit. Throws a friendly [Exception] if the
  /// window is invalid, the item isn't Equipment, or not enough units are free.
  ///
  /// This is a deliberate pre-check-then-batch-write, NOT a Firestore
  /// transaction: transactions can't run fresh `where` queries, which the
  /// conflict check needs. A small residual double-booking race across
  /// simultaneous callers is an accepted limitation at this app's scale,
  /// consistent with the rest of this codebase's unguarded read-then-write
  /// style elsewhere.
  static Future<List<EquipmentReservation>> reserveUnits({
    required EquipmentItem equipment,
    required int quantity,
    required DateTime startTime,
    required DateTime endTime,
    required String employeeId,
    required String employeeName,
    String workId = '',
    String jobAddress = '',
  }) async {
    if (quantity < 1) {
      throw Exception('Quantity must be at least 1.');
    }
    if (!startTime.isBefore(endTime)) {
      throw Exception('End time must be after start time.');
    }
    if (!equipment.isEquipment) {
      throw Exception('Only Equipment items can be reserved.');
    }
    if (DateFormat('yyyy-MM-dd').format(endTime) !=
        DateFormat('yyyy-MM-dd').format(startTime)) {
      throw Exception('Reservations cannot span more than one day.');
    }

    // re-fetch fresh unit statuses rather than trusting the caller's
    // possibly-stale snapshot (e.g. a unit could have been marked broken
    // while a reservation dialog sat open)
    final freshEquipment = await EquipmentService.fetchOnce(equipment.id);
    if (freshEquipment == null) {
      throw Exception('This equipment no longer exists.');
    }

    final dateKey = DateFormat('yyyy-MM-dd').format(startTime);

    // candidate units: only active ones (broken / in-repair aren't reservable)
    final candidateUnitNumbers = freshEquipment.units
        .where((u) => u.status == EquipmentUnitStatus.active)
        .map((u) => u.unitNumber)
        .toList();

    // one-time read of that day's reservations for this item (not a stream)
    final snapshot = await _collection
        .where('equipmentId', isEqualTo: equipment.id)
        .where('date', isEqualTo: dateKey)
        .get();
    final sameDayActive = snapshot.docs
        .map((doc) =>
            EquipmentReservation.fromMap({...doc.data(), 'id': doc.id}))
        .where((r) => r.isActive)
        .toList();

    final freeUnits = candidateUnitNumbers.where((unitNumber) {
      final overlapping = sameDayActive.any((r) =>
          r.unitNumber == unitNumber && r.overlaps(startTime, endTime));
      return !overlapping;
    }).toList()
      ..sort();

    if (freeUnits.length < quantity) {
      if (freeUnits.isEmpty) {
        throw Exception('No units are free for that time window.');
      }
      throw Exception(
          'Only ${freeUnits.length} of $quantity requested unit(s) are free '
          'for that time window.');
    }

    final chosen = freeUnits.take(quantity).toList();
    final now = DateTime.now();
    final batch = FirebaseFirestore.instance.batch();
    final created = <EquipmentReservation>[];

    for (final unitNumber in chosen) {
      final id = newReservationId();
      final reservation = EquipmentReservation(
        id: id,
        equipmentId: freshEquipment.id,
        equipmentName: freshEquipment.name,
        unitNumber: unitNumber,
        date: dateKey,
        startTime: startTime,
        endTime: endTime,
        employeeId: employeeId,
        employeeName: employeeName,
        workId: workId,
        jobAddress: jobAddress,
        createdAt: now,
      );
      batch.set(_collection.doc(id), reservation.toMap());
      created.add(reservation);
    }

    await batch.commit();
    return created;
  }

  /// cancel a reservation (soft — the row stays in history, flagged cancelled).
  static Future<void> cancelReservation({
    required String id,
    String reason = '',
  }) async {
    await _collection.doc(id).set(
      {
        'isCancelled': true,
        'cancelledAt': DateTime.now(),
        'cancelReason': reason.trim(),
      },
      SetOptions(merge: true),
    );
  }

  /// stamp a reservation as physically checked out (Phase 5 UI).
  static Future<void> markCheckedOut(String id) async {
    await _collection.doc(id).set(
      {'checkedOutAt': DateTime.now()},
      SetOptions(merge: true),
    );
  }

  /// stamp a reservation as returned (Phase 5 UI).
  static Future<void> markReturned(String id) async {
    await _collection.doc(id).set(
      {'returnedAt': DateTime.now()},
      SetOptions(merge: true),
    );
  }
}

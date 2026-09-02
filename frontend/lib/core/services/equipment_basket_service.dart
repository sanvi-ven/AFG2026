import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../models/equipment.dart';
import '../../models/equipment_basket.dart';
import '../../models/equipment_reservation.dart';
import 'equipment_reservation_service.dart';
import 'equipment_service.dart';

/// one requested line in a basket-under-construction — either an Equipment
/// item (goes through the normal per-unit reservation flow) or a Supply item
/// (just a quantity, decremented from stock at check-out). The basket builder
/// UI collects a list of these and hands them to [EquipmentBasketService.createBasket].
class BasketLineRequest {
  const BasketLineRequest({required this.equipmentId, required this.quantity});

  final String equipmentId;
  final int quantity;
}

/// manages equipment baskets — a set of equipment reservations + supply lines
/// sharing one time window, created/checked-out/returned together. Follows
/// this codebase's static-service + direct-Firestore convention (see
/// EquipmentReservationService, which this delegates the actual per-unit
/// conflict-check/reservation logic to).
class EquipmentBasketService {
  EquipmentBasketService._();

  static final CollectionReference<Map<String, dynamic>> _collection =
      FirebaseFirestore.instance.collection('equipment_baskets');

  static String newBasketId() => _collection.doc().id;

  static Stream<List<EquipmentBasket>> watchAllBaskets() {
    return _collection.snapshots().map((snapshot) {
      final baskets = snapshot.docs
          .map((doc) => EquipmentBasket.fromMap({...doc.data(), 'id': doc.id}))
          .toList();
      baskets.sort((a, b) => a.startTime.compareTo(b.startTime));
      return baskets;
    });
  }

  static Stream<List<EquipmentBasket>> watchForEmployee(String employeeId) {
    return _collection
        .where('employeeId', isEqualTo: employeeId)
        .snapshots()
        .map((snapshot) {
      final baskets = snapshot.docs
          .map((doc) => EquipmentBasket.fromMap({...doc.data(), 'id': doc.id}))
          .toList();
      baskets.sort((a, b) => a.startTime.compareTo(b.startTime));
      return baskets;
    });
  }

  static Stream<List<EquipmentBasket>> watchForWork(String workId) {
    return _collection
        .where('workId', isEqualTo: workId)
        .snapshots()
        .map((snapshot) {
      final baskets = snapshot.docs
          .map((doc) => EquipmentBasket.fromMap({...doc.data(), 'id': doc.id}))
          .toList();
      baskets.sort((a, b) => a.startTime.compareTo(b.startTime));
      return baskets;
    });
  }

  static Future<EquipmentBasket?> fetchOnce(String id) async {
    final doc = await _collection.doc(id).get();
    if (!doc.exists) return null;
    return EquipmentBasket.fromMap({...?doc.data(), 'id': doc.id});
  }

  /// build a basket: for each equipment line, reuses the same
  /// lowest-numbered-free-unit selection + same-day conflict check as
  /// [EquipmentReservationService.reserveUnits], batched under one new
  /// [basketId]; for each supply line, just validates enough is on hand right
  /// now (the actual stock decrement happens at check-out, not here — see
  /// [checkOutBasket]). All-or-nothing: if any line can't be satisfied, the
  /// whole basket is rejected with a combined, per-line message and nothing is
  /// written — matching reserveUnits' existing accepted-limitation (a small
  /// residual race across simultaneous callers) at this app's scale.
  static Future<EquipmentBasket> createBasket({
    required List<BasketLineRequest> equipmentLines,
    required List<BasketLineRequest> supplyLines,
    required DateTime startTime,
    required DateTime endTime,
    required String employeeId,
    required String employeeName,
    String workId = '',
    String jobAddress = '',
    String kitId = '',
    String kitName = '',
  }) async {
    if (equipmentLines.isEmpty && supplyLines.isEmpty) {
      throw Exception('Add at least one item to the basket.');
    }
    if (!startTime.isBefore(endTime)) {
      throw Exception('End time must be after start time.');
    }
    if (DateFormat('yyyy-MM-dd').format(endTime) !=
        DateFormat('yyyy-MM-dd').format(startTime)) {
      throw Exception('A basket cannot span more than one day.');
    }

    final dateKey = DateFormat('yyyy-MM-dd').format(startTime);
    final basketId = newBasketId();
    final now = DateTime.now();
    final errors = <String>[];
    final batch = FirebaseFirestore.instance.batch();
    final createdReservations = <EquipmentReservation>[];

    for (final line in equipmentLines) {
      if (line.quantity < 1) continue;
      final item = await EquipmentService.fetchOnce(line.equipmentId);
      if (item == null || !item.isEquipment) {
        errors.add('An equipment item in this basket no longer exists.');
        continue;
      }
      final candidateUnitNumbers = item.units
          .where((u) => u.status == EquipmentUnitStatus.active)
          .map((u) => u.unitNumber)
          .toList();
      final freeUnits = await EquipmentReservationService.freeUnitNumbersFor(
        equipmentId: item.id,
        candidateUnitNumbers: candidateUnitNumbers,
        dateKey: dateKey,
        startTime: startTime,
        endTime: endTime,
      );
      if (freeUnits.length < line.quantity) {
        errors.add(freeUnits.isEmpty
            ? '${item.name}: no units are free for that time window.'
            : '${item.name}: only ${freeUnits.length} of ${line.quantity} '
                'requested unit(s) are free for that time window.');
        continue;
      }
      for (final unitNumber in freeUnits.take(line.quantity)) {
        final id = EquipmentReservationService.newReservationId();
        final reservation = EquipmentReservation(
          id: id,
          equipmentId: item.id,
          equipmentName: item.name,
          unitNumber: unitNumber,
          date: dateKey,
          startTime: startTime,
          endTime: endTime,
          employeeId: employeeId,
          employeeName: employeeName,
          workId: workId,
          jobAddress: jobAddress,
          basketId: basketId,
          createdAt: now,
        );
        batch.set(
          FirebaseFirestore.instance
              .collection('equipment_reservations')
              .doc(id),
          reservation.toMap(),
        );
        createdReservations.add(reservation);
      }
    }

    final supplyBasketLines = <EquipmentBasketSupplyLine>[];
    for (final line in supplyLines) {
      if (line.quantity < 1) continue;
      final item = await EquipmentService.fetchOnce(line.equipmentId);
      if (item == null || !item.isSupply) {
        errors.add('A supply item in this basket no longer exists.');
        continue;
      }
      if (item.quantity < line.quantity) {
        errors.add('${item.name}: only ${item.quantity} '
            '${item.unitOfMeasure.isEmpty ? "" : "${item.unitOfMeasure} "}'
            'on hand (requested ${line.quantity}).');
        continue;
      }
      supplyBasketLines.add(EquipmentBasketSupplyLine(
        equipmentId: item.id,
        name: item.name,
        quantity: line.quantity,
        unitOfMeasure: item.unitOfMeasure,
      ));
    }

    if (errors.isNotEmpty) {
      throw Exception(errors.join('\n'));
    }

    final basket = EquipmentBasket(
      id: basketId,
      date: dateKey,
      startTime: startTime,
      endTime: endTime,
      employeeId: employeeId,
      employeeName: employeeName,
      workId: workId,
      jobAddress: jobAddress,
      kitId: kitId,
      kitName: kitName,
      supplyLines: supplyBasketLines,
      createdAt: now,
    );
    batch.set(_collection.doc(basketId), basket.toMap());

    await batch.commit();
    return basket;
  }

  /// check out every not-yet-checked-out equipment reservation in the basket,
  /// and consume every not-yet-consumed supply line (decrementing that item's
  /// on-hand quantity). Re-validates on-hand supply quantity right before
  /// committing rather than trusting [EquipmentBasket.supplyLines] (which
  /// could be stale if stock was already drawn down by something else since
  /// the basket was created) — same non-transactional, small-residual-race
  /// tradeoff as the rest of this service.
  static Future<void> checkOutBasket(String basketId) async {
    final basket = await fetchOnce(basketId);
    if (basket == null) throw Exception('This basket no longer exists.');
    if (basket.isCancelled) throw Exception('This basket was cancelled.');

    final reservationsSnapshot = await FirebaseFirestore.instance
        .collection('equipment_reservations')
        .where('basketId', isEqualTo: basketId)
        .get();
    final reservations = reservationsSnapshot.docs
        .map((doc) => EquipmentReservation.fromMap({...doc.data(), 'id': doc.id}))
        .where((r) => r.isActive)
        .toList();

    final errors = <String>[];
    final pendingSupplyDecrements = <String, int>{};
    for (final line in basket.supplyLines) {
      if (line.consumedAt != null) continue;
      final item = await EquipmentService.fetchOnce(line.equipmentId);
      if (item == null) {
        errors.add('${line.name} no longer exists in the catalog.');
        continue;
      }
      if (item.quantity < line.quantity) {
        errors.add('${line.name}: only ${item.quantity} on hand '
            '(basket needs ${line.quantity}).');
        continue;
      }
      pendingSupplyDecrements[line.equipmentId] = line.quantity;
    }

    if (errors.isNotEmpty) {
      throw Exception(errors.join('\n'));
    }

    final batch = FirebaseFirestore.instance.batch();
    for (final reservation in reservations) {
      if (reservation.checkedOutAt == null) {
        EquipmentReservationService.addCheckedOutToBatch(batch, reservation.id);
      }
    }

    final equipmentCollection = FirebaseFirestore.instance.collection('equipment');
    pendingSupplyDecrements.forEach((equipmentId, quantity) {
      batch.set(
        equipmentCollection.doc(equipmentId),
        {
          'quantity': FieldValue.increment(-quantity),
          'updatedAt': DateTime.now(),
        },
        SetOptions(merge: true),
      );
    });

    final updatedSupplyLines = basket.supplyLines
        .map((line) => line.consumedAt != null
            ? line
            : line.copyWith(consumedAt: DateTime.now()))
        .toList();
    batch.set(
      _collection.doc(basketId),
      {'supplyLines': updatedSupplyLines.map((l) => l.toMap()).toList()},
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  /// return every checked-out, not-yet-returned equipment reservation in the
  /// basket. Supplies have nothing to return — once consumed they're gone.
  static Future<void> returnBasket(String basketId) async {
    final reservationsSnapshot = await FirebaseFirestore.instance
        .collection('equipment_reservations')
        .where('basketId', isEqualTo: basketId)
        .get();
    final reservations = reservationsSnapshot.docs
        .map((doc) => EquipmentReservation.fromMap({...doc.data(), 'id': doc.id}))
        .where((r) => r.isActive && r.checkedOutAt != null && r.returnedAt == null)
        .toList();

    if (reservations.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final reservation in reservations) {
      EquipmentReservationService.addReturnedToBatch(batch, reservation.id);
    }
    await batch.commit();
  }

  /// cancel every not-yet-checked-out equipment reservation in the basket
  /// (soft — same as EquipmentReservationService.cancelReservation) and flag
  /// the basket itself cancelled. A reservation that's already checked out is
  /// left alone — it needs to be physically returned, not cancelled.
  static Future<void> cancelBasket(String basketId, {String reason = ''}) async {
    final reservationsSnapshot = await FirebaseFirestore.instance
        .collection('equipment_reservations')
        .where('basketId', isEqualTo: basketId)
        .get();
    final reservations = reservationsSnapshot.docs
        .map((doc) => EquipmentReservation.fromMap({...doc.data(), 'id': doc.id}))
        .where((r) => r.isActive && r.checkedOutAt == null)
        .toList();

    final batch = FirebaseFirestore.instance.batch();
    for (final reservation in reservations) {
      EquipmentReservationService.addCancelToBatch(batch, reservation.id, reason: reason);
    }
    batch.set(
      _collection.doc(basketId),
      {
        'isCancelled': true,
        'cancelledAt': DateTime.now(),
        'cancelReason': reason.trim(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }
}

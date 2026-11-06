import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/crew_points.dart';

/// the Crew Points Program: seasons, each day's crews, point events, and
/// challenge tokens. Owner writes almost everything; an employee can only
/// submit a teamwork call-out (as pending) and spend their own challenge
/// token — see the points_* blocks in firestore.rules.
class CrewPointsService {
  CrewPointsService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final _seasons = _firestore.collection('points_seasons');
  static final _crews = _firestore.collection('points_crews');
  static final _events = _firestore.collection('points_events');
  static final _challenges = _firestore.collection('points_challenges');

  // ---------------------------------------------------------------- seasons

  static Stream<List<PointsSeason>> watchSeasons() {
    return _seasons.snapshots().map((snapshot) {
      final seasons = snapshot.docs
          .map((doc) => PointsSeason.fromMap({...doc.data(), 'id': doc.id}))
          .toList();
      seasons.sort((a, b) => b.startDate.compareTo(a.startDate));
      return seasons;
    });
  }

  /// the season running today; otherwise the next one coming up; otherwise
  /// the most recent one that ended (so the final board stays visible)
  static PointsSeason? currentOf(List<PointsSeason> seasons, {DateTime? now}) {
    if (seasons.isEmpty) return null;
    final today = now ?? DateTime.now();
    for (final season in seasons) {
      if (season.containsDay(today)) return season;
    }
    final upcoming = seasons.where((s) => s.startDate.isAfter(today)).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    if (upcoming.isNotEmpty) return upcoming.first;
    return seasons.first;
  }

  static Future<String> createSeason({
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    required double pointValue,
    required List<PointsParticipant> participants,
  }) async {
    final doc = _seasons.doc();
    final season = PointsSeason(
      id: doc.id,
      name: name.trim(),
      startDate: startDate,
      endDate: endDate,
      pointValue: pointValue,
      participants: participants,
      createdAt: DateTime.now(),
    );
    await doc.set(season.toMap());
    return doc.id;
  }

  static Future<void> updateSeason(PointsSeason season) =>
      _seasons.doc(season.id).set(season.toMap(), SetOptions(merge: true));

  static Future<void> setFinalized(String seasonId, bool finalized) => _seasons
      .doc(seasonId)
      .update({'finalizedAt': finalized ? DateTime.now() : null});

  // ------------------------------------------------------------------ crews

  static Stream<DailyCrews?> watchCrews(String seasonId, String day) {
    return _crews.doc(DailyCrews.docId(seasonId, day)).snapshots().map((doc) {
      final data = doc.data();
      return data == null ? null : DailyCrews.fromMap(data);
    });
  }

  static Future<DailyCrews?> fetchCrews(String seasonId, String day) async {
    final doc = await _crews.doc(DailyCrews.docId(seasonId, day)).get();
    final data = doc.data();
    return data == null ? null : DailyCrews.fromMap(data);
  }

  /// the most recent day before [day] that has crews set, so a new day can
  /// start from yesterday's lineup
  static Future<DailyCrews?> fetchLatestCrewsBefore(
      String seasonId, String day) async {
    final snapshot = await _crews.where('seasonId', isEqualTo: seasonId).get();
    final earlier = snapshot.docs
        .map((doc) => DailyCrews.fromMap(doc.data()))
        .where((c) => c.day.compareTo(day) < 0 && c.crews.isNotEmpty)
        .toList()
      ..sort((a, b) => b.day.compareTo(a.day));
    return earlier.isEmpty ? null : earlier.first;
  }

  /// save a day's crews. The day's daily checks (on time, clean truck, ...)
  /// belong to a crew, not to fixed people, so they're re-pointed at the
  /// crew's new members — and dropped if the crew itself was removed.
  static Future<void> saveCrews(DailyCrews crews) async {
    final batch = _firestore.batch();
    batch.set(
        _crews.doc(DailyCrews.docId(crews.seasonId, crews.day)), crews.toMap());

    final dayEvents = await _events
        .where('seasonId', isEqualTo: crews.seasonId)
        .where('day', isEqualTo: crews.day)
        .get();
    final byId = {for (final crew in crews.crews) crew.id: crew};
    for (final doc in dayEvents.docs) {
      final event = PointsEvent.fromMap({...doc.data(), 'id': doc.id});
      final isDailyCheck = event.id ==
          PointsEvent.dailyCheckId(
              event.seasonId, event.day, event.crewId ?? '', event.category);
      if (!isDailyCheck) continue;
      final crew = byId[event.crewId];
      if (crew == null) {
        batch.delete(doc.reference);
      } else {
        batch.update(doc.reference,
            {'employeeIds': crew.memberIds, 'crewName': crew.name});
      }
    }
    await batch.commit();
  }

  // ----------------------------------------------------------------- events

  static Stream<List<PointsEvent>> watchEvents(String seasonId) {
    return _events
        .where('seasonId', isEqualTo: seasonId)
        .snapshots()
        .map((snapshot) {
      final events = snapshot.docs
          .map((doc) => PointsEvent.fromMap({...doc.data(), 'id': doc.id}))
          .toList();
      events.sort((a, b) {
        final byDay = b.day.compareTo(a.day);
        return byDay != 0 ? byDay : b.createdAt.compareTo(a.createdAt);
      });
      return events;
    });
  }

  /// turn one of a crew's daily checks on (writes the event) or off
  /// (deletes it). On time and late are one control: setting either clears
  /// the other.
  static Future<void> setDailyCheck({
    required String seasonId,
    required String day,
    required PointsCrew crew,
    required String category,
    required bool on,
  }) async {
    final batch = _firestore.batch();
    final ref =
        _events.doc(PointsEvent.dailyCheckId(seasonId, day, crew.id, category));
    if (on) {
      final info = PointsCatalog.byKey(category);
      batch.set(
        ref,
        PointsEvent(
          id: ref.id,
          seasonId: seasonId,
          day: day,
          category: category,
          points: info.points,
          employeeIds: crew.memberIds,
          status: PointsEventStatus.approved,
          createdBy: 'owner',
          createdByName: 'Owner',
          createdAt: DateTime.now(),
          crewId: crew.id,
          crewName: crew.name,
        ).toMap(),
      );
    } else {
      batch.delete(ref);
    }
    final opposite = switch (category) {
      PointsCatalog.onTime => PointsCatalog.lateArrival,
      PointsCatalog.lateArrival => PointsCatalog.onTime,
      _ => null,
    };
    if (on && opposite != null) {
      batch.delete(_events
          .doc(PointsEvent.dailyCheckId(seasonId, day, crew.id, opposite)));
    }
    await batch.commit();
  }

  /// owner action: any other award or deduction (spot-check, damage,
  /// bonus, adjustment...)
  static Future<void> addEvent({
    required String seasonId,
    required String day,
    required String category,
    required int points,
    required List<String> employeeIds,
    String? crewId,
    String crewName = '',
    String note = '',
    String? clientId,
  }) async {
    final ref = _events.doc();
    await ref.set(PointsEvent(
      id: ref.id,
      seasonId: seasonId,
      day: day,
      category: category,
      points: points,
      employeeIds: employeeIds,
      status: PointsEventStatus.approved,
      createdBy: 'owner',
      createdByName: 'Owner',
      createdAt: DateTime.now(),
      crewId: crewId,
      crewName: crewName,
      note: note.trim(),
      clientId: clientId,
    ).toMap());
  }

  /// employee action: give +1 to another crew that helped yours. Lands as
  /// pending; it counts once the owner approves it.
  static Future<void> submitTeamworkCallout({
    required String seasonId,
    required String day,
    required PointsCrew crew,
    required String submittedBy,
    required String submittedByName,
    required String note,
  }) async {
    final ref = _events.doc();
    await ref.set(PointsEvent(
      id: ref.id,
      seasonId: seasonId,
      day: day,
      category: PointsCatalog.teamworkCallout,
      points: 1,
      employeeIds: crew.memberIds,
      status: PointsEventStatus.pending,
      createdBy: submittedBy,
      createdByName: submittedByName,
      createdAt: DateTime.now(),
      crewId: crew.id,
      crewName: crew.name,
      note: note.trim(),
    ).toMap());
  }

  /// owner: approve or reject a pending call-out, or reverse / restore any
  /// event
  static Future<void> setEventStatus(String eventId, String status,
      {String note = ''}) {
    return _events.doc(eventId).update({
      'status': status,
      'reviewedAt': DateTime.now(),
      'reviewNote': note.trim(),
    });
  }

  static Future<void> deleteEvent(String eventId) =>
      _events.doc(eventId).delete();

  // ------------------------------------------------------------- challenges

  static Stream<List<PointsChallenge>> watchChallenges(String seasonId) {
    return _challenges
        .where('seasonId', isEqualTo: seasonId)
        .snapshots()
        .map((snapshot) {
      final challenges = snapshot.docs
          .map((doc) => PointsChallenge.fromMap({...doc.data(), 'id': doc.id}))
          .toList();
      challenges.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return challenges;
    });
  }

  /// employee action: spend the season's one token on [event]. The doc id
  /// is fixed per employee per season and the rules allow create only, so a
  /// second challenge fails even if the UI is bypassed.
  static Future<void> submitChallenge({
    required String seasonId,
    required String employeeId,
    required String employeeName,
    required PointsEvent event,
    required String eventSummary,
    required String reason,
  }) async {
    final id = PointsChallenge.docId(seasonId, employeeId);
    await _challenges.doc(id).set({
      'id': id,
      'seasonId': seasonId,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'eventId': event.id,
      'eventSummary': eventSummary,
      'reason': reason.trim(),
      'status': ChallengeStatus.pending,
      'createdAt': DateTime.now(),
    });
  }

  /// owner action: rule on a challenge. Upholding it reverses the docked
  /// event for everyone it applied to.
  static Future<void> resolveChallenge({
    required PointsChallenge challenge,
    required bool upheld,
    String note = '',
  }) async {
    final batch = _firestore.batch();
    final now = DateTime.now();
    batch.update(_challenges.doc(challenge.id), {
      'status': upheld ? ChallengeStatus.upheld : ChallengeStatus.denied,
      'resolvedAt': now,
      'ownerNote': note.trim(),
    });
    if (upheld) {
      batch.update(_events.doc(challenge.eventId), {
        'status': PointsEventStatus.reversed,
        'reviewedAt': now,
        'reviewNote': 'Challenge upheld (${challenge.employeeName})',
      });
    }
    await batch.commit();
  }
}

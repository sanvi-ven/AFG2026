import 'package:cloud_firestore/cloud_firestore.dart';

/// which section of the program a category belongs to — drives its color
/// on the crew page (lime / gold / red, matching the program's promo video)
enum PointsGroup { daily, bonus, penalty, adjustment }

/// one scoring category from the Crew Points Program rules
class PointsCategory {
  const PointsCategory({
    required this.key,
    required this.name,
    required this.description,
    required this.points,
    required this.group,
    this.allowedPoints,
  });

  final String key;
  final String name;
  final String description;

  /// the default award; [allowedPoints] lists the other values the owner can
  /// pick (the weekly spot-check is +1 or +2)
  final int points;
  final PointsGroup group;
  final List<int>? allowedPoints;

  bool get isNegative => points < 0;
}

/// the program's categories. Keys are stored on every event, so never
/// rename one; names and descriptions are display-only and safe to edit.
class PointsCatalog {
  PointsCatalog._();

  static const onTime = 'on_time';
  static const cleanEquipment = 'clean_equipment';
  static const properEquipment = 'proper_equipment';
  static const bookkeeping = 'bookkeeping';
  static const qualitySpotCheck = 'quality_spot_check';
  static const lateArrival = 'late_arrival';
  static const equipmentDamage = 'equipment_damage';
  static const clientCallback = 'client_callback';
  static const clientComplaint = 'client_complaint';
  static const googleReview = 'google_review';
  static const photoOfDay = 'photo_of_day';
  static const teamworkCallout = 'teamwork_callout';
  static const weeklyMvp = 'weekly_mvp';
  static const adjustment = 'adjustment';

  static const all = <PointsCategory>[
    PointsCategory(
      key: onTime,
      name: 'On time',
      description:
          'Whole team out of the shop on time, gas stop done, and on time to start the first job.',
      points: 1,
      group: PointsGroup.daily,
    ),
    PointsCategory(
      key: cleanEquipment,
      name: 'Clean equipment + truck',
      description:
          'Blowers and tools wiped down and put away. Truck cleaned out, trash removed, cab blown out.',
      points: 1,
      group: PointsGroup.daily,
    ),
    PointsCategory(
      key: properEquipment,
      name: 'Proper equipment / uniform',
      description:
          'Right gear on the job. Nothing forgotten from the uniform SOP or shop packing list.',
      points: 1,
      group: PointsGroup.daily,
    ),
    PointsCategory(
      key: bookkeeping,
      name: 'Correct bookkeeping',
      description:
          'Start/end times tracked, everyone clocked in and out, before/after photos and job forms submitted.',
      points: 1,
      group: PointsGroup.daily,
    ),
    PointsCategory(
      key: qualitySpotCheck,
      name: 'Quality spot-check',
      description:
          'Once a week, Ryan picks one job site at random and rates the work.',
      points: 1,
      group: PointsGroup.daily,
      allowedPoints: [1, 2],
    ),
    PointsCategory(
      key: googleReview,
      name: '5-star Google review',
      description: 'A customer leaves us 5 stars. One point per client.',
      points: 1,
      group: PointsGroup.bonus,
    ),
    PointsCategory(
      key: photoOfDay,
      name: 'Photo of the day',
      description:
          'Best before-and-after cleanup shot, picked by Ryan or the crew.',
      points: 1,
      group: PointsGroup.bonus,
    ),
    PointsCategory(
      key: teamworkCallout,
      name: 'Teamwork call-out',
      description: 'A crew awards it to another team that helped them out.',
      points: 1,
      group: PointsGroup.bonus,
    ),
    PointsCategory(
      key: weeklyMvp,
      name: 'Weekly MVP team',
      description: 'The team with the best overall week.',
      points: 1,
      group: PointsGroup.bonus,
    ),
    PointsCategory(
      key: lateArrival,
      name: 'Late arrival',
      description:
          'Team was not all on time: in the shop driveway (not the back circle), or on the job property, by arrival time.',
      points: -1,
      group: PointsGroup.penalty,
    ),
    PointsCategory(
      key: clientComplaint,
      name: 'Client complaint',
      description:
          'Bad review, angry message, or anything else negative caused by the crew.',
      points: -1,
      group: PointsGroup.penalty,
    ),
    PointsCategory(
      key: equipmentDamage,
      name: 'Careless damage',
      description:
          'Equipment damaged from carelessness, not normal wear and tear.',
      points: -2,
      group: PointsGroup.penalty,
    ),
    PointsCategory(
      key: clientCallback,
      name: 'Client callback',
      description:
          'A client reports a problem with the job and it is confirmed.',
      points: -3,
      group: PointsGroup.penalty,
    ),
    PointsCategory(
      key: adjustment,
      name: 'Adjustment',
      description: 'A manual correction by the owner.',
      points: 0,
      group: PointsGroup.adjustment,
    ),
  ];

  /// the four yes/no checks scored for every crew every day (on time vs.
  /// late is its own three-way control)
  static const dailyToggles = [cleanEquipment, properEquipment, bookkeeping];

  static PointsCategory byKey(String key) => all.firstWhere(
        (category) => category.key == key,
        orElse: () => PointsCategory(
          key: key,
          name: key,
          description: '',
          points: 0,
          group: PointsGroup.adjustment,
        ),
      );
}

DateTime _readDate(dynamic value, [DateTime? fallback]) {
  if (value is Timestamp) return value.toDate();
  if (value is String) {
    return DateTime.tryParse(value) ?? fallback ?? DateTime.now();
  }
  return fallback ?? DateTime.now();
}

DateTime? _readOptionalDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value);
  return null;
}

/// "2026-10-26" — the day key used on crews and events, in local time
String pointsDayKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime pointsDayFromKey(String key) {
  final parts = key.split('-').map(int.tryParse).toList();
  if (parts.length != 3 || parts.contains(null)) return DateTime.now();
  return DateTime(parts[0]!, parts[1]!, parts[2]!);
}

/// someone in the program. The name is copied here (and onto crews) because
/// employees can't read each other's profiles under firestore.rules, and
/// the leaderboard has to show everyone.
class PointsParticipant {
  const PointsParticipant({required this.employeeId, required this.name});

  final String employeeId;
  final String name;

  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  /// "RP" from "Ryan Prendergast", for avatars
  String get initials {
    final words =
        name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first[0].toUpperCase();
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }

  factory PointsParticipant.fromMap(Map<String, dynamic> map) =>
      PointsParticipant(
        employeeId: (map['employeeId'] as String? ?? '').trim(),
        name: (map['name'] as String? ?? '').trim(),
      );

  Map<String, dynamic> toMap() => {'employeeId': employeeId, 'name': name};
}

/// one run of the program (e.g. "Fall 2026"), with its roster
class PointsSeason {
  const PointsSeason({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.pointValue,
    required this.participants,
    required this.createdAt,
    this.finalizedAt,
  });

  final String id;
  final String name;

  /// first and last day of the season, inclusive
  final DateTime startDate;
  final DateTime endDate;

  /// dollars paid per point at the end of the season
  final double pointValue;
  final List<PointsParticipant> participants;
  final DateTime createdAt;

  /// set when the owner locks the final totals for payout
  final DateTime? finalizedAt;

  bool get isFinalized => finalizedAt != null;

  int get totalDays => endDate.difference(startDate).inDays + 1;
  int get totalWeeks => (totalDays / 7).ceil();

  bool containsDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(startDate) && !d.isAfter(endDate);
  }

  /// 1-based week of the season [day] falls in, clamped to the season
  int weekOf(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final days = d.difference(startDate).inDays;
    return (days ~/ 7 + 1).clamp(1, totalWeeks);
  }

  PointsParticipant? participant(String employeeId) {
    for (final p in participants) {
      if (p.employeeId == employeeId) return p;
    }
    return null;
  }

  factory PointsSeason.fromMap(Map<String, dynamic> map) {
    final start = _readDate(map['startDate']);
    final end = _readDate(map['endDate']);
    return PointsSeason(
      id: (map['id'] as String? ?? '').trim(),
      name: (map['name'] as String? ?? '').trim(),
      startDate: DateTime(start.year, start.month, start.day),
      endDate: DateTime(end.year, end.month, end.day),
      pointValue: (map['pointValue'] as num? ?? 1).toDouble(),
      participants: (map['participants'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((p) => PointsParticipant.fromMap(p.cast<String, dynamic>()))
          .toList(),
      createdAt: _readDate(map['createdAt']),
      finalizedAt: _readOptionalDate(map['finalizedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'startDate': startDate,
        'endDate': endDate,
        'pointValue': pointValue,
        'participants': participants.map((p) => p.toMap()).toList(),
        'createdAt': createdAt,
        'finalizedAt': finalizedAt,
      };
}

/// one crew as set up for one day
class PointsCrew {
  const PointsCrew(
      {required this.id, required this.name, required this.memberIds});

  final String id;
  final String name;
  final List<String> memberIds;

  factory PointsCrew.fromMap(Map<String, dynamic> map) => PointsCrew(
        id: (map['id'] as String? ?? '').trim(),
        name: (map['name'] as String? ?? '').trim(),
        memberIds: (map['memberIds'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
      );

  Map<String, dynamic> toMap() =>
      {'id': id, 'name': name, 'memberIds': memberIds};

  PointsCrew copyWith({String? name, List<String>? memberIds}) => PointsCrew(
      id: id, name: name ?? this.name, memberIds: memberIds ?? this.memberIds);
}

/// the crews for one day of a season. Doc id `<seasonId>_<yyyy-MM-dd>`.
class DailyCrews {
  const DailyCrews(
      {required this.seasonId, required this.day, required this.crews});

  final String seasonId;

  /// [pointsDayKey] format
  final String day;
  final List<PointsCrew> crews;

  static String docId(String seasonId, String day) => '${seasonId}_$day';

  PointsCrew? crewOf(String employeeId) {
    for (final crew in crews) {
      if (crew.memberIds.contains(employeeId)) return crew;
    }
    return null;
  }

  factory DailyCrews.fromMap(Map<String, dynamic> map) => DailyCrews(
        seasonId: (map['seasonId'] as String? ?? '').trim(),
        day: (map['day'] as String? ?? '').trim(),
        crews: (map['crews'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((c) => PointsCrew.fromMap(c.cast<String, dynamic>()))
            .toList(),
      );

  Map<String, dynamic> toMap() => {
        'seasonId': seasonId,
        'day': day,
        'crews': crews.map((c) => c.toMap()).toList(),
      };
}

class PointsEventStatus {
  PointsEventStatus._();

  /// counts toward totals
  static const approved = 'approved';

  /// an employee's teamwork call-out awaiting the owner
  static const pending = 'pending';

  /// a call-out the owner turned down
  static const rejected = 'rejected';

  /// taken back (an upheld challenge, or an owner correction); kept for the
  /// record and shown struck through
  static const reversed = 'reversed';
}

/// points earned or lost by everyone on a crew (or by named people) on one
/// day. [employeeIds] is a snapshot of who gets them, so a later crew
/// change never moves points that were already earned — except for the
/// daily checks, which follow the crew they belong to ([crewId]) when the
/// owner edits that same day's crew.
class PointsEvent {
  const PointsEvent({
    required this.id,
    required this.seasonId,
    required this.day,
    required this.category,
    required this.points,
    required this.employeeIds,
    required this.status,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    this.crewId,
    this.crewName = '',
    this.note = '',
    this.clientId,
    this.reviewedAt,
    this.reviewNote = '',
  });

  final String id;
  final String seasonId;
  final String day;
  final String category;
  final int points;
  final List<String> employeeIds;
  final String status;

  /// 'owner', or the employee id of whoever submitted a call-out
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final String? crewId;
  final String crewName;
  final String note;

  /// google reviews only: the client it came from (capped at one per client)
  final String? clientId;
  final DateTime? reviewedAt;
  final String reviewNote;

  bool get counts => status == PointsEventStatus.approved;
  bool get isPending => status == PointsEventStatus.pending;
  bool get isReversed => status == PointsEventStatus.reversed;
  PointsCategory get categoryInfo => PointsCatalog.byKey(category);
  DateTime get date => pointsDayFromKey(day);

  /// the deterministic id of a daily check, so toggling it on and off
  /// writes and deletes the same doc instead of piling up duplicates
  static String dailyCheckId(
          String seasonId, String day, String crewId, String category) =>
      '${seasonId}_${day}_${crewId}_$category';

  factory PointsEvent.fromMap(Map<String, dynamic> map) => PointsEvent(
        id: (map['id'] as String? ?? '').trim(),
        seasonId: (map['seasonId'] as String? ?? '').trim(),
        day: (map['day'] as String? ?? '').trim(),
        category: (map['category'] as String? ?? '').trim(),
        points: (map['points'] as num? ?? 0).toInt(),
        employeeIds: (map['employeeIds'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        status: (map['status'] as String? ?? PointsEventStatus.approved).trim(),
        createdBy: (map['createdBy'] as String? ?? '').trim(),
        createdByName: (map['createdByName'] as String? ?? '').trim(),
        createdAt: _readDate(map['createdAt']),
        crewId: (map['crewId'] as String?)?.trim(),
        crewName: (map['crewName'] as String? ?? '').trim(),
        note: (map['note'] as String? ?? '').trim(),
        clientId: (map['clientId'] as String?)?.trim(),
        reviewedAt: _readOptionalDate(map['reviewedAt']),
        reviewNote: (map['reviewNote'] as String? ?? '').trim(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'seasonId': seasonId,
        'day': day,
        'category': category,
        'points': points,
        'employeeIds': employeeIds,
        'status': status,
        'createdBy': createdBy,
        'createdByName': createdByName,
        'createdAt': createdAt,
        'crewId': crewId,
        'crewName': crewName,
        'note': note,
        'clientId': clientId,
        'reviewedAt': reviewedAt,
        'reviewNote': reviewNote,
      };
}

class ChallengeStatus {
  ChallengeStatus._();
  static const pending = 'pending';

  /// the employee had a case: the event was reversed
  static const upheld = 'upheld';
  static const denied = 'denied';
}

/// an employee spending their one challenge token on a docked point. Doc id
/// `<seasonId>_<employeeId>`, and firestore.rules lets an employee only
/// create it, never update it, so the token can be spent exactly once.
class PointsChallenge {
  const PointsChallenge({
    required this.id,
    required this.seasonId,
    required this.employeeId,
    required this.employeeName,
    required this.eventId,
    required this.eventSummary,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
    this.ownerNote = '',
  });

  final String id;
  final String seasonId;
  final String employeeId;
  final String employeeName;
  final String eventId;

  /// e.g. "Late arrival (−1) on Oct 28", frozen at challenge time
  final String eventSummary;
  final String reason;
  final String status;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String ownerNote;

  static String docId(String seasonId, String employeeId) =>
      '${seasonId}_$employeeId';

  bool get isPending => status == ChallengeStatus.pending;

  factory PointsChallenge.fromMap(Map<String, dynamic> map) => PointsChallenge(
        id: (map['id'] as String? ?? '').trim(),
        seasonId: (map['seasonId'] as String? ?? '').trim(),
        employeeId: (map['employeeId'] as String? ?? '').trim(),
        employeeName: (map['employeeName'] as String? ?? '').trim(),
        eventId: (map['eventId'] as String? ?? '').trim(),
        eventSummary: (map['eventSummary'] as String? ?? '').trim(),
        reason: (map['reason'] as String? ?? '').trim(),
        status: (map['status'] as String? ?? ChallengeStatus.pending).trim(),
        createdAt: _readDate(map['createdAt']),
        resolvedAt: _readOptionalDate(map['resolvedAt']),
        ownerNote: (map['ownerNote'] as String? ?? '').trim(),
      );
}

/// one row of the leaderboard
class PointsStanding {
  const PointsStanding({
    required this.participant,
    required this.rawPoints,
    required this.weekPoints,
    required this.rank,
    required this.previousRank,
  });

  final PointsParticipant participant;

  /// sum of every counting event; can dip below zero mid-season
  final int rawPoints;

  /// points earned in the current week of the season
  final int weekPoints;
  final int rank;

  /// rank as of a week ago, for the up/down arrow; null if there's no
  /// history yet
  final int? previousRank;

  /// what's shown and paid: the rules say you can't go below 0 points
  int get points => rawPoints < 0 ? 0 : rawPoints;

  /// positive = moved up the board
  int get movement => previousRank == null ? 0 : previousRank! - rank;
}

/// the leaderboard math, kept pure so it's easy to test
class PointsMath {
  PointsMath._();

  static int pointsFor(String employeeId, Iterable<PointsEvent> events,
      {bool Function(PointsEvent)? where}) {
    var total = 0;
    for (final event in events) {
      if (!event.counts || !event.employeeIds.contains(employeeId)) continue;
      if (where != null && !where(event)) continue;
      total += event.points;
    }
    return total;
  }

  /// competition ranking: ties share a rank and the next rank is skipped
  /// (10, 10, 8 → 1, 1, 3)
  static Map<String, int> _ranks(Map<String, int> pointsById) {
    final sorted = pointsById.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final ranks = <String, int>{};
    for (var i = 0; i < sorted.length; i++) {
      ranks[sorted[i].key] = i > 0 && sorted[i].value == sorted[i - 1].value
          ? ranks[sorted[i - 1].key]!
          : i + 1;
    }
    return ranks;
  }

  static List<PointsStanding> standings(
    PointsSeason season,
    List<PointsEvent> events, {
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final todayKey = pointsDayKey(today);
    final weekStart =
        season.startDate.add(Duration(days: (season.weekOf(today) - 1) * 7));
    final weekStartKey = pointsDayKey(weekStart);
    final weekAgoKey = pointsDayKey(today.subtract(const Duration(days: 7)));

    int floor(int p) => p < 0 ? 0 : p;
    final current = <String, int>{};
    final previous = <String, int>{};
    final week = <String, int>{};
    for (final p in season.participants) {
      current[p.employeeId] = pointsFor(p.employeeId, events);
      previous[p.employeeId] = floor(pointsFor(p.employeeId, events,
          where: (e) => e.day.compareTo(weekAgoKey) <= 0));
      week[p.employeeId] = pointsFor(p.employeeId, events,
          where: (e) =>
              e.day.compareTo(weekStartKey) >= 0 &&
              e.day.compareTo(todayKey) <= 0);
    }
    final ranks = _ranks(current.map((k, v) => MapEntry(k, floor(v))));
    final hasHistory =
        events.any((e) => e.counts && e.day.compareTo(weekAgoKey) <= 0);
    final previousRanks = hasHistory ? _ranks(previous) : const <String, int>{};

    final rows = [
      for (final p in season.participants)
        PointsStanding(
          participant: p,
          rawPoints: current[p.employeeId]!,
          weekPoints: week[p.employeeId]!,
          rank: ranks[p.employeeId]!,
          previousRank: previousRanks[p.employeeId],
        ),
    ];
    rows.sort((a, b) {
      final byRank = a.rank.compareTo(b.rank);
      return byRank != 0
          ? byRank
          : a.participant.name
              .toLowerCase()
              .compareTo(b.participant.name.toLowerCase());
    });
    return rows;
  }
}

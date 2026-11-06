import 'package:anchor/models/crew_points.dart';
import 'package:flutter_test/flutter_test.dart';

PointsEvent event(String id, String day, int points, List<String> who,
        {String status = PointsEventStatus.approved, String category = 'on_time'}) =>
    PointsEvent(
      id: id,
      seasonId: 's',
      day: day,
      category: category,
      points: points,
      employeeIds: who,
      status: status,
      createdBy: 'owner',
      createdByName: 'Owner',
      createdAt: DateTime(2026, 10, 26),
    );

void main() {
  final season = PointsSeason(
    id: 's',
    name: 'Fall 2026',
    startDate: DateTime(2026, 10, 26),
    endDate: DateTime(2026, 12, 6),
    pointValue: 1,
    participants: const [
      PointsParticipant(employeeId: 'a', name: 'Alex Doe'),
      PointsParticipant(employeeId: 'b', name: 'Blair Roe'),
      PointsParticipant(employeeId: 'c', name: 'Casey Poe'),
    ],
    createdAt: DateTime(2026, 10, 1),
  );

  test('season shape: 6 weeks, week numbering', () {
    expect(season.totalWeeks, 6);
    expect(season.weekOf(DateTime(2026, 10, 26)), 1);
    expect(season.weekOf(DateTime(2026, 11, 2)), 2);
    expect(season.weekOf(DateTime(2026, 12, 6)), 6);
  });

  test('points follow people across crews; only approved events count', () {
    final events = [
      event('1', '2026-10-26', 1, ['a', 'b']), // day 1: a+b crew
      event('2', '2026-10-27', 1, ['a', 'c']), // day 2: teams changed
      event('3', '2026-10-27', -1, ['c'], category: 'late_arrival'),
      event('4', '2026-10-27', 1, ['b'], status: PointsEventStatus.pending),
      event('5', '2026-10-27', -3, ['a'], status: PointsEventStatus.reversed),
    ];
    final rows = PointsMath.standings(season, events, now: DateTime(2026, 10, 28));
    final byId = {for (final r in rows) r.participant.employeeId: r};
    expect(byId['a']!.points, 2);
    expect(byId['b']!.points, 1);
    expect(byId['c']!.points, 0);
    expect(rows.first.participant.employeeId, 'a');
  });

  test('ties share a rank and the next rank is skipped', () {
    final events = [
      event('1', '2026-10-26', 2, ['a', 'b']),
      event('2', '2026-10-26', 1, ['c']),
    ];
    final rows = PointsMath.standings(season, events, now: DateTime(2026, 10, 26));
    expect(rows.map((r) => r.rank), [1, 1, 3]);
  });

  test('totals never show below zero', () {
    final events = [event('1', '2026-10-26', -3, ['c'], category: 'client_callback')];
    final c = PointsMath.standings(season, events, now: DateTime(2026, 10, 26))
        .firstWhere((r) => r.participant.employeeId == 'c');
    expect(c.rawPoints, -3);
    expect(c.points, 0);
  });

  test('week points and movement over the last 7 days', () {
    final events = [
      event('1', '2026-10-26', 3, ['b']), // week 1: b leads
      event('2', '2026-11-03', 5, ['a']), // week 2: a overtakes
    ];
    final rows = PointsMath.standings(season, events, now: DateTime(2026, 11, 4));
    final a = rows.firstWhere((r) => r.participant.employeeId == 'a');
    final b = rows.firstWhere((r) => r.participant.employeeId == 'b');
    expect(a.weekPoints, 5);
    expect(b.weekPoints, 0);
    expect(a.rank, 1);
    expect(a.movement, greaterThan(0));
    expect(b.movement, lessThan(0));
  });

  test('participant initials', () {
    expect(const PointsParticipant(employeeId: 'x', name: 'Ryan Prendergast').initials, 'RP');
    expect(const PointsParticipant(employeeId: 'x', name: 'Cher').initials, 'C');
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/crew_points_service.dart';
import '../../../core/state/employee_session.dart';
import '../../../models/crew_points.dart';
import '../../../shared/utils/stream_cache.dart';
import '../../../shared/widgets/app_scaffold.dart';
import 'crew_points_admin_page.dart';
import 'crew_points_widgets.dart';

/// entry point for the Crew Points nav item: the owner gets the scoring
/// tools, an employee gets the crew view
class CrewPointsPage extends StatelessWidget {
  const CrewPointsPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  @override
  Widget build(BuildContext context) {
    if (role == 'owner') {
      return CrewPointsAdminPage(role: role, authToken: authToken);
    }
    return AppScaffold(
      title: 'Crew Points',
      role: role,
      authToken: authToken,
      selectedRoute: AppRouter.crewPoints,
      body: const CrewPointsBoard(),
    );
  }
}

/// the crew-facing view: your score, today's crew, the leaderboard, your
/// challenge token, your point history, and the rules. With no signed-in
/// employee (the owner's "Crew view" preview) it shows the shared parts.
class CrewPointsBoard extends StatefulWidget {
  const CrewPointsBoard({this.employeeId, super.key});

  /// defaults to the signed-in employee
  final String? employeeId;

  @override
  State<CrewPointsBoard> createState() => _CrewPointsBoardState();
}

class _CrewPointsBoardState extends State<CrewPointsBoard> {
  final _streams = StreamCache();

  String? get _me =>
      widget.employeeId ?? EmployeeSession.profile.value?.employeeId;

  @override
  Widget build(BuildContext context) {
    return FallingLeavesBackground(
      child: StreamBuilder<List<PointsSeason>>(
        stream: _streams.get('seasons', null, CrewPointsService.watchSeasons),
        builder: (context, seasonSnapshot) {
          if (seasonSnapshot.hasError) {
            return _centered('Could not load Crew Points.');
          }
          if (!seasonSnapshot.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: PointsColors.lime));
          }
          final season = CrewPointsService.currentOf(seasonSnapshot.data!);
          if (season == null) {
            return _centered('No Crew Points season has been set up yet.');
          }
          final today = pointsDayKey(DateTime.now());
          return StreamBuilder<List<PointsEvent>>(
            stream: _streams.get('events', season.id,
                () => CrewPointsService.watchEvents(season.id)),
            builder: (context, eventSnapshot) {
              final events = eventSnapshot.data ?? const <PointsEvent>[];
              return StreamBuilder<DailyCrews?>(
                stream: _streams.get('crews', (season.id, today),
                    () => CrewPointsService.watchCrews(season.id, today)),
                builder: (context, crewSnapshot) {
                  return StreamBuilder<List<PointsChallenge>>(
                    stream: _streams.get('challenges', season.id,
                        () => CrewPointsService.watchChallenges(season.id)),
                    builder: (context, challengeSnapshot) {
                      return CrewPointsBoardBody(
                        season: season,
                        events: events,
                        todayCrews: crewSnapshot.data,
                        challenges: challengeSnapshot.data ?? const [],
                        me: _me,
                        loading: !eventSnapshot.hasData,
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _centered(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: PointsColors.muted, fontSize: 16)),
        ),
      );
}

/// the board itself, given its data — public so it can be rendered with
/// sample data in tests
class CrewPointsBoardBody extends StatelessWidget {
  const CrewPointsBoardBody({
    super.key,
    required this.season,
    required this.events,
    required this.todayCrews,
    required this.challenges,
    required this.me,
    required this.loading,
  });

  final PointsSeason season;
  final List<PointsEvent> events;
  final DailyCrews? todayCrews;
  final List<PointsChallenge> challenges;
  final String? me;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final standings = PointsMath.standings(season, events);
    final myStanding = me == null
        ? null
        : standings.where((s) => s.participant.employeeId == me).firstOrNull;
    final myChallenge = me == null
        ? null
        : challenges
            .where((c) => c.id == PointsChallenge.docId(season.id, me!))
            .firstOrNull;

    final sections = <Widget>[
      _SeasonHeader(season: season),
      if (myStanding != null)
        _MyScore(season: season, standing: myStanding, total: standings.length)
      else if (me != null)
        const PointsCard(
          child: Text(
            "You're not on this season's roster yet. Ask Ryan to add you.",
            style: TextStyle(color: PointsColors.text),
          ),
        ),
      _TodayCrew(
        season: season,
        crews: todayCrews,
        events: events,
        me: myStanding == null ? null : me,
      ),
      _Leaderboard(
          season: season, standings: standings, me: me, loading: loading),
      if (myStanding != null) ...[
        _TokenCard(challenge: myChallenge),
        _MyActivity(
          season: season,
          events: events,
          me: me!,
          myName: myStanding.participant.name,
          tokenAvailable: myChallenge == null && !season.isFinalized,
        ),
      ],
      _HowItWorks(pointValue: season.pointValue),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < sections.length; i++) ...[
                  PointsEntrance(
                      delay: Duration(milliseconds: 90 * i),
                      child: sections[i]),
                  const SizedBox(height: 18),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ header

class _SeasonHeader extends StatelessWidget {
  const _SeasonHeader({required this.season});

  final PointsSeason season;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final String status;
    final double progress;
    if (today.isBefore(season.startDate)) {
      final days = season.startDate.difference(today).inDays;
      status = 'STARTS IN $days DAY${days == 1 ? '' : 'S'}';
      progress = 0;
    } else if (today.isAfter(season.endDate)) {
      status = season.isFinalized
          ? 'SEASON OVER · FINAL'
          : 'SEASON OVER · TOTALS LOCKING';
      progress = 1;
    } else {
      final daysLeft = season.endDate.difference(today).inDays;
      status = 'WEEK ${season.weekOf(today)} OF ${season.totalWeeks} · '
          '$daysLeft DAY${daysLeft == 1 ? '' : 'S'} LEFT';
      progress =
          (today.difference(season.startDate).inDays + 1) / season.totalDays;
    }
    return Column(
      children: [
        PointsEyebrow(season.name),
        const SizedBox(height: 10),
        FittedBox(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: 'CREW ', style: pointsDisplay(44)),
              TextSpan(
                  text: 'POINTS',
                  style: pointsDisplay(44, color: PointsColors.lime)),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        Text(status, style: pointsEyebrow(color: PointsColors.muted)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              color: PointsColors.lime,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- my score

/// the big animated total. If it went up since the last visit, the gain
/// floats up over it with a burst of confetti.
class _MyScore extends StatefulWidget {
  const _MyScore(
      {required this.season, required this.standing, required this.total});

  final PointsSeason season;
  final PointsStanding standing;
  final int total;

  @override
  State<_MyScore> createState() => _MyScoreState();
}

class _MyScoreState extends State<_MyScore> {
  int? _gain;

  String get _seenKey =>
      'crew_points_seen_${widget.season.id}_${widget.standing.participant.employeeId}';

  @override
  void initState() {
    super.initState();
    _checkGain();
  }

  @override
  void didUpdateWidget(_MyScore oldWidget) {
    super.didUpdateWidget(oldWidget);
    final delta = widget.standing.points - oldWidget.standing.points;
    if (delta != 0) {
      setState(() => _gain = delta);
      _remember();
    }
  }

  Future<void> _checkGain() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getInt(_seenKey);
      final now = widget.standing.points;
      if (seen != null && seen != now && mounted) {
        setState(() => _gain = now - seen);
      }
      await prefs.setInt(_seenKey, now);
    } catch (_) {
      // storage unavailable (private window etc.) — just skip the celebration
    }
  }

  Future<void> _remember() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_seenKey, widget.standing.points);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final standing = widget.standing;
    final dollars = standing.points * widget.season.pointValue;
    final gain = _gain;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        PointsCard(
          highlighted: true,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Row(
            children: [
              PointsAvatar(
                  participant: standing.participant,
                  size: 58,
                  ring: PointsColors.lime),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('YOUR SEASON', style: pointsEyebrow()),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        AnimatedPointsNumber(
                            value: standing.points.toDouble(),
                            style: pointsDisplay(52)),
                        const SizedBox(width: 6),
                        Text('PTS',
                            style:
                                pointsDisplay(18, color: PointsColors.muted)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text('= ',
                            style: pointsDisplay(20, color: PointsColors.gold)),
                        AnimatedPointsNumber(
                          value: dollars,
                          prefix: '\$',
                          decimals: dollars == dollars.roundToDouble() ? 0 : 2,
                          style: pointsDisplay(22, color: PointsColors.gold),
                        ),
                        Text(' BONUS',
                            style: pointsDisplay(16, color: PointsColors.gold)),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('#${standing.rank}',
                      style: pointsDisplay(34, color: PointsColors.lime)),
                  Text('of ${widget.total}',
                      style: const TextStyle(
                          color: PointsColors.muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  _Movement(movement: standing.movement),
                  if (standing.weekPoints != 0) ...[
                    const SizedBox(height: 4),
                    Text('${signedPoints(standing.weekPoints)} this week',
                        style: TextStyle(
                            color: standing.weekPoints > 0
                                ? PointsColors.lime
                                : PointsColors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (gain != null && gain != 0) ...[
          if (gain > 0) const Positioned.fill(child: ConfettiBurst()),
          Positioned(
              left: 110,
              top: 10,
              child: FloatingGain(key: ValueKey(gain), gain: gain)),
        ],
      ],
    );
  }
}

class _Movement extends StatelessWidget {
  const _Movement({required this.movement});

  final int movement;

  @override
  Widget build(BuildContext context) {
    if (movement == 0) {
      return const Icon(Icons.remove, size: 16, color: PointsColors.muted);
    }
    final up = movement > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(up ? Icons.arrow_drop_up : Icons.arrow_drop_down,
            color: up ? PointsColors.lime : PointsColors.red, size: 22),
        Text('${movement.abs()}',
            style: TextStyle(
                color: up ? PointsColors.lime : PointsColors.red,
                fontWeight: FontWeight.w800,
                fontSize: 12)),
      ],
    );
  }
}

// -------------------------------------------------------------- today crew

class _TodayCrew extends StatelessWidget {
  const _TodayCrew(
      {required this.season,
      required this.crews,
      required this.events,
      this.me});

  final PointsSeason season;
  final DailyCrews? crews;
  final List<PointsEvent> events;
  final String? me;

  Future<void> _shoutOut(BuildContext context, List<PointsCrew> others) async {
    final me = this.me!;
    final result = await showDialog<(PointsCrew, String)>(
      context: context,
      builder: (_) => _ShoutOutDialog(crews: others),
    );
    if (result == null || !context.mounted) return;
    try {
      await CrewPointsService.submitTeamworkCallout(
        seasonId: season.id,
        day: pointsDayKey(DateTime.now()),
        crew: result.$1,
        submittedBy: me,
        submittedByName: season.participant(me)?.name ?? '',
        note: result.$2,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Shout-out sent! ${result.$1.name} gets +1 once Ryan approves it.')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not send the shout-out: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = pointsDayKey(DateTime.now());
    final crews = this.crews?.crews ?? const <PointsCrew>[];
    final myCrew = me == null ? null : this.crews?.crewOf(me!);
    final shown = myCrew != null ? [myCrew] : crews;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
            child: PointsEyebrow(
                myCrew != null ? 'Today · ${myCrew.name}' : "Today's crews")),
        const SizedBox(height: 10),
        if (shown.isEmpty)
          const PointsCard(
            child: Text("Crews for today haven't been set yet.",
                style: TextStyle(color: PointsColors.muted)),
          ),
        for (final crew in shown) ...[
          _CrewDayCard(
            season: season,
            crew: crew,
            dayEvents: events
                .where((e) =>
                    e.day == today && e.crewId == crew.id && !e.isPending)
                .toList(),
            highlighted: crew == myCrew,
          ),
          const SizedBox(height: 10),
        ],
        if (me != null && myCrew != null && crews.length > 1)
          Center(
            child: OutlinedButton.icon(
              onPressed: () => _shoutOut(
                  context, crews.where((c) => c.id != myCrew.id).toList()),
              icon: const Icon(Icons.celebration_outlined),
              label: const Text('Shout out a crew that helped you'),
              style: OutlinedButton.styleFrom(
                foregroundColor: PointsColors.gold,
                side: const BorderSide(color: PointsColors.gold),
              ),
            ),
          ),
      ],
    );
  }
}

class _CrewDayCard extends StatelessWidget {
  const _CrewDayCard({
    required this.season,
    required this.crew,
    required this.dayEvents,
    required this.highlighted,
  });

  final PointsSeason season;
  final PointsCrew crew;
  final List<PointsEvent> dayEvents;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final counted = dayEvents.where((e) => e.counts).toList();
    final dayTotal = counted.fold<int>(0, (sum, e) => sum + e.points);
    bool has(String category) => counted.any((e) => e.category == category);

    final checks = <(String, Color?, String)>[
      if (has(PointsCatalog.onTime))
        ('On time', PointsColors.lime, '+1')
      else if (has(PointsCatalog.lateArrival))
        ('Late', PointsColors.red, '−1')
      else
        ('On time', null, '—'),
      for (final key in PointsCatalog.dailyToggles)
        (
          PointsCatalog.byKey(key).name,
          has(key) ? PointsColors.lime : null,
          has(key) ? '+1' : '—'
        ),
    ];
    final extras = counted.where((e) =>
        e.category != PointsCatalog.onTime &&
        e.category != PointsCatalog.lateArrival &&
        !PointsCatalog.dailyToggles.contains(e.category));

    return PointsCard(
      highlighted: highlighted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(crew.name.toUpperCase(), style: pointsDisplay(18)),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: -6,
                  children: [
                    for (final id in crew.memberIds)
                      if (season.participant(id) case final p?)
                        Tooltip(
                          message: p.name,
                          child: PointsAvatar(
                              participant: p,
                              size: 30,
                              ring: PointsColors.background),
                        ),
                  ],
                ),
              ),
              if (dayTotal != 0)
                Text(signedPoints(dayTotal),
                    style: pointsDisplay(24,
                        color: dayTotal > 0
                            ? PointsColors.lime
                            : PointsColors.red)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (label, color, points) in checks)
                _CheckChip(label: label, color: color, points: points),
              for (final event in extras)
                _CheckChip(
                  label: event.categoryInfo.name,
                  color: PointsColors.forGroup(event.categoryInfo.group,
                      points: event.points),
                  points: signedPoints(event.points),
                ),
            ],
          ),
          if (checks.any((c) => c.$2 == null))
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Ryan scores the rest at the end of the day.',
                  style: TextStyle(color: PointsColors.muted, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _CheckChip extends StatelessWidget {
  const _CheckChip(
      {required this.label, required this.color, required this.points});

  final String label;
  final Color? color;
  final String points;

  @override
  Widget build(BuildContext context) {
    final color = this.color;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color == null
            ? Colors.white.withValues(alpha: 0.05)
            : color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: color == null
                ? Colors.white.withValues(alpha: 0.12)
                : color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            color == null
                ? Icons.radio_button_unchecked
                : color == PointsColors.red
                    ? Icons.cancel
                    : Icons.check_circle,
            size: 15,
            color: color ?? PointsColors.muted,
          ),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color == null ? PointsColors.muted : PointsColors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          Text(points,
              style: TextStyle(
                  color: color ?? PointsColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _ShoutOutDialog extends StatefulWidget {
  const _ShoutOutDialog({required this.crews});

  final List<PointsCrew> crews;

  @override
  State<_ShoutOutDialog> createState() => _ShoutOutDialogState();
}

class _ShoutOutDialogState extends State<_ShoutOutDialog> {
  late PointsCrew _crew = widget.crews.first;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Teamwork call-out'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
              'Give +1 to a crew that helped yours out today. Ryan approves it first.'),
          const SizedBox(height: 12),
          DropdownButtonFormField<PointsCrew>(
            initialValue: _crew,
            decoration: const InputDecoration(
                labelText: 'Crew', border: OutlineInputBorder()),
            items: [
              for (final crew in widget.crews)
                DropdownMenuItem(value: crew, child: Text(crew.name)),
            ],
            onChanged: (crew) => setState(() => _crew = crew ?? _crew),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'How did they help?', border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_note.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Say how they helped.')));
              return;
            }
            Navigator.of(context).pop((_crew, _note.text.trim()));
          },
          child: const Text('Send shout-out'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- leaderboard

class _Leaderboard extends StatelessWidget {
  const _Leaderboard({
    required this.season,
    required this.standings,
    required this.me,
    required this.loading,
  });

  final PointsSeason season;
  final List<PointsStanding> standings;
  final String? me;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (standings.isEmpty) {
      return const PointsCard(
        child: Text('Nobody is on the roster yet.',
            style: TextStyle(color: PointsColors.muted)),
      );
    }
    final leader = standings.first.points;
    final anyPoints = standings.any((s) => s.points > 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: PointsEyebrow('Leaderboard')),
        const SizedBox(height: 12),
        if (anyPoints && standings.length >= 3)
          _Podium(top: standings.take(3).toList(), me: me),
        const SizedBox(height: 12),
        for (var i = 0; i < standings.length; i++) ...[
          PointsEntrance(
            delay: Duration(milliseconds: 60 * i),
            child: _LeaderRow(
              standing: standings[i],
              leaderPoints: leader,
              pointValue: season.pointValue,
              isMe: standings[i].participant.employeeId == me,
            ),
          ),
          const SizedBox(height: 8),
        ],
        const Text(
          'Arrows show movement over the last 7 days. Totals never go below 0.',
          textAlign: TextAlign.center,
          style: TextStyle(color: PointsColors.muted, fontSize: 11),
        ),
      ],
    );
  }
}

/// top three on blocks that rise into place: 2nd, 1st, 3rd
class _Podium extends StatelessWidget {
  const _Podium({required this.top, required this.me});

  final List<PointsStanding> top;
  final String? me;

  @override
  Widget build(BuildContext context) {
    final order = [top[1], top[0], top[2]];
    const heights = [78.0, 110.0, 58.0];
    const medals = [Color(0xFFC9D1D9), PointsColors.gold, Color(0xFFD08A4E)];
    return SizedBox(
      height: 250,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: Duration(milliseconds: 900 + 200 * i),
                  curve: Curves.easeOutBack,
                  builder: (context, t, _) {
                    final standing = order[i];
                    final isMe = standing.participant.employeeId == me;
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (i == 1)
                          Transform.scale(
                            scale: t,
                            child: const Icon(Icons.emoji_events,
                                color: PointsColors.gold, size: 30),
                          ),
                        Opacity(
                          opacity: t.clamp(0.0, 1.0),
                          child: PointsAvatar(
                            participant: standing.participant,
                            size: i == 1 ? 58 : 46,
                            ring: isMe ? PointsColors.lime : medals[i],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isMe ? 'YOU' : standing.participant.firstName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color:
                                  isMe ? PointsColors.lime : PointsColors.text,
                              fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: heights[i] * t.clamp(0.0, 1.0),
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(12)),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                medals[i].withValues(alpha: 0.55),
                                medals[i].withValues(alpha: 0.12),
                              ],
                            ),
                            border: Border.all(
                                color: medals[i].withValues(alpha: 0.6)),
                          ),
                          alignment: Alignment.topCenter,
                          padding: const EdgeInsets.only(top: 8),
                          child: FittedBox(
                            child: Column(
                              children: [
                                Text('${standing.rank}',
                                    style: pointsDisplay(26)),
                                Text('${standing.points} pts',
                                    style: const TextStyle(
                                        color: PointsColors.text,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({
    required this.standing,
    required this.leaderPoints,
    required this.pointValue,
    required this.isMe,
  });

  final PointsStanding standing;
  final int leaderPoints;
  final double pointValue;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final share = leaderPoints <= 0 ? 0.0 : standing.points / leaderPoints;
    final rankColor = switch (standing.rank) {
      1 => PointsColors.gold,
      2 => const Color(0xFFC9D1D9),
      3 => const Color(0xFFD08A4E),
      _ => PointsColors.muted,
    };
    final dollars = standing.points * pointValue;
    return PointsCard(
      highlighted: isMe,
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 34,
                child: Text('${standing.rank}',
                    textAlign: TextAlign.center,
                    style: pointsDisplay(22, color: rankColor)),
              ),
              const SizedBox(width: 6),
              PointsAvatar(participant: standing.participant, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isMe
                          ? '${standing.participant.name} (you)'
                          : standing.participant.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: isMe ? PointsColors.lime : PointsColors.text,
                          fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${signedPoints(standing.weekPoints)} this week · '
                      '\$${dollars.toStringAsFixed(dollars == dollars.roundToDouble() ? 0 : 2)}',
                      style: const TextStyle(
                          color: PointsColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              _Movement(movement: standing.movement),
              const SizedBox(width: 8),
              AnimatedPointsNumber(
                  value: standing.points.toDouble(), style: pointsDisplay(24)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: share.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 4,
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                color:
                    isMe ? PointsColors.lime : rankColor.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ token + feed

class _TokenCard extends StatelessWidget {
  const _TokenCard({required this.challenge});

  final PointsChallenge? challenge;

  @override
  Widget build(BuildContext context) {
    final challenge = this.challenge;
    final (title, body, color) = switch (challenge?.status) {
      null => (
          'TOKEN READY',
          'Think a point was docked unfairly? Tap "Challenge" on it below. One token for the whole season — spent either way, so save it for a call you\'re sure about.',
          PointsColors.gold,
        ),
      ChallengeStatus.pending => (
          'TOKEN SPENT · UNDER REVIEW',
          'Challenging: ${challenge!.eventSummary}. Ryan will review it.',
          PointsColors.gold,
        ),
      ChallengeStatus.upheld => (
          'CHALLENGE WON',
          '${challenge!.eventSummary} was reversed. The point came back.'
              '${challenge.ownerNote.isEmpty ? '' : ' "${challenge.ownerNote}"'}',
          PointsColors.lime,
        ),
      _ => (
          'CHALLENGE DENIED',
          '${challenge!.eventSummary} stands.'
              '${challenge.ownerNote.isEmpty ? '' : ' "${challenge.ownerNote}"'}',
          PointsColors.red,
        ),
    };
    return PointsCard(
      accent: PointsColors.gold,
      child: Row(
        children: [
          ChallengeCoin(size: 58, spent: challenge != null),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CHALLENGE TOKEN',
                    style: pointsEyebrow(color: PointsColors.gold)),
                const SizedBox(height: 4),
                Text(title, style: pointsDisplay(18, color: color)),
                const SizedBox(height: 4),
                Text(body,
                    style: const TextStyle(
                        color: PointsColors.muted, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MyActivity extends StatelessWidget {
  const _MyActivity({
    required this.season,
    required this.events,
    required this.me,
    required this.myName,
    required this.tokenAvailable,
  });

  final PointsSeason season;
  final List<PointsEvent> events;
  final String me;
  final String myName;
  final bool tokenAvailable;

  static String summaryOf(PointsEvent event) =>
      '${event.categoryInfo.name} (${signedPoints(event.points)}) on '
      '${DateFormat('MMM d').format(event.date)}';

  Future<void> _challenge(BuildContext context, PointsEvent event) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ChallengeDialog(summary: summaryOf(event)),
    );
    if (reason == null || !context.mounted) return;
    try {
      await CrewPointsService.submitChallenge(
        seasonId: season.id,
        employeeId: me,
        employeeName: myName,
        event: event,
        eventSummary: summaryOf(event),
        reason: reason,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Token spent. Ryan will review your challenge.')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not send the challenge: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = events
        .where((e) =>
            e.employeeIds.contains(me) ||
            (e.createdBy == me && e.category == PointsCatalog.teamworkCallout))
        .where(
            (e) => e.status != PointsEventStatus.rejected || e.createdBy == me)
        .toList();
    final byDay = <String, List<PointsEvent>>{};
    for (final event in mine) {
      byDay.putIfAbsent(event.day, () => []).add(event);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: PointsEyebrow('Your points')),
        const SizedBox(height: 10),
        if (mine.isEmpty)
          const PointsCard(
            child: Text('No points yet. Every day is a fresh shot.',
                style: TextStyle(color: PointsColors.muted)),
          ),
        for (final entry in byDay.entries) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 6, bottom: 6),
            child: Text(
              DateFormat('EEEE, MMM d')
                  .format(pointsDayFromKey(entry.key))
                  .toUpperCase(),
              style: pointsEyebrow(color: PointsColors.muted),
            ),
          ),
          for (final event in entry.value) ...[
            _EventTile(
              event: event,
              isMine: event.employeeIds.contains(me),
              onChallenge: tokenAvailable &&
                      event.counts &&
                      event.points < 0 &&
                      event.employeeIds.contains(me)
                  ? () => _challenge(context, event)
                  : null,
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile(
      {required this.event, required this.isMine, this.onChallenge});

  final PointsEvent event;

  /// false for a call-out this employee sent to another crew
  final bool isMine;
  final VoidCallback? onChallenge;

  @override
  Widget build(BuildContext context) {
    final info = event.categoryInfo;
    final color = PointsColors.forGroup(info.group, points: event.points);
    final status = switch (event.status) {
      PointsEventStatus.pending =>
        isMine ? 'Waiting for Ryan' : 'You sent this · waiting for Ryan',
      PointsEventStatus.rejected => 'Not approved',
      PointsEventStatus.reversed =>
        'Reversed${event.reviewNote.isEmpty ? '' : ' · ${event.reviewNote}'}',
      _ => isMine ? null : 'You sent this',
    };
    return PointsCard(
      accent: event.counts ? color : PointsColors.muted,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(info.name.toUpperCase(),
                    style: pointsDisplay(15,
                        color: event.counts
                            ? PointsColors.text
                            : PointsColors.muted)),
                const SizedBox(height: 3),
                Text(
                  [
                    if (event.crewName.isNotEmpty) event.crewName,
                    if (event.note.isNotEmpty) event.note,
                    if (event.category == PointsCatalog.teamworkCallout &&
                        event.createdByName.isNotEmpty)
                      'from ${event.createdByName}',
                  ].join(' · '),
                  style:
                      const TextStyle(color: PointsColors.muted, fontSize: 12),
                ),
                if (status != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(status,
                        style: const TextStyle(
                            color: PointsColors.gold,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                if (onChallenge != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onChallenge,
                      style: TextButton.styleFrom(
                        foregroundColor: PointsColors.gold,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.toll_outlined, size: 18),
                      label: const Text('Challenge'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          PointsPill(
              label: signedPoints(event.points),
              color: color,
              struck: !event.counts),
        ],
      ),
    );
  }
}

class _ChallengeDialog extends StatefulWidget {
  const _ChallengeDialog({required this.summary});

  final String summary;

  @override
  State<_ChallengeDialog> createState() => _ChallengeDialogState();
}

class _ChallengeDialogState extends State<_ChallengeDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Spend your challenge token?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Challenging: ${widget.summary}'),
          const SizedBox(height: 8),
          const Text(
            "You only get one for the whole season, and it's spent whether or not the challenge succeeds.",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            maxLines: 4,
            decoration: const InputDecoration(
                labelText: 'Why was this unfair?',
                border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Keep my token')),
        FilledButton(
          onPressed: () {
            if (_reason.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Explain your case first.')));
              return;
            }
            Navigator.of(context).pop(_reason.text.trim());
          },
          child: const Text('Spend token'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ how it works

class _HowItWorks extends StatefulWidget {
  const _HowItWorks({required this.pointValue});

  final double pointValue;

  @override
  State<_HowItWorks> createState() => _HowItWorksState();
}

class _HowItWorksState extends State<_HowItWorks> {
  bool _open = false;

  Widget _group(String eyebrow, String title, PointsGroup group, Color color) {
    final categories = PointsCatalog.all.where((c) => c.group == group);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        Center(child: PointsEyebrow(eyebrow, color: color)),
        const SizedBox(height: 4),
        Center(child: Text(title, style: pointsDisplay(24, color: color))),
        const SizedBox(height: 10),
        for (final category in categories) ...[
          PointsCard(
            accent: color,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(category.name.toUpperCase(),
                          style: pointsDisplay(15)),
                      const SizedBox(height: 3),
                      Text(category.description,
                          style: const TextStyle(
                              color: PointsColors.muted, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                PointsPill(
                  label: category.allowedPoints == null
                      ? signedPoints(category.points)
                      : category.allowedPoints!.map(signedPoints).join(' or '),
                  color: color,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: TextButton.icon(
            onPressed: () => setState(() => _open = !_open),
            style: TextButton.styleFrom(foregroundColor: PointsColors.lime),
            icon: Icon(_open ? Icons.expand_less : Icons.menu_book_outlined),
            label: Text(_open ? 'Hide the rules' : 'How it works'),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !_open
              ? const SizedBox(width: double.infinity)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Center(
                        child: Text('NEW TEAMS EVERY DAY.',
                            style: pointsDisplay(22))),
                    const SizedBox(height: 6),
                    const Text(
                      'Your crew earns and loses points together, but the points are yours. '
                      'When teams change, your total comes with you.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: PointsColors.muted),
                    ),
                    _group('How you earn', 'DAILY TEAM POINTS',
                        PointsGroup.daily, PointsColors.lime),
                    _group('The fun ones', 'BONUS POINTS', PointsGroup.bonus,
                        PointsColors.gold),
                    _group('Watch out', 'POINTS YOU CAN LOSE',
                        PointsGroup.penalty, PointsColors.red),
                    PointsCard(
                      child: Column(
                        children: [
                          Text('NEVER LOST FOR', style: pointsEyebrow()),
                          const SizedBox(height: 4),
                          Text('WEATHER DELAYS OR HARDER, SLOWER JOBS',
                              textAlign: TextAlign.center,
                              style: pointsDisplay(16)),
                          const SizedBox(height: 4),
                          const Text(
                              'Never push through unsafe conditions to chase points.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: PointsColors.muted, fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Center(
                        child: Text('DO IT RIGHT.',
                            style:
                                pointsDisplay(28, color: PointsColors.lime))),
                    Center(child: Text('NOT FAST.', style: pointsDisplay(28))),
                    const SizedBox(height: 6),
                    const Text('Rushing a job to save time earns zero points.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: PointsColors.muted)),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: PointsColors.gold),
                      ),
                      child: Column(
                        children: [
                          Text(
                              'YOUR SEASON TOTAL × \$${widget.pointValue.toStringAsFixed(widget.pointValue == widget.pointValue.roundToDouble() ? 0 : 2)}',
                              style: pointsDisplay(18)),
                          const SizedBox(height: 6),
                          Text('= YOUR BONUS',
                              style:
                                  pointsDisplay(26, color: PointsColors.gold)),
                          const SizedBox(height: 8),
                          const Text(
                            'Paid on top of your normal pay once the last week\'s jobs are confirmed. '
                            'You can\'t go below 0 and will never owe money.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: PointsColors.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

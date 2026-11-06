import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/client_profile_service.dart';
import '../../../core/services/crew_points_service.dart';
import '../../../core/services/csv_download_service.dart';
import '../../../core/services/employee_profile_service.dart';
import '../../../models/client_profile.dart';
import '../../../models/crew_points.dart';
import '../../../models/employee_profile.dart';
import '../../../shared/utils/stream_cache.dart';
import '../../../shared/widgets/app_scaffold.dart';
import 'crew_points_page.dart';
import 'crew_points_widgets.dart';

/// the owner's side of the Crew Points Program: score each day's crews,
/// add bonuses and deductions, review call-outs and challenges, see the
/// payout, and set up the season
class CrewPointsAdminPage extends StatefulWidget {
  const CrewPointsAdminPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  @override
  State<CrewPointsAdminPage> createState() => _CrewPointsAdminPageState();
}

class _CrewPointsAdminPageState extends State<CrewPointsAdminPage> {
  final _streams = StreamCache();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PointsSeason>>(
      stream: _streams.get('seasons', null, CrewPointsService.watchSeasons),
      builder: (context, seasonSnapshot) {
        final seasons = seasonSnapshot.data;
        final season =
            seasons == null ? null : CrewPointsService.currentOf(seasons);

        Widget body;
        if (seasonSnapshot.hasError) {
          body = Center(
              child:
                  Text('Could not load Crew Points: ${seasonSnapshot.error}'));
        } else if (seasons == null) {
          body = const Center(child: CircularProgressIndicator());
        } else if (season == null) {
          body = const _SeasonSetup();
        } else {
          body = StreamBuilder<List<PointsEvent>>(
            stream: _streams.get('events', season.id,
                () => CrewPointsService.watchEvents(season.id)),
            builder: (context, eventSnapshot) =>
                StreamBuilder<List<PointsChallenge>>(
              stream: _streams.get('challenges', season.id,
                  () => CrewPointsService.watchChallenges(season.id)),
              builder: (context, challengeSnapshot) => _AdminTabs(
                season: season,
                events: eventSnapshot.data ?? const [],
                challenges: challengeSnapshot.data ?? const [],
              ),
            ),
          );
        }

        return AppScaffold(
          title: 'Crew Points',
          role: widget.role,
          authToken: widget.authToken,
          selectedRoute: AppRouter.crewPoints,
          body: body,
        );
      },
    );
  }
}

class _AdminTabs extends StatelessWidget {
  const _AdminTabs(
      {required this.season, required this.events, required this.challenges});

  final PointsSeason season;
  final List<PointsEvent> events;
  final List<PointsChallenge> challenges;

  @override
  Widget build(BuildContext context) {
    final toReview = events.where((e) => e.isPending).length +
        challenges.where((c) => c.isPending).length;
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: TabBar(
              isScrollable: true,
              tabs: [
                const Tab(text: 'Score a day'),
                Tab(
                  child: Badge(
                    isLabelVisible: toReview > 0,
                    label: Text('$toReview'),
                    child: const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Text('Review'),
                    ),
                  ),
                ),
                const Tab(text: 'Standings & payout'),
                const Tab(text: 'Season'),
                const Tab(text: 'Crew view'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _ScoreDayTab(season: season, events: events),
                _ReviewTab(
                    season: season, events: events, challenges: challenges),
                _StandingsTab(season: season, events: events),
                _SeasonTab(season: season),
                const CrewPointsBoard(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void _snack(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Color _pointsColor(int points) => points > 0
    ? Colors.green.shade700
    : points < 0
        ? Colors.red.shade700
        : Colors.grey.shade700;

// ================================================================ score a day

class _ScoreDayTab extends StatefulWidget {
  const _ScoreDayTab({required this.season, required this.events});

  final PointsSeason season;
  final List<PointsEvent> events;

  @override
  State<_ScoreDayTab> createState() => _ScoreDayTabState();
}

class _ScoreDayTabState extends State<_ScoreDayTab> {
  final _streams = StreamCache();
  late DateTime _day = _initialDay();

  DateTime _initialDay() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final season = widget.season;
    if (today.isBefore(season.startDate)) return season.startDate;
    if (today.isAfter(season.endDate)) return season.endDate;
    return today;
  }

  void _shift(int days) {
    final next = _day.add(Duration(days: days));
    if (!widget.season.containsDay(next)) return;
    setState(() => _day = next);
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: widget.season.startDate,
      lastDate: widget.season.endDate,
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _editCrews(DailyCrews? current) async {
    final dayKey = pointsDayKey(_day);
    var starting = current;
    if (starting == null || starting.crews.isEmpty) {
      final previous = await CrewPointsService.fetchLatestCrewsBefore(
          widget.season.id, dayKey);
      starting = previous == null
          ? null
          : DailyCrews(
              seasonId: widget.season.id, day: dayKey, crews: previous.crews);
    }
    if (!mounted) return;
    final result = await showDialog<List<PointsCrew>>(
      context: context,
      builder: (_) => _CrewEditorDialog(
        season: widget.season,
        day: _day,
        initial: starting?.crews,
        copiedFromEarlierDay: current == null && starting != null,
      ),
    );
    if (result == null) return;
    try {
      await CrewPointsService.saveCrews(
          DailyCrews(seasonId: widget.season.id, day: dayKey, crews: result));
      if (mounted) _snack(context, 'Crews saved.');
    } catch (error) {
      if (mounted) _snack(context, 'Could not save crews: $error');
    }
  }

  Future<void> _addPoints(List<PointsCrew> crews, {PointsCrew? crew}) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _AddPointsDialog(
        season: widget.season,
        day: _day,
        crews: crews,
        events: widget.events,
        initialCrew: crew,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final season = widget.season;
    final dayKey = pointsDayKey(_day);
    return StreamBuilder<DailyCrews?>(
      stream: _streams.get('crews', dayKey,
          () => CrewPointsService.watchCrews(season.id, dayKey)),
      builder: (context, snapshot) {
        final dailyCrews = snapshot.data;
        final crews = dailyCrews?.crews ?? const <PointsCrew>[];
        final dayEvents = widget.events.where((e) => e.day == dayKey).toList();
        final unassigned = dayEvents.where((e) =>
            e.crewId == null || !crews.any((crew) => crew.id == e.crewId));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (season.isFinalized)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('This season is finalized.'),
                  subtitle:
                      Text('Unlock it on the Standings tab to change points.'),
                ),
              ),
            Row(
              children: [
                IconButton(
                  onPressed:
                      season.containsDay(_day.subtract(const Duration(days: 1)))
                          ? () => _shift(-1)
                          : null,
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Previous day',
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: _pickDay,
                    icon: const Icon(Icons.event),
                    label: Text(
                      '${DateFormat('EEEE, MMM d').format(_day)} · week ${season.weekOf(_day)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                IconButton(
                  onPressed:
                      season.containsDay(_day.add(const Duration(days: 1)))
                          ? () => _shift(1)
                          : null,
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Next day',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed:
                      season.isFinalized ? null : () => _editCrews(dailyCrews),
                  icon: const Icon(Icons.groups_outlined),
                  label: Text(
                      crews.isEmpty ? "Set up this day's crews" : 'Edit crews'),
                ),
                FilledButton.icon(
                  onPressed:
                      season.isFinalized ? null : () => _addPoints(crews),
                  icon: const Icon(Icons.add),
                  label: const Text('Add points'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (crews.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    "No crews set for this day yet. Teams are set fresh each day; "
                    "the editor starts from the last day you set up.",
                  ),
                ),
              ),
            for (final crew in crews)
              _CrewScoreCard(
                season: season,
                day: dayKey,
                crew: crew,
                events: dayEvents.where((e) => e.crewId == crew.id).toList(),
                locked: season.isFinalized,
                onAddPoints: () => _addPoints(crews, crew: crew),
              ),
            if (unassigned.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Other points this day',
                  style: Theme.of(context).textTheme.titleSmall),
              for (final event in unassigned)
                _EventListTile(
                    season: season, event: event, locked: season.isFinalized),
            ],
          ],
        );
      },
    );
  }
}

class _CrewScoreCard extends StatelessWidget {
  const _CrewScoreCard({
    required this.season,
    required this.day,
    required this.crew,
    required this.events,
    required this.locked,
    required this.onAddPoints,
  });

  final PointsSeason season;
  final String day;
  final PointsCrew crew;
  final List<PointsEvent> events;
  final bool locked;
  final VoidCallback onAddPoints;

  bool _has(String category) =>
      events.any((e) => e.category == category && e.id == _checkId(category));

  String _checkId(String category) =>
      PointsEvent.dailyCheckId(season.id, day, crew.id, category);

  Future<void> _set(BuildContext context, String category, bool on) async {
    try {
      await CrewPointsService.setDailyCheck(
          seasonId: season.id,
          day: day,
          crew: crew,
          category: category,
          on: on);
    } catch (error) {
      if (context.mounted) _snack(context, 'Could not save: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final counted = events.where((e) => e.counts);
    final total = counted.fold<int>(0, (sum, e) => sum + e.points);
    final arrival = _has(PointsCatalog.onTime)
        ? 'on_time'
        : _has(PointsCatalog.lateArrival)
            ? 'late'
            : 'none';
    final others = events.where((e) =>
        e.id != _checkId(PointsCatalog.onTime) &&
        e.id != _checkId(PointsCatalog.lateArrival) &&
        !PointsCatalog.dailyToggles.any((key) => e.id == _checkId(key)));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(crew.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Text(signedPoints(total),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: _pointsColor(total))),
                const SizedBox(width: 4),
                const Text('today'),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final id in crew.memberIds)
                  if (season.participant(id) case final p?)
                    Chip(
                      avatar: PointsAvatar(participant: p, size: 22),
                      label: Text(p.name),
                      visualDensity: VisualDensity.compact,
                    ),
                if (crew.memberIds.isEmpty) const Text('No one on this crew.'),
              ],
            ),
            const SizedBox(height: 12),
            Text('Arrival', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'on_time', label: Text('On time +1')),
                ButtonSegment(value: 'none', label: Text('Not scored')),
                ButtonSegment(value: 'late', label: Text('Late −1')),
              ],
              selected: {arrival},
              showSelectedIcon: false,
              onSelectionChanged: locked
                  ? null
                  : (selection) {
                      final value = selection.first;
                      if (value == 'on_time') {
                        _set(context, PointsCatalog.onTime, true);
                      } else if (value == 'late') {
                        _set(context, PointsCatalog.lateArrival, true);
                      } else {
                        _set(
                            context,
                            arrival == 'on_time'
                                ? PointsCatalog.onTime
                                : PointsCatalog.lateArrival,
                            false);
                      }
                    },
            ),
            const SizedBox(height: 10),
            Text('End of day', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final key in PointsCatalog.dailyToggles)
                  FilterChip(
                    label: Text('${PointsCatalog.byKey(key).name} +1'),
                    tooltip: PointsCatalog.byKey(key).description,
                    selected: _has(key),
                    onSelected: locked ? null : (on) => _set(context, key, on),
                  ),
              ],
            ),
            if (others.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final event in others)
                _EventListTile(
                    season: season, event: event, locked: locked, dense: true),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: locked ? null : onAddPoints,
                icon: const Icon(Icons.add),
                label: const Text('Bonus / deduction'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// one event with its reverse / restore / delete actions
class _EventListTile extends StatelessWidget {
  const _EventListTile({
    required this.season,
    required this.event,
    required this.locked,
    this.dense = false,
  });

  final PointsSeason season;
  final PointsEvent event;
  final bool locked;
  final bool dense;

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete these points?'),
        content: const Text(
            'This removes the entry completely. To keep a record, use Reverse instead.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await CrewPointsService.deleteEvent(event.id);
  }

  @override
  Widget build(BuildContext context) {
    final names = event.employeeIds
        .map((id) => season.participant(id)?.firstName ?? '?')
        .join(', ');
    final statusLabel = switch (event.status) {
      PointsEventStatus.pending => ' · pending',
      PointsEventStatus.rejected => ' · rejected',
      PointsEventStatus.reversed => ' · reversed',
      _ => '',
    };
    return ListTile(
      dense: dense,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: _pointsColor(event.counts ? event.points : 0)
            .withValues(alpha: 0.12),
        child: Text(signedPoints(event.points),
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: _pointsColor(event.counts ? event.points : 0),
                decoration: event.counts ? null : TextDecoration.lineThrough)),
      ),
      title: Text('${event.categoryInfo.name}$statusLabel'),
      subtitle: Text([
        if (event.crewName.isNotEmpty) event.crewName,
        names,
        if (event.note.isNotEmpty) event.note,
        if (event.createdBy != 'owner') 'from ${event.createdByName}',
      ].join(' · ')),
      trailing: locked
          ? null
          : PopupMenuButton<String>(
              onSelected: (action) async {
                try {
                  switch (action) {
                    case 'reverse':
                      await CrewPointsService.setEventStatus(
                          event.id, PointsEventStatus.reversed,
                          note: 'Reversed by owner');
                    case 'restore':
                      await CrewPointsService.setEventStatus(
                          event.id, PointsEventStatus.approved);
                    case 'delete':
                      if (context.mounted) await _confirmDelete(context);
                  }
                } catch (error) {
                  if (context.mounted) {
                    _snack(context, 'Could not update: $error');
                  }
                }
              },
              itemBuilder: (_) => [
                if (event.counts)
                  const PopupMenuItem(value: 'reverse', child: Text('Reverse')),
                if (!event.counts)
                  const PopupMenuItem(
                      value: 'restore', child: Text('Count it (approve)')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
    );
  }
}

/// set up which participants are on which crew for one day
class _CrewEditorDialog extends StatefulWidget {
  const _CrewEditorDialog({
    required this.season,
    required this.day,
    required this.initial,
    required this.copiedFromEarlierDay,
  });

  final PointsSeason season;
  final DateTime day;
  final List<PointsCrew>? initial;
  final bool copiedFromEarlierDay;

  @override
  State<_CrewEditorDialog> createState() => _CrewEditorDialogState();
}

class _CrewEditorDialogState extends State<_CrewEditorDialog> {
  late final List<(String, TextEditingController)> _crews;

  /// employeeId → crew id, or null for "off today"
  late final Map<String, String?> _assignment;
  var _nextId = 0;

  String _newCrewId() =>
      'crew_${DateTime.now().millisecondsSinceEpoch}_${_nextId++}';

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null && initial.isNotEmpty) {
      _crews = [
        for (final crew in initial)
          (crew.id, TextEditingController(text: crew.name))
      ];
    } else {
      _crews = [
        for (var i = 1; i <= 2; i++)
          (_newCrewId(), TextEditingController(text: 'Team $i')),
      ];
    }
    _assignment = {
      for (final p in widget.season.participants)
        p.employeeId: initial
            ?.where((crew) => crew.memberIds.contains(p.employeeId))
            .firstOrNull
            ?.id,
    };
  }

  @override
  void dispose() {
    for (final crew in _crews) {
      crew.$2.dispose();
    }
    super.dispose();
  }

  void _addCrew() {
    setState(() => _crews.add((
          _newCrewId(),
          TextEditingController(text: 'Team ${_crews.length + 1}')
        )));
  }

  void _removeCrew(int index) {
    final (id, controller) = _crews[index];
    setState(() {
      _crews.removeAt(index);
      _assignment.updateAll((_, crewId) => crewId == id ? null : crewId);
    });
    controller.dispose();
  }

  void _save() {
    final result = <PointsCrew>[];
    for (final (id, controller) in _crews) {
      final name = controller.text.trim();
      if (name.isEmpty) {
        _snack(context, 'Every crew needs a name.');
        return;
      }
      result.add(PointsCrew(
        id: id,
        name: name,
        memberIds: [
          for (final p in widget.season.participants)
            if (_assignment[p.employeeId] == id) p.employeeId,
        ],
      ));
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Crews for ${DateFormat('EEE, MMM d').format(widget.day)}'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.copiedFromEarlierDay)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                      'Starting from the last day you set up. Change anything that\'s different today.'),
                ),
              Text('Crews', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              for (var i = 0; i < _crews.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _crews[i].$2,
                          decoration: const InputDecoration(
                              labelText: 'Crew name',
                              border: OutlineInputBorder(),
                              isDense: true),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      IconButton(
                        onPressed:
                            _crews.length > 1 ? () => _removeCrew(i) : null,
                        icon: const Icon(Icons.remove_circle_outline),
                        tooltip: 'Remove crew',
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                    onPressed: _addCrew,
                    icon: const Icon(Icons.add),
                    label: const Text('Add crew')),
              ),
              const Divider(),
              Text('Who is on which crew',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              if (widget.season.participants.isEmpty)
                const Text(
                    'No one is on the roster. Add people on the Season tab.'),
              for (final p in widget.season.participants)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      PointsAvatar(participant: p, size: 28),
                      const SizedBox(width: 10),
                      Expanded(child: Text(p.name)),
                      DropdownButton<String?>(
                        value:
                            _crews.any((c) => c.$1 == _assignment[p.employeeId])
                                ? _assignment[p.employeeId]
                                : null,
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('Off today')),
                          for (final (id, controller) in _crews)
                            DropdownMenuItem(
                              value: id,
                              child: Text(controller.text.trim().isEmpty
                                  ? '(unnamed)'
                                  : controller.text.trim()),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _assignment[p.employeeId] = value),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save crews')),
      ],
    );
  }
}

/// any award or deduction beyond the daily checks
class _AddPointsDialog extends StatefulWidget {
  const _AddPointsDialog({
    required this.season,
    required this.day,
    required this.crews,
    required this.events,
    this.initialCrew,
  });

  final PointsSeason season;
  final DateTime day;
  final List<PointsCrew> crews;
  final List<PointsEvent> events;
  final PointsCrew? initialCrew;

  @override
  State<_AddPointsDialog> createState() => _AddPointsDialogState();
}

class _AddPointsDialogState extends State<_AddPointsDialog> {
  static final _categories = PointsCatalog.all
      .where((c) =>
          c.key != PointsCatalog.onTime &&
          c.key != PointsCatalog.lateArrival &&
          !PointsCatalog.dailyToggles.contains(c.key))
      .toList();

  late PointsCategory _category = _categories.first;
  late int _points = _category.points;
  late String? _crewId = widget.initialCrew?.id ?? widget.crews.firstOrNull?.id;
  final Set<String> _people = {};
  final _note = TextEditingController();
  final _adjustment = TextEditingController();
  late final Future<List<ClientProfile>> _clients =
      ClientProfileService.watchAllProfiles().first;
  ClientProfile? _client;
  bool _saving = false;

  /// recipients: a crew, or hand-picked people (crewId null)
  bool get _byCrew => _crewId != null;

  @override
  void dispose() {
    _note.dispose();
    _adjustment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final crew = widget.crews.where((c) => c.id == _crewId).firstOrNull;
    final employeeIds =
        _byCrew ? (crew?.memberIds ?? const <String>[]) : _people.toList();
    if (employeeIds.isEmpty) {
      _snack(context, 'Pick who gets these points.');
      return;
    }
    var points = _points;
    if (_category.key == PointsCatalog.adjustment) {
      final parsed = int.tryParse(_adjustment.text.trim().replaceAll('+', ''));
      if (parsed == null || parsed == 0) {
        _snack(context, 'Enter a whole number like 2 or -1.');
        return;
      }
      if (_note.text.trim().isEmpty) {
        _snack(context, 'Add a note saying what the adjustment is for.');
        return;
      }
      points = parsed;
    }
    if (_category.key == PointsCatalog.googleReview) {
      final client = _client;
      if (client == null) {
        _snack(context, 'Pick the client who left the review.');
        return;
      }
      final already = widget.events.any((e) =>
          e.category == PointsCatalog.googleReview &&
          e.counts &&
          e.clientId == client.signupId);
      if (already) {
        _snack(context,
            '${client.fullName} already earned a review point this season (capped at one per client).');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      await CrewPointsService.addEvent(
        seasonId: widget.season.id,
        day: pointsDayKey(widget.day),
        category: _category.key,
        points: points,
        employeeIds: employeeIds,
        crewId: _byCrew ? crew?.id : null,
        crewName: _byCrew ? crew?.name ?? '' : '',
        note: [
          if (_client != null && _category.key == PointsCatalog.googleReview)
            _client!.fullName,
          _note.text.trim(),
        ].where((s) => s.isNotEmpty).join(' · '),
        clientId: _category.key == PointsCatalog.googleReview
            ? _client?.signupId
            : null,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _snack(context, 'Could not save: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add points · ${DateFormat('MMM d').format(widget.day)}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<PointsCategory>(
                initialValue: _category,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'What for', border: OutlineInputBorder()),
                items: [
                  for (final c in _categories)
                    DropdownMenuItem(
                      value: c,
                      child: Text(c.key == PointsCatalog.adjustment
                          ? 'Adjustment (any amount)'
                          : '${c.name} (${c.allowedPoints?.map(signedPoints).join('/') ?? signedPoints(c.points)})'),
                    ),
                ],
                onChanged: (c) {
                  if (c == null) return;
                  setState(() {
                    _category = c;
                    _points = c.points;
                  });
                },
              ),
              const SizedBox(height: 6),
              Text(_category.description,
                  style: Theme.of(context).textTheme.bodySmall),
              if (_category.allowedPoints != null) ...[
                const SizedBox(height: 10),
                SegmentedButton<int>(
                  segments: [
                    for (final p in _category.allowedPoints!)
                      ButtonSegment(value: p, label: Text(signedPoints(p))),
                  ],
                  selected: {_points},
                  onSelectionChanged: (s) => setState(() => _points = s.first),
                ),
              ],
              if (_category.key == PointsCatalog.adjustment) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _adjustment,
                  keyboardType:
                      const TextInputType.numberWithOptions(signed: true),
                  decoration: const InputDecoration(
                      labelText: 'Points (e.g. 2 or -1)',
                      border: OutlineInputBorder()),
                ),
              ],
              if (_category.key == PointsCatalog.googleReview) ...[
                const SizedBox(height: 10),
                FutureBuilder<List<ClientProfile>>(
                  future: _clients,
                  builder: (context, snapshot) {
                    final clients = snapshot.data ?? const <ClientProfile>[];
                    return DropdownButtonFormField<ClientProfile>(
                      initialValue: _client,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Client who left the review',
                          border: OutlineInputBorder()),
                      items: [
                        for (final c in clients)
                          DropdownMenuItem(value: c, child: Text(c.fullName)),
                      ],
                      onChanged: (c) => setState(() => _client = c),
                    );
                  },
                ),
              ],
              const SizedBox(height: 14),
              Text('Who gets them',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final crew in widget.crews)
                    ChoiceChip(
                      label: Text('${crew.name} (${crew.memberIds.length})'),
                      selected: _crewId == crew.id,
                      onSelected: (_) => setState(() => _crewId = crew.id),
                    ),
                  ChoiceChip(
                    label: const Text('Specific people'),
                    selected: !_byCrew,
                    onSelected: (_) => setState(() => _crewId = null),
                  ),
                ],
              ),
              if (!_byCrew) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in widget.season.participants)
                      FilterChip(
                        label: Text(p.name),
                        selected: _people.contains(p.employeeId),
                        onSelected: (on) => setState(() => on
                            ? _people.add(p.employeeId)
                            : _people.remove(p.employeeId)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: _note,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: _category.key == PointsCatalog.adjustment
                      ? 'Note (required)'
                      : 'Note (shown to the crew, optional)',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Add'),
        ),
      ],
    );
  }
}

// ==================================================================== review

class _ReviewTab extends StatelessWidget {
  const _ReviewTab(
      {required this.season, required this.events, required this.challenges});

  final PointsSeason season;
  final List<PointsEvent> events;
  final List<PointsChallenge> challenges;

  Future<void> _resolve(
      BuildContext context, PointsChallenge challenge, bool upheld) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(upheld ? 'Uphold the challenge?' : 'Deny the challenge?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(upheld
                ? '${challenge.eventSummary} will be reversed for everyone it applied to.'
                : '${challenge.eventSummary} stands. Their token is still spent.'),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Note to them (optional)',
                  border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(upheld ? 'Uphold' : 'Deny')),
        ],
      ),
    );
    final text = note.text;
    note.dispose();
    if (ok != true) return;
    try {
      await CrewPointsService.resolveChallenge(
          challenge: challenge, upheld: upheld, note: text);
    } catch (error) {
      if (context.mounted) _snack(context, 'Could not save: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingCallouts = events.where((e) => e.isPending).toList();
    final pendingChallenges = challenges.where((c) => c.isPending).toList();
    final resolved = challenges.where((c) => !c.isPending).toList();
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Teamwork call-outs', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
            'Crew members giving +1 to another crew that helped them. They count once you approve.'),
        const SizedBox(height: 8),
        if (pendingCallouts.isEmpty) const Text('Nothing waiting.'),
        for (final event in pendingCallouts)
          Card(
            child: ListTile(
              title: Text('${event.createdByName} → ${event.crewName} (+1)'),
              subtitle: Text(
                  '${DateFormat('EEE, MMM d').format(event.date)} · ${event.note}\n'
                  'Goes to: ${event.employeeIds.map((id) => season.participant(id)?.firstName ?? '?').join(', ')}'),
              isThreeLine: true,
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: 'Reject',
                    icon: const Icon(Icons.close),
                    onPressed: () => CrewPointsService.setEventStatus(
                        event.id, PointsEventStatus.rejected),
                  ),
                  IconButton(
                    tooltip: 'Approve',
                    icon: const Icon(Icons.check, color: Colors.green),
                    onPressed: () => CrewPointsService.setEventStatus(
                        event.id, PointsEventStatus.approved),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 20),
        Text('Challenges', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
            'Someone spent their one challenge token on a docked point.'),
        const SizedBox(height: 8),
        if (pendingChallenges.isEmpty) const Text('Nothing waiting.'),
        for (final challenge in pendingChallenges)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${challenge.employeeName} challenges: ${challenge.eventSummary}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('"${challenge.reason}"'),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                          onPressed: () => _resolve(context, challenge, false),
                          child: const Text('Deny')),
                      const SizedBox(width: 8),
                      FilledButton(
                          onPressed: () => _resolve(context, challenge, true),
                          child: const Text('Uphold & reverse')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (resolved.isNotEmpty) ...[
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Decided (${resolved.length})'),
            children: [
              for (final c in resolved)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${c.employeeName}: ${c.eventSummary}'),
                  subtitle: Text(
                      '${c.status == ChallengeStatus.upheld ? 'Upheld' : 'Denied'}'
                      '${c.ownerNote.isEmpty ? '' : ' · ${c.ownerNote}'}'),
                ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        Text('All activity', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        if (events.isEmpty) const Text('No points yet this season.'),
        for (final event in events.take(150))
          _EventListTile(
              season: season, event: event, locked: season.isFinalized),
      ],
    );
  }
}

// ======================================================== standings & payout

class _StandingsTab extends StatelessWidget {
  const _StandingsTab({required this.season, required this.events});

  final PointsSeason season;
  final List<PointsEvent> events;

  String _money(double value) =>
      NumberFormat.currency(symbol: r'$').format(value);

  Future<void> _export(
      BuildContext context, List<PointsStanding> standings) async {
    final rows = <List<String>>[
      ['Rank', 'Name', 'Points', 'Payout'],
      for (final s in standings)
        [
          '${s.rank}',
          s.participant.name,
          '${s.points}',
          (s.points * season.pointValue).toStringAsFixed(2)
        ],
    ];
    String cell(String v) =>
        v.contains(RegExp('[",\n]')) ? '"${v.replaceAll('"', '""')}"' : v;
    final csv = rows.map((r) => r.map(cell).join(',')).join('\n');
    try {
      await downloadCsvBytes(
          csvText: csv,
          fileName:
              '${season.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}_payout.csv');
    } catch (error) {
      if (context.mounted) _snack(context, 'Could not export: $error');
    }
  }

  Future<void> _toggleFinal(BuildContext context) async {
    final finalize = !season.isFinalized;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(finalize ? 'Finalize the season?' : 'Unlock the season?'),
        content: Text(finalize
            ? 'Locks the totals for payout: no more points can be added, changed, or challenged. '
                'Do this once the last week\'s jobs are confirmed (callbacks can take a few days). '
                'You can unlock it again.'
            : 'Points can be changed again after unlocking.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(finalize ? 'Finalize' : 'Unlock')),
        ],
      ),
    );
    if (ok == true) await CrewPointsService.setFinalized(season.id, finalize);
  }

  @override
  Widget build(BuildContext context) {
    final standings = PointsMath.standings(season, events);
    final totalPayout = standings.fold<double>(
        0, (sum, s) => sum + s.points * season.pointValue);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 32,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total bonus owed', style: theme.textTheme.labelLarge),
                    Text(_money(totalPayout),
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    Text('${_money(season.pointValue)} per point · '
                        '${season.isFinalized ? 'final' : 'running total'}'),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _export(context, standings),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Export CSV'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _toggleFinal(context),
                      icon: Icon(season.isFinalized
                          ? Icons.lock_open
                          : Icons.lock_outline),
                      label: Text(
                          season.isFinalized ? 'Unlock' : 'Finalize totals'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('#')),
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Points'), numeric: true),
                DataColumn(label: Text('This week'), numeric: true),
                DataColumn(label: Text('Payout'), numeric: true),
              ],
              rows: [
                for (final s in standings)
                  DataRow(cells: [
                    DataCell(Text('${s.rank}')),
                    DataCell(Row(children: [
                      PointsAvatar(participant: s.participant, size: 26),
                      const SizedBox(width: 8),
                      Text(s.participant.name),
                    ])),
                    DataCell(Text(
                      s.rawPoints < 0 ? '0 (${s.rawPoints})' : '${s.points}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    )),
                    DataCell(Text(signedPoints(s.weekPoints),
                        style: TextStyle(color: _pointsColor(s.weekPoints)))),
                    DataCell(Text(_money(s.points * season.pointValue))),
                  ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
            'A negative running total shows as 0: per the rules nobody goes below 0 '
            'or owes money. The raw number is in parentheses.'),
      ],
    );
  }
}

// ==================================================================== season

/// shown when no season exists yet: a prefilled Fall 2026 setup
class _SeasonSetup extends StatelessWidget {
  const _SeasonSetup();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Start the Crew Points Program',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        const Text(
            'Set the season dates, what a point is worth, and who is in it. Everything can be changed later.'),
        const SizedBox(height: 16),
        const _SeasonForm(season: null),
      ],
    );
  }
}

class _SeasonTab extends StatelessWidget {
  const _SeasonTab({required this.season});

  final PointsSeason season;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SeasonForm(key: ValueKey(season.id), season: season),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('New season'),
              content: const SizedBox(
                  width: 560,
                  child:
                      SingleChildScrollView(child: _SeasonForm(season: null))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close')),
              ],
            ),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Start a new season'),
        ),
        const SizedBox(height: 6),
        const Text(
            'The page always shows the season running today (or the next one coming up).'),
      ],
    );
  }
}

class _SeasonForm extends StatefulWidget {
  const _SeasonForm({required this.season, super.key});

  /// null creates a new season
  final PointsSeason? season;

  @override
  State<_SeasonForm> createState() => _SeasonFormState();
}

class _SeasonFormState extends State<_SeasonForm> {
  late final _name =
      TextEditingController(text: widget.season?.name ?? 'Fall 2026');
  late final _value = TextEditingController(
      text: (widget.season?.pointValue ?? 1).toStringAsFixed(
          (widget.season?.pointValue ?? 1) ==
                  (widget.season?.pointValue ?? 1).roundToDouble()
              ? 0
              : 2));
  // last week of October through the first week of December 2026
  late DateTime _start = widget.season?.startDate ?? DateTime(2026, 10, 26);
  late DateTime _end = widget.season?.endDate ?? DateTime(2026, 12, 6);
  late final Set<String> _roster =
      widget.season?.participants.map((p) => p.employeeId).toSet() ??
          <String>{};
  late final _rosterStream = EmployeeProfileService.watchAllProfiles();
  bool _rosterSeeded = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() => start ? _start = picked : _end = picked);
  }

  Future<void> _save(List<EmployeeProfile> employees) async {
    final value = double.tryParse(_value.text.trim().replaceAll(r'$', ''));
    if (_name.text.trim().isEmpty || value == null || value < 0) {
      _snack(context, 'Enter a name and a dollar value per point.');
      return;
    }
    if (_end.isBefore(_start)) {
      _snack(context, 'The season has to end after it starts.');
      return;
    }
    final byId = {for (final e in employees) e.employeeId: e};
    final previous = {
      for (final p
          in widget.season?.participants ?? const <PointsParticipant>[])
        p.employeeId: p,
    };
    final participants = [
      for (final id in _roster)
        PointsParticipant(
          employeeId: id,
          name: byId[id]?.fullName ?? previous[id]?.name ?? 'Unknown',
        ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    setState(() => _saving = true);
    try {
      final season = widget.season;
      if (season == null) {
        await CrewPointsService.createSeason(
          name: _name.text,
          startDate: _start,
          endDate: _end,
          pointValue: value,
          participants: participants,
        );
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      } else {
        await CrewPointsService.updateSeason(PointsSeason(
          id: season.id,
          name: _name.text.trim(),
          startDate: _start,
          endDate: _end,
          pointValue: value,
          participants: participants,
          createdAt: season.createdAt,
          finalizedAt: season.finalizedAt,
        ));
        if (mounted) _snack(context, 'Season saved.');
      }
    } catch (error) {
      if (mounted) _snack(context, 'Could not save: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEE, MMM d, yyyy');
    return StreamBuilder<List<EmployeeProfile>>(
      stream: _rosterStream,
      builder: (context, snapshot) {
        final employees = (snapshot.data ?? const <EmployeeProfile>[])
            .where((e) =>
                !e.archived && (e.active || _roster.contains(e.employeeId)))
            .toList();
        // a new season starts with every active employee in it
        if (widget.season == null && !_rosterSeeded && snapshot.hasData) {
          _rosterSeeded = true;
          _roster.addAll(
              employees.where((e) => e.active).map((e) => e.employeeId));
        }
        final missing = widget.season?.participants
                .where(
                    (p) => !employees.any((e) => e.employeeId == p.employeeId))
                .toList() ??
            const <PointsParticipant>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'Season name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pick(true),
                  icon: const Icon(Icons.play_arrow_outlined),
                  label: Text('Starts ${fmt.format(_start)}'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pick(false),
                  icon: const Icon(Icons.flag_outlined),
                  label: Text('Ends ${fmt.format(_end)}'),
                ),
                Text('${(_end.difference(_start).inDays + 1 + 6) ~/ 7} weeks'),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _value,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Bonus per point',
                prefixText: r'$',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text('Roster (${_roster.length})',
                style: Theme.of(context).textTheme.titleSmall),
            const Text(
                'Names are copied onto the leaderboard; saving refreshes them.'),
            const SizedBox(height: 6),
            for (final e in employees)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _roster.contains(e.employeeId),
                onChanged: (on) => setState(() => on == true
                    ? _roster.add(e.employeeId)
                    : _roster.remove(e.employeeId)),
                title: Text(e.fullName),
                subtitle: e.active ? null : const Text('Inactive'),
              ),
            for (final p in missing)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _roster.contains(p.employeeId),
                onChanged: (on) => setState(() => on == true
                    ? _roster.add(p.employeeId)
                    : _roster.remove(p.employeeId)),
                title: Text(p.name),
                subtitle: const Text('No longer an active employee'),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed:
                    _saving ? null : () => _save(snapshot.data ?? const []),
                child: Text(
                    widget.season == null ? 'Start season' : 'Save season'),
              ),
            ),
          ],
        );
      },
    );
  }
}

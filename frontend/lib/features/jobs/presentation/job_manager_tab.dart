import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/client_profile_service.dart';
import '../../../core/services/estimate_service.dart';
import '../../../core/services/scheduled_work_service.dart';
import '../../../core/services/team_service.dart';
import '../../../models/estimate.dart';
import '../../../models/scheduled_work.dart';
import '../../../models/team.dart';
import '../../../shared/widgets/get_directions_button.dart';

/// owner-only visual weekly calendar: long-press-drag a job chip to a
/// different day/hour cell to reschedule it via [ScheduledWorkService.rescheduleWork].
class JobManagerTab extends StatefulWidget {
  const JobManagerTab({super.key});

  @override
  State<JobManagerTab> createState() => _JobManagerTabState();
}

class _JobManagerTabState extends State<JobManagerTab> {
  static const List<int> _hours = [
    6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
  ]; // 6:00 AM - 7:00 PM
  static const double _timeColWidth = 56.0;
  static const double _dayColWidth = 140.0;
  static const double _rowHeight = 64.0;

  late DateTime _weekStart = _mondayOf(DateTime.now());
  String? _selectedTeamId;
  final ScrollController _headerScrollController = ScrollController();
  final ScrollController _bodyScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _bodyScrollController.addListener(() {
      if (_headerScrollController.hasClients) {
        _headerScrollController.jumpTo(_bodyScrollController.offset);
      }
    });
  }

  @override
  void dispose() {
    _headerScrollController.dispose();
    _bodyScrollController.dispose();
    super.dispose();
  }

  static DateTime _mondayOf(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized.subtract(Duration(days: (normalized.weekday - DateTime.monday) % 7));
  }

  void _shiftWeek(int days) {
    setState(() => _weekStart = _weekStart.add(Duration(days: days)));
  }

  Future<void> _rescheduleJob(ScheduledWork job, DateTime day, int hour) async {
    final newDate = DateTime(day.year, day.month, day.day, hour);
    try {
      await ScheduledWorkService.rescheduleWork(workId: job.id, newDate: newDate);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reschedule: $error')),
        );
      }
    }
  }

  /// schedule an approved-but-unscheduled estimate dropped onto a calendar
  /// cell — same underlying calls as the Estimates tab's "Schedule Work"
  /// button for a single, non-recurring occurrence with no checklist
  /// template (drag-and-drop is a fast single-drop action; a checklist can
  /// still be attached afterward from the job detail page).
  Future<void> _scheduleEstimateAt(Estimate estimate, DateTime day, int hour) async {
    final scheduledDateTime = DateTime(day.year, day.month, day.day, hour);
    try {
      final client = await ClientProfileService.fetchBySignupId(estimate.clientId);
      final workId = await ScheduledWorkService.createScheduledWork(
        estimateId: estimate.id,
        estimateNumber: estimate.estimateNumber,
        clientId: estimate.clientId,
        services: estimate.services,
        total: estimate.total,
        scheduledDate: scheduledDateTime,
        address: client?.address ?? '',
        phoneNumber: client?.phoneNumber ?? '',
      );
      await EstimateService.markScheduled(estimateId: estimate.id, scheduledWorkId: workId);
      if (mounted) {
        final formatted = DateFormat('MMM d, h:mm a').format(scheduledDateTime);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${estimate.estimateNumber} scheduled for $formatted.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to schedule: $error')),
        );
      }
    }
  }

  void _showJobDetails(ScheduledWork job) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => _JobDetailsSheet(job: job),
    );
  }

  @override
  Widget build(BuildContext context) {
    final weekEnd = _weekStart.add(const Duration(days: 7));

    return StreamBuilder<List<Team>>(
      stream: TeamService.watchAllTeams(),
      builder: (context, teamsSnapshot) {
        final teams = teamsSnapshot.data ?? const <Team>[];

        return StreamBuilder<List<ScheduledWork>>(
          stream: ScheduledWorkService.watchJobsForRange(start: _weekStart, end: weekEnd, role: 'owner'),
          builder: (context, jobsSnapshot) {
            if (!jobsSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            var jobs = jobsSnapshot.data!;
            if (_selectedTeamId != null) {
              jobs = jobs.where((job) => (job.teamId ?? '') == _selectedTeamId).toList();
            }

            final bucketed = <int, Map<int, List<ScheduledWork>>>{
              for (var d = 0; d < 7; d++) d: <int, List<ScheduledWork>>{},
            };
            final outsideHours = <int, List<ScheduledWork>>{for (var d = 0; d < 7; d++) d: <ScheduledWork>[]};

            for (final job in jobs) {
              final jobDay = DateTime(job.scheduledDate.year, job.scheduledDate.month, job.scheduledDate.day);
              final dayIndex = jobDay.difference(_weekStart).inDays;
              if (dayIndex < 0 || dayIndex > 6) continue;
              final hour = job.scheduledDate.hour;
              if (hour >= _hours.first && hour <= _hours.last) {
                bucketed[dayIndex]!.putIfAbsent(hour, () => <ScheduledWork>[]).add(job);
              } else {
                outsideHours[dayIndex]!.add(job);
              }
            }

            return Column(
              children: [
                _WeekNavHeader(
                  weekStart: _weekStart,
                  onPrevious: () => _shiftWeek(-7),
                  onNext: () => _shiftWeek(7),
                ),
                const _NeedsSchedulingPanel(),
                if (teams.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: DropdownButton<String?>(
                        value: _selectedTeamId,
                        hint: const Text('All Teams'),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('All Teams')),
                          for (final team in teams)
                            DropdownMenuItem<String?>(value: team.id, child: Text(team.name)),
                        ],
                        onChanged: (value) => setState(() => _selectedTeamId = value),
                      ),
                    ),
                  ),
                Row(
                  children: [
                    const SizedBox(width: _timeColWidth),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _headerScrollController,
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        child: Row(
                          children: [
                            for (var d = 0; d < 7; d++)
                              _DayHeaderCell(day: _weekStart.add(Duration(days: d)), width: _dayColWidth),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TimeLabelColumn(width: _timeColWidth, hours: _hours, rowHeight: _rowHeight),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _bodyScrollController,
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (var d = 0; d < 7; d++)
                                  _DayColumn(
                                    hours: _hours,
                                    rowHeight: _rowHeight,
                                    width: _dayColWidth,
                                    jobsByHour: bucketed[d]!,
                                    outsideHoursJobs: outsideHours[d]!,
                                    onDrop: (data, hour) {
                                      final day = _weekStart.add(Duration(days: d));
                                      if (data is ScheduledWork) {
                                        _rescheduleJob(data, day, hour);
                                      } else if (data is Estimate) {
                                        _scheduleEstimateAt(data, day, hour);
                                      }
                                    },
                                    onTapJob: _showJobDetails,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _WeekNavHeader extends StatelessWidget {
  const _WeekNavHeader({required this.weekStart, required this.onPrevious, required this.onNext});

  final DateTime weekStart;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final weekEnd = weekStart.add(const Duration(days: 6));
    final label = '${DateFormat('MMM d').format(weekStart)} – ${DateFormat('MMM d').format(weekEnd)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(onPressed: onPrevious, icon: const Icon(Icons.chevron_left)),
          Text(label, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
        ],
      ),
    );
  }
}

class _DayHeaderCell extends StatelessWidget {
  const _DayHeaderCell({required this.day, required this.width});

  final DateTime day;
  final double width;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday = now.year == day.year && now.month == day.month && now.day == day.day;
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Text(DateFormat('EEE').format(day), style: Theme.of(context).textTheme.bodySmall),
            Text(
              DateFormat('MMM d').format(day),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isToday ? Theme.of(context).colorScheme.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeLabelColumn extends StatelessWidget {
  const _TimeLabelColumn({required this.width, required this.hours, required this.rowHeight});

  final double width;
  final List<int> hours;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        children: [
          for (final hour in hours)
            SizedBox(
              height: rowHeight,
              child: Padding(
                padding: const EdgeInsets.only(top: 2, right: 4),
                child: Text(
                  DateFormat('h a').format(DateTime(2000, 1, 1, hour)),
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.hours,
    required this.rowHeight,
    required this.width,
    required this.jobsByHour,
    required this.outsideHoursJobs,
    required this.onDrop,
    required this.onTapJob,
  });

  final List<int> hours;
  final double rowHeight;
  final double width;
  final Map<int, List<ScheduledWork>> jobsByHour;
  final List<ScheduledWork> outsideHoursJobs;
  final void Function(Object data, int hour) onDrop;
  final ValueChanged<ScheduledWork> onTapJob;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final hour in hours)
            _HourCell(
              height: rowHeight,
              jobs: jobsByHour[hour] ?? const <ScheduledWork>[],
              onAccept: (data) => onDrop(data, hour),
              onTapJob: onTapJob,
            ),
          if (outsideHoursJobs.isNotEmpty) _OutsideHoursRow(jobs: outsideHoursJobs, onTapJob: onTapJob),
        ],
      ),
    );
  }
}

class _HourCell extends StatelessWidget {
  const _HourCell({required this.height, required this.jobs, required this.onAccept, required this.onTapJob});

  final double height;
  final List<ScheduledWork> jobs;
  final ValueChanged<Object> onAccept;
  final ValueChanged<ScheduledWork> onTapJob;

  @override
  Widget build(BuildContext context) {
    return DragTarget<Object>(
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidateData, rejectedData) {
        // Every cell stays exactly `height` tall so the grid lines up with the
        // time-label column regardless of job density; anything past the
        // first two collapses into a "+N more" tap target.
        const maxVisible = 2;
        final visible = jobs.take(maxVisible).toList();
        final overflowCount = jobs.length - visible.length;

        return Container(
          height: height,
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
            color: candidateData.isNotEmpty
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
                : null,
          ),
          padding: const EdgeInsets.all(2),
          child: ClipRect(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final job in visible) _JobChip(job: job, onTap: () => onTapJob(job)),
                if (overflowCount > 0)
                  GestureDetector(
                    onTap: () => onTapJob(jobs[maxVisible]),
                    child: Text(
                      '+$overflowCount more',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OutsideHoursRow extends StatefulWidget {
  const _OutsideHoursRow({required this.jobs, required this.onTapJob});

  final List<ScheduledWork> jobs;
  final ValueChanged<ScheduledWork> onTapJob;

  @override
  State<_OutsideHoursRow> createState() => _OutsideHoursRowState();
}

class _OutsideHoursRowState extends State<_OutsideHoursRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
              'Outside business hours (${widget.jobs.length})',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
            ),
          ),
        ),
        if (_expanded)
          for (final job in widget.jobs) _JobChip(job: job, onTap: () => widget.onTapJob(job)),
      ],
    );
  }
}

class _JobChip extends StatelessWidget {
  const _JobChip({required this.job, required this.onTap});

  final ScheduledWork job;
  final VoidCallback onTap;

  Color _statusColor(BuildContext context) => switch (job.status) {
        ScheduledWorkStatus.completed => Colors.blue,
        ScheduledWorkStatus.invoiced => Colors.green,
        _ => Theme.of(context).colorScheme.primary,
      };

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(context);
    final chip = Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.15),
        border: Border(left: BorderSide(color: statusColor, width: 3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            DateFormat('h:mm a').format(job.scheduledDate),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor),
          ),
          Text(
            job.address.isEmpty ? 'No address' : job.address,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );

    return LongPressDraggable<ScheduledWork>(
      data: job,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(width: 130, child: chip),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: chip),
      child: GestureDetector(onTap: onTap, child: chip),
    );
  }
}

/// horizontally-scrollable strip of approved-but-unscheduled estimates that
/// can be long-press-dragged onto a calendar cell to schedule them (see
/// _JobManagerTabState._scheduleEstimateAt). Hidden entirely when empty.
class _NeedsSchedulingPanel extends StatelessWidget {
  const _NeedsSchedulingPanel();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Estimate>>(
      stream: EstimateService.watchEstimates(role: 'owner'),
      builder: (context, snapshot) {
        final needsScheduling = (snapshot.data ?? const <Estimate>[])
            .where((estimate) => estimate.isApproved && !estimate.isScheduled)
            .toList();
        if (needsScheduling.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Needs Scheduling — drag onto the calendar',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final estimate in needsScheduling)
                      _NeedsSchedulingChip(estimate: estimate),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NeedsSchedulingChip extends StatelessWidget {
  const _NeedsSchedulingChip({required this.estimate});

  final Estimate estimate;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            estimate.estimateNumber,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          Text(
            '\$${estimate.total.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );

    return LongPressDraggable<Estimate>(
      data: estimate,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(width: 130, child: chip),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: chip),
      child: chip,
    );
  }
}

class _JobDetailsSheet extends StatelessWidget {
  const _JobDetailsSheet({required this.job});

  final ScheduledWork job;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (job.status) {
      ScheduledWorkStatus.completed => Colors.blue,
      ScheduledWorkStatus.invoiced => Colors.green,
      _ => Theme.of(context).colorScheme.primary,
    };
    final statusText = switch (job.status) {
      ScheduledWorkStatus.completed => 'Completed',
      ScheduledWorkStatus.invoiced => 'Invoiced',
      _ => 'Scheduled',
    };

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  job.estimateNumber,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(DateFormat('MMM d, yyyy · h:mm a').format(job.scheduledDate)),
          const SizedBox(height: 12),
          if (job.address.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 16),
                const SizedBox(width: 6),
                Expanded(child: Text(job.address)),
              ],
            ),
            const SizedBox(height: 8),
            GetDirectionsButton(address: job.address),
            const SizedBox(height: 12),
          ],
          if (job.phoneNumber.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.phone_outlined, size: 16),
                const SizedBox(width: 6),
                Text(job.phoneNumber),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Text('Services', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          for (final item in job.services)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(child: Text(item.name)),
                  Text('\$${item.price.toStringAsFixed(2)}'),
                ],
              ),
            ),
          const Divider(height: 20),
          Row(
            children: [
              const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w700))),
              Text('\$${job.total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

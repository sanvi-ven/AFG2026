import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/employee_availability_service.dart';
import '../../../models/employee_availability.dart';

enum _DayAction { markAllDay, setTimeRange, remove }

class _TimeRangeResult {
  const _TimeRangeResult({this.startTime, this.endTime});

  final DateTime? startTime;
  final DateTime? endTime;
}

/// month-grid calendar for an employee to mark the days they can work.
/// tapping an unmarked day marks it available all day; tapping an already
/// marked day opens options to switch to a start/end time window or remove it.
class EmployeeAvailabilityCalendar extends StatefulWidget {
  const EmployeeAvailabilityCalendar({required this.employeeId, super.key});

  final String employeeId;

  @override
  State<EmployeeAvailabilityCalendar> createState() => _EmployeeAvailabilityCalendarState();
}

class _EmployeeAvailabilityCalendarState extends State<EmployeeAvailabilityCalendar> {
  late DateTime _visibleMonth;
  late DateTime _todayMidnight;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _todayMidnight = DateTime(now.year, now.month, now.day);
    _visibleMonth = DateTime(now.year, now.month, 1);
  }

  bool get _isCurrentMonth =>
      _visibleMonth.year == _todayMidnight.year && _visibleMonth.month == _todayMidnight.month;

  void _shiftMonth(int deltaMonths) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + deltaMonths, 1);
    });
  }

  Future<void> _markAllDay(DateTime day) async {
    try {
      await EmployeeAvailabilityService.setAvailability(employeeId: widget.employeeId, date: day);
    } catch (error) {
      _snack('Failed to mark day: $error');
    }
  }

  Future<void> _openOptions(DateTime day, EmployeeAvailability existing) async {
    final action = await showModalBottomSheet<_DayAction>(
      context: context,
      builder: (_) => _DayOptionsSheet(availability: existing),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case _DayAction.markAllDay:
        await _markAllDay(day);
        break;
      case _DayAction.setTimeRange:
        final result = await showDialog<_TimeRangeResult>(
          context: context,
          builder: (_) => _TimeRangeDialog(day: day, existing: existing),
        );
        if (result == null) return;
        try {
          await EmployeeAvailabilityService.setAvailability(
            employeeId: widget.employeeId,
            date: day,
            startTime: result.startTime,
            endTime: result.endTime,
          );
        } catch (error) {
          _snack('Failed to update day: $error');
        }
        break;
      case _DayAction.remove:
        try {
          await EmployeeAvailabilityService.clearAvailability(employeeId: widget.employeeId, date: day);
        } catch (error) {
          _snack('Failed to remove day: $error');
        }
        break;
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<EmployeeAvailability>>(
      stream: EmployeeAvailabilityService.watchForEmployee(widget.employeeId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Failed to load availability: ${snapshot.error}'));
        }

        final byDate = <String, EmployeeAvailability>{
          for (final item in snapshot.data ?? const <EmployeeAvailability>[]) item.date: item,
        };

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildMonthControls(context),
            const SizedBox(height: 8),
            _buildWeekdayHeader(context),
            const SizedBox(height: 4),
            _buildGrid(context, byDate),
            const SizedBox(height: 16),
            _buildLegend(context),
          ],
        );
      },
    );
  }

  Widget _buildMonthControls(BuildContext context) {
    final label = DateFormat('MMMM yyyy').format(_visibleMonth);
    return Row(
      children: [
        IconButton(
          onPressed: _isCurrentMonth ? null : () => _shiftMonth(-1),
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous month',
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          onPressed: () => _shiftMonth(1),
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next month',
        ),
      ],
    );
  }

  Widget _buildWeekdayHeader(BuildContext context) {
    const labels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    return Row(
      children: [
        for (final label in labels)
          Expanded(
            child: Center(child: Text(label, style: Theme.of(context).textTheme.labelMedium)),
          ),
      ],
    );
  }

  Widget _buildGrid(BuildContext context, Map<String, EmployeeAvailability> byDate) {
    final firstOfMonth = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    // .weekday is 1=Mon..7=Sun; %7 turns Sunday into 0 leading blanks for a Sun-first grid.
    final leadingBlanks = firstOfMonth.weekday % 7;
    final dateFormat = DateFormat('yyyy-MM-dd');

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
        for (var day = 1; day <= daysInMonth; day++) _buildDayCell(day, dateFormat, byDate),
      ],
    );
  }

  Widget _buildDayCell(int day, DateFormat dateFormat, Map<String, EmployeeAvailability> byDate) {
    final cellDate = DateTime(_visibleMonth.year, _visibleMonth.month, day);
    final isPast = cellDate.isBefore(_todayMidnight);
    final availability = byDate[dateFormat.format(cellDate)];

    VoidCallback? onTap;
    if (!isPast) {
      onTap = availability == null
          ? () => _markAllDay(cellDate)
          : () => _openOptions(cellDate, availability);
    }

    return _DayCell(
      day: day,
      isPast: isPast,
      isToday: cellDate == _todayMidnight,
      availability: availability,
      onTap: onTap,
    );
  }

  Widget _buildLegend(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: const [
        _LegendItem(color: Colors.green, label: 'Available all day'),
        _LegendItem(color: Colors.blue, label: 'Available (time set)'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.6), shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isPast,
    required this.isToday,
    required this.availability,
    required this.onTap,
  });

  final int day;
  final bool isPast;
  final bool isToday;
  final EmployeeAvailability? availability;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color? background;
    Color? foreground;
    IconData? icon;

    if (isPast) {
      foreground = theme.disabledColor;
    } else if (availability != null) {
      if (availability!.isAllDay) {
        background = Colors.green.withValues(alpha: 0.15);
        foreground = Colors.green.shade800;
        icon = Icons.check_circle;
      } else {
        background = Colors.blue.withValues(alpha: 0.15);
        foreground = Colors.blue.shade800;
        icon = Icons.access_time_filled;
      }
    }

    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: background ?? Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: isToday
                ? BoxDecoration(
                    border: Border.all(color: theme.colorScheme.primary, width: 1.5),
                    borderRadius: BorderRadius.circular(8),
                  )
                : null,
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$day',
                  style: TextStyle(color: foreground, fontWeight: isToday ? FontWeight.w700 : FontWeight.w500),
                ),
                if (icon != null) Icon(icon, size: 14, color: foreground),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DayOptionsSheet extends StatelessWidget {
  const _DayOptionsSheet({required this.availability});

  final EmployeeAvailability availability;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.event_available),
            title: const Text('Mark all day'),
            enabled: !availability.isAllDay,
            onTap: () => Navigator.of(context).pop(_DayAction.markAllDay),
          ),
          ListTile(
            leading: const Icon(Icons.access_time),
            title: const Text('Set start / end time'),
            onTap: () => Navigator.of(context).pop(_DayAction.setTimeRange),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Remove availability', style: TextStyle(color: Colors.red)),
            onTap: () => Navigator.of(context).pop(_DayAction.remove),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _TimeRangeDialog extends StatefulWidget {
  const _TimeRangeDialog({required this.day, required this.existing});

  final DateTime day;
  final EmployeeAvailability existing;

  @override
  State<_TimeRangeDialog> createState() => _TimeRangeDialogState();
}

class _TimeRangeDialogState extends State<_TimeRangeDialog> {
  late TimeOfDay? _startTime =
      widget.existing.startTime == null ? null : TimeOfDay.fromDateTime(widget.existing.startTime!);
  late TimeOfDay? _endTime =
      widget.existing.endTime == null ? null : TimeOfDay.fromDateTime(widget.existing.endTime!);

  DateTime? _combine(TimeOfDay? time) {
    if (time == null) return null;
    return DateTime(widget.day.year, widget.day.month, widget.day.day, time.hour, time.minute);
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial = (isStart ? _startTime : _endTime) ?? TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  void _save() {
    final start = _combine(_startTime);
    final end = _combine(_endTime);
    if (start != null && end != null && !end.isAfter(start)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('End time must be after start time.')));
      return;
    }
    Navigator.of(context).pop(_TimeRangeResult(startTime: start, endTime: end));
  }

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('h:mm a');
    return AlertDialog(
      title: Text('Availability — ${DateFormat('MMM d, yyyy').format(widget.day)}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Start time'),
            subtitle: Text(_startTime == null ? 'Not set' : timeFormat.format(_combine(_startTime)!)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(onPressed: () => _pickTime(isStart: true), child: const Text('Edit')),
                if (_startTime != null)
                  IconButton(
                    onPressed: () => setState(() => _startTime = null),
                    icon: const Icon(Icons.clear, size: 18),
                    tooltip: 'Clear start time',
                  ),
              ],
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('End time'),
            subtitle: Text(_endTime == null ? 'Not set' : timeFormat.format(_combine(_endTime)!)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(onPressed: () => _pickTime(isStart: false), child: const Text('Edit')),
                if (_endTime != null)
                  IconButton(
                    onPressed: () => setState(() => _endTime = null),
                    icon: const Icon(Icons.clear, size: 18),
                    tooltip: 'Clear end time',
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

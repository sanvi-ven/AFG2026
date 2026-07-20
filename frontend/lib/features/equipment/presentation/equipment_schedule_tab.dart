import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/equipment_reservation_service.dart';
import '../../../models/equipment_reservation.dart';

/// owner-only schedule view: a day-grouped list of active reservations for a
/// selected day, with prev/next-day controls and a "Today" reset. Reservations
/// are streamed cross-equipment and filtered client-side to the selected day,
/// then grouped by equipment name. Each row shows the checkout/return status and
/// an owner cancel action.
class EquipmentScheduleTab extends StatefulWidget {
  const EquipmentScheduleTab({super.key});

  @override
  State<EquipmentScheduleTab> createState() => _EquipmentScheduleTabState();
}

class _EquipmentScheduleTabState extends State<EquipmentScheduleTab> {
  /// the day whose reservations are shown — date-only (midnight).
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDay.year == now.year &&
        _selectedDay.month == now.month &&
        _selectedDay.day == now.day;
  }

  void _shiftDay(int deltaDays) {
    setState(() {
      _selectedDay = _selectedDay.add(Duration(days: deltaDays));
    });
  }

  void _resetToToday() {
    final now = DateTime.now();
    setState(() => _selectedDay = DateTime(now.year, now.month, now.day));
  }

  Future<void> _cancelReservation(EquipmentReservation reservation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel reservation'),
        content: Text(
            'Cancel ${reservation.employeeName}\'s reservation of '
            '${reservation.equipmentName} unit #${reservation.unitNumber} on '
            '${reservation.date}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Back')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Cancel reservation')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await EquipmentReservationService.cancelReservation(id: reservation.id);
      if (!mounted) return;
      _snack('Reservation cancelled.');
    } catch (error) {
      if (!mounted) return;
      _snack(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final dayKey = DateFormat('yyyy-MM-dd').format(_selectedDay);

    return Column(
      children: [
        _buildDayControls(context),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<List<EquipmentReservation>>(
            stream: EquipmentReservationService.watchAllReservations(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                    child: Text('Failed to load schedule: ${snapshot.error}'));
              }

              final all = snapshot.data ?? const <EquipmentReservation>[];
              final forDay = all
                  .where((r) => r.isActive && r.date == dayKey)
                  .toList();

              if (forDay.isEmpty) {
                return const Center(
                    child: Text('No reservations for this day.'));
              }

              // group by equipment name, sorted by start time within each group
              final grouped = <String, List<EquipmentReservation>>{};
              for (final reservation in forDay) {
                grouped
                    .putIfAbsent(reservation.equipmentName, () => [])
                    .add(reservation);
              }
              for (final list in grouped.values) {
                list.sort((a, b) => a.startTime.compareTo(b.startTime));
              }
              final names = grouped.keys.toList()..sort();

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final name in names) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        name.isEmpty ? 'Equipment' : name,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    for (final reservation in grouped[name]!)
                      _ScheduleRow(
                        reservation: reservation,
                        onCancel: () => _cancelReservation(reservation),
                      ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDayControls(BuildContext context) {
    final label = DateFormat('EEE, MMM d, yyyy').format(_selectedDay);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _shiftDay(-1),
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous day',
          ),
          Expanded(
            child: Column(
              children: [
                Text(label,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (!_isToday)
                  TextButton(
                    onPressed: _resetToToday,
                    child: const Text('Today'),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _shiftDay(1),
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next day',
          ),
        ],
      ),
    );
  }
}

/// one reservation row in the owner schedule: unit, time window, employee, a
/// checkout/return status indicator, and a cancel action.
class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.reservation, required this.onCancel});

  final EquipmentReservation reservation;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('h:mm a');
    final window =
        '${timeFmt.format(reservation.startTime)} – ${timeFmt.format(reservation.endTime)}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          child: Text('#${reservation.unitNumber}',
              style: const TextStyle(fontSize: 12)),
        ),
        title: Text(window),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(reservation.employeeName),
            const SizedBox(height: 4),
            _CheckoutStatus(reservation: reservation),
          ],
        ),
        isThreeLine: true,
        trailing: IconButton(
          onPressed: onCancel,
          icon: const Icon(Icons.cancel_outlined),
          tooltip: 'Cancel reservation',
          iconSize: 20,
        ),
      ),
    );
  }
}

/// small pill reflecting whether a reservation has been checked out / returned.
class _CheckoutStatus extends StatelessWidget {
  const _CheckoutStatus({required this.reservation});

  final EquipmentReservation reservation;

  @override
  Widget build(BuildContext context) {
    String label;
    Color color;
    if (reservation.returnedAt != null) {
      label = 'Returned';
      color = Colors.blueGrey;
    } else if (reservation.checkedOutAt != null) {
      label = 'Checked out';
      color = Colors.green;
    } else {
      label = 'Not checked out yet';
      color = Colors.orange;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

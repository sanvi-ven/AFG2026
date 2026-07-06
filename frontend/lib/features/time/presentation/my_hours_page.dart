import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/time_entry_service.dart';
import '../../../core/state/employee_session.dart';
import '../../../models/time_entry.dart';
import '../../../shared/widgets/app_scaffold.dart';

/// general shift clock in/out and recent hours history for the signed-in employee
class MyHoursPage extends StatefulWidget {
  const MyHoursPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  @override
  State<MyHoursPage> createState() => _MyHoursPageState();
}

class _MyHoursPageState extends State<MyHoursPage> {
  bool _isSubmitting = false;

  Future<void> _clockIn(String employeeId) async {
    setState(() => _isSubmitting = true);
    try {
      await TimeEntryService.clockIn(employeeId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _clockOut(String employeeId) async {
    setState(() => _isSubmitting = true);
    try {
      await TimeEntryService.clockOut(employeeId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: EmployeeSession.profile,
      builder: (context, profile, _) {
        final employeeId = profile?.employeeId;

        return AppScaffold(
          title: 'My Hours',
          role: widget.role,
          authToken: widget.authToken,
          selectedRoute: AppRouter.myHours,
          body: employeeId == null
              ? const Center(child: Text('Log in to track your hours.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    StreamBuilder<TimeEntry?>(
                      stream: TimeEntryService.watchTodayEntry(employeeId),
                      builder: (context, snapshot) {
                        final entry = snapshot.data;
                        final isClockedIn = entry?.isClockedIn ?? false;

                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Today's shift", style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 10),
                                if (entry?.clockInAt != null)
                                  Text('Clocked in: ${DateFormat('h:mm a').format(entry!.clockInAt!)}'),
                                if (entry?.clockOutAt != null)
                                  Text('Clocked out: ${DateFormat('h:mm a').format(entry!.clockOutAt!)}'),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _isSubmitting
                                      ? null
                                      : isClockedIn
                                          ? () => _clockOut(employeeId)
                                          : entry?.clockOutAt != null
                                              ? null
                                              : () => _clockIn(employeeId),
                                  icon: Icon(isClockedIn ? Icons.logout : Icons.login),
                                  label: Text(
                                    entry?.clockOutAt != null
                                        ? 'Shift complete'
                                        : isClockedIn
                                            ? 'Clock out'
                                            : 'Clock in',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    StreamBuilder<List<TimeEntry>>(
                      stream: TimeEntryService.watchEntriesForEmployee(employeeId),
                      builder: (context, snapshot) {
                        final entries = snapshot.data ?? const <TimeEntry>[];
                        final totalDuration = entries.fold<Duration>(Duration.zero, (sum, e) {
                          if (e.clockInAt == null || e.clockOutAt == null) return sum;
                          return sum + e.clockOutAt!.difference(e.clockInAt!);
                        });
                        final rate = profile?.hourlyRate;
                        final hours = totalDuration.inMinutes / 60.0;
                        final payout = rate != null ? hours * rate : null;

                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Your Pay', style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 8),
                                Text('Total hours: ${hours.toStringAsFixed(1)}h'),
                                Text(rate == null
                                    ? 'Hourly rate not set yet.'
                                    : 'Rate: \$${rate.toStringAsFixed(2)}/hr'),
                                if (payout != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Total payout: \$${payout.toStringAsFixed(2)}',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    Text('Recent history', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    StreamBuilder<List<TimeEntry>>(
                      stream: TimeEntryService.watchEntriesForEmployee(employeeId),
                      builder: (context, snapshot) {
                        final entries = snapshot.data ?? const <TimeEntry>[];
                        if (entries.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('No shifts recorded yet.'),
                          );
                        }
                        return Column(
                          children: [
                            for (final entry in entries)
                              Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  title: Text(entry.date),
                                  subtitle: Text(
                                    entry.clockInAt == null
                                        ? 'No clock-in recorded'
                                        : '${DateFormat('h:mm a').format(entry.clockInAt!)}'
                                            ' – ${entry.clockOutAt == null ? 'in progress' : DateFormat('h:mm a').format(entry.clockOutAt!)}',
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
        );
      },
    );
  }
}

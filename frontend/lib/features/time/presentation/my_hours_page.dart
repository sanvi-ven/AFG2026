import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/reporting_service.dart';
import '../../../core/services/time_entry_service.dart';
import '../../../core/state/employee_session.dart';
import '../../../models/time_entry.dart';
import '../../../shared/utils/time_entry_pay_format.dart';
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
                    StreamBuilder<List<TimeEntry>>(
                      stream: TimeEntryService.watchTodayEntries(employeeId),
                      builder: (context, snapshot) {
                        final todaysEntries = snapshot.data ?? const <TimeEntry>[];
                        final isClockedIn = todaysEntries.any((e) => e.isClockedIn);

                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Today's shifts", style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 10),
                                if (todaysEntries.isEmpty)
                                  const Text('No shifts yet today.')
                                else
                                  for (final entry in todaysEntries)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        '${entry.clockInAt == null ? '—' : DateFormat('h:mm a').format(entry.clockInAt!)}'
                                        ' – ${entry.clockOutAt == null ? 'in progress' : DateFormat('h:mm a').format(entry.clockOutAt!)}',
                                      ),
                                    ),
                                const SizedBox(height: 8),
                                FilledButton.icon(
                                  onPressed: _isSubmitting
                                      ? null
                                      : isClockedIn
                                          ? () => _clockOut(employeeId)
                                          : () => _clockIn(employeeId),
                                  icon: Icon(isClockedIn ? Icons.logout : Icons.login),
                                  label: Text(
                                    isClockedIn
                                        ? 'Clock out'
                                        : todaysEntries.isEmpty
                                            ? 'Clock in'
                                            : 'Clock in (new shift)',
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
                        final rate = profile?.hourlyRate;
                        final hours = entries.fold<double>(
                          0,
                          (sum, e) => sum + ReportingService.hoursForEntry(e),
                        );
                        final payout = entries.fold<double>(
                          0,
                          (sum, e) => sum + ReportingService.payoutForEntry(e, profile),
                        );

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
                                if (payout > 0) ...[
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
                                    '${entry.clockInAt == null ? 'No clock-in recorded' : '${DateFormat('h:mm a').format(entry.clockInAt!)}'
                                        ' – ${entry.clockOutAt == null ? 'in progress' : DateFormat('h:mm a').format(entry.clockOutAt!)}'}'
                                    '\n${formatEntryPay(entry, profile)}',
                                  ),
                                  isThreeLine: true,
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

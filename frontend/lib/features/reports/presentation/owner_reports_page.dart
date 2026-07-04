import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/client_profile_service.dart';
import '../../../core/services/employee_profile_service.dart';
import '../../../core/services/estimate_service.dart';
import '../../../core/services/invoice_service.dart';
import '../../../core/services/reporting_service.dart';
import '../../../core/services/scheduled_work_service.dart';
import '../../../core/services/time_entry_service.dart';
import '../../../models/client_profile.dart';
import '../../../models/employee_profile.dart';
import '../../../models/estimate.dart';
import '../../../models/invoice.dart';
import '../../../models/scheduled_work.dart';
import '../../../models/time_entry.dart';
import '../../../shared/widgets/app_scaffold.dart';

enum _ReportRange { thisWeek, thisMonth, allTime }

/// owner-only revenue/pipeline/hours reporting dashboard. Every source
/// collection is already streamed in full by its existing service and
/// aggregated here in Dart, matching this app's established pattern.
class OwnerReportsPage extends StatefulWidget {
  const OwnerReportsPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  @override
  State<OwnerReportsPage> createState() => _OwnerReportsPageState();
}

class _OwnerReportsPageState extends State<OwnerReportsPage> {
  _ReportRange _range = _ReportRange.thisMonth;
  static final DateFormat _isoDate = DateFormat('yyyy-MM-dd');

  (String, String) _rangeBounds() {
    final now = DateTime.now();
    late final DateTime start;
    switch (_range) {
      case _ReportRange.thisWeek:
        start = now.subtract(Duration(days: now.weekday - 1));
        break;
      case _ReportRange.thisMonth:
        start = DateTime(now.year, now.month, 1);
        break;
      case _ReportRange.allTime:
        start = DateTime(2000, 1, 1);
        break;
    }
    return (_isoDate.format(start), _isoDate.format(now));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.role != 'owner') {
      return const SizedBox.shrink();
    }

    final (startDate, endDate) = _rangeBounds();

    return AppScaffold(
      title: 'Reports',
      role: widget.role,
      authToken: widget.authToken,
      selectedRoute: AppRouter.reports,
      body: StreamBuilder<List<Invoice>>(
        stream: InvoiceService.watchInvoices(role: 'owner'),
        builder: (context, invoiceSnapshot) {
          return StreamBuilder<List<Estimate>>(
            stream: EstimateService.watchEstimates(role: 'owner'),
            builder: (context, estimateSnapshot) {
              return StreamBuilder<List<ScheduledWork>>(
                stream: ScheduledWorkService.watchScheduledWork(role: 'owner'),
                builder: (context, jobsSnapshot) {
                  return StreamBuilder<List<ClientProfile>>(
                    stream: ClientProfileService.watchAllProfiles(),
                    builder: (context, clientsSnapshot) {
                      return StreamBuilder<List<EmployeeProfile>>(
                        stream: EmployeeProfileService.watchAllProfiles(),
                        builder: (context, employeesSnapshot) {
                          return StreamBuilder<List<TimeEntry>>(
                            stream: TimeEntryService.watchEntriesInRange(startDate, endDate),
                            builder: (context, entriesSnapshot) {
                              final loading = !invoiceSnapshot.hasData ||
                                  !estimateSnapshot.hasData ||
                                  !jobsSnapshot.hasData ||
                                  !clientsSnapshot.hasData ||
                                  !employeesSnapshot.hasData ||
                                  !entriesSnapshot.hasData;
                              if (loading) {
                                return const Center(child: CircularProgressIndicator());
                              }

                              return _ReportsBody(
                                range: _range,
                                onRangeChanged: (value) => setState(() => _range = value),
                                invoices: invoiceSnapshot.data!,
                                estimates: estimateSnapshot.data!,
                                jobs: jobsSnapshot.data!,
                                clients: clientsSnapshot.data!,
                                employees: employeesSnapshot.data!,
                                entries: entriesSnapshot.data!,
                              );
                            },
                          );
                        },
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
}

class _ReportsBody extends StatelessWidget {
  const _ReportsBody({
    required this.range,
    required this.onRangeChanged,
    required this.invoices,
    required this.estimates,
    required this.jobs,
    required this.clients,
    required this.employees,
    required this.entries,
  });

  final _ReportRange range;
  final ValueChanged<_ReportRange> onRangeChanged;
  final List<Invoice> invoices;
  final List<Estimate> estimates;
  final List<ScheduledWork> jobs;
  final List<ClientProfile> clients;
  final List<EmployeeProfile> employees;
  final List<TimeEntry> entries;

  static final NumberFormat _currency = NumberFormat.simpleCurrency();

  @override
  Widget build(BuildContext context) {
    final monthlyRevenue = ReportingService.paidRevenueByMonth(invoices);
    final totalPaid = ReportingService.totalPaidRevenue(invoices);
    final expectedFromEstimates = ReportingService.expectedRevenueFromEstimates(estimates);
    final expectedFromJobs = ReportingService.expectedRevenueFromScheduledWork(jobs);
    final busiestClients = ReportingService.busiestClients(
      clients,
      invoices: invoices,
      estimates: estimates,
      scheduledWork: jobs,
    ).take(8).toList();
    final hoursByEmployee = ReportingService.employeeHoursByEmployee(entries);
    final employeeNameFor = {for (final employee in employees) employee.employeeId: employee.fullName};

    final sortedMonths = monthlyRevenue.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Revenue', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('Total paid to date: ${_currency.format(totalPaid)}'),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: sortedMonths.isEmpty
              ? const Center(child: Text('No paid invoices yet.'))
              : BarChart(
                  BarChartData(
                    barGroups: [
                      for (var i = 0; i < sortedMonths.length; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: monthlyRevenue[sortedMonths[i]] ?? 0,
                              color: Theme.of(context).colorScheme.primary,
                              width: 18,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        ),
                    ],
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < 0 || index >= sortedMonths.length) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(sortedMonths[index], style: const TextStyle(fontSize: 10)),
                            );
                          },
                        ),
                      ),
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: true, drawVerticalLine: false),
                  ),
                ),
        ),
        const SizedBox(height: 24),
        Text('Expected Revenue', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'Approved, not yet scheduled',
                value: _currency.format(expectedFromEstimates),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                label: 'Scheduled, not yet invoiced',
                value: _currency.format(expectedFromJobs),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('Busiest Clients', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (busiestClients.isEmpty)
          const Text('No client activity yet.')
        else
          Card(
            child: Column(
              children: [
                for (final client in busiestClients)
                  ListTile(
                    title: Text(client.displayName),
                    subtitle: Text('${client.count} record(s)'),
                    trailing: Text(
                      _currency.format(client.total),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Employee Hours', style: Theme.of(context).textTheme.titleLarge),
            SegmentedButton<_ReportRange>(
              segments: const [
                ButtonSegment(value: _ReportRange.thisWeek, label: Text('Week')),
                ButtonSegment(value: _ReportRange.thisMonth, label: Text('Month')),
                ButtonSegment(value: _ReportRange.allTime, label: Text('All')),
              ],
              selected: {range},
              onSelectionChanged: (selection) => onRangeChanged(selection.first),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (hoursByEmployee.isEmpty)
          const Text('No clocked hours in this range.')
        else
          Card(
            child: Column(
              children: [
                for (final entry in hoursByEmployee.entries)
                  ListTile(
                    title: Text(employeeNameFor[entry.key] ?? entry.key),
                    trailing: Text(
                      '${entry.value.inHours}h ${entry.value.inMinutes.remainder(60)}m',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

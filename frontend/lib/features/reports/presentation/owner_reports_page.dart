import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/broken_report_service.dart';
import '../../../core/services/client_profile_service.dart';
import '../../../core/services/employee_profile_service.dart';
import '../../../core/services/equipment_reservation_service.dart';
import '../../../core/services/equipment_service.dart';
import '../../../core/services/estimate_service.dart';
import '../../../core/services/expense_service.dart';
import '../../../core/services/invoice_service.dart';
import '../../../core/services/job_completion_service.dart';
import '../../../core/services/reporting_service.dart';
import '../../../core/services/scheduled_work_service.dart';
import '../../../core/services/team_service.dart';
import '../../../core/services/time_entry_service.dart';
import '../../../models/broken_report.dart';
import '../../../models/client_profile.dart';
import '../../../models/employee_profile.dart';
import '../../../models/equipment.dart';
import '../../../models/equipment_reservation.dart';
import '../../../models/estimate.dart';
import '../../../models/expense.dart';
import '../../../models/invoice.dart';
import '../../../models/job_completion_form.dart';
import '../../../models/scheduled_work.dart';
import '../../../models/team.dart';
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

  DateTime _rangeStart() {
    final now = DateTime.now();
    switch (_range) {
      case _ReportRange.thisWeek:
        return now.subtract(Duration(days: now.weekday - 1));
      case _ReportRange.thisMonth:
        return DateTime(now.year, now.month, 1);
      case _ReportRange.allTime:
        return DateTime(2000, 1, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.role != 'owner') {
      return const SizedBox.shrink();
    }

    final rangeStart = _rangeStart();
    final rangeEnd = DateTime.now();
    final startDate = _isoDate.format(rangeStart);
    final endDate = _isoDate.format(rangeEnd);

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
                          return StreamBuilder<List<Team>>(
                            stream: TeamService.watchAllTeams(),
                            builder: (context, teamsSnapshot) {
                              return StreamBuilder<List<TimeEntry>>(
                                stream: TimeEntryService.watchEntriesInRange(startDate, endDate),
                                builder: (context, entriesSnapshot) {
                                  return StreamBuilder<List<JobCompletionForm>>(
                                    stream: JobCompletionService.watchAllForms(),
                                    builder: (context, formsSnapshot) {
                                      return StreamBuilder<List<Expense>>(
                                        stream: ExpenseService.watchAllExpenses(),
                                        builder: (context, expensesSnapshot) {
                                          final loading = !invoiceSnapshot.hasData ||
                                              !estimateSnapshot.hasData ||
                                              !jobsSnapshot.hasData ||
                                              !clientsSnapshot.hasData ||
                                              !employeesSnapshot.hasData ||
                                              !teamsSnapshot.hasData ||
                                              !entriesSnapshot.hasData ||
                                              !formsSnapshot.hasData ||
                                              !expensesSnapshot.hasData;
                                          if (loading) {
                                            return const Center(child: CircularProgressIndicator());
                                          }

                                          return _ReportsTabs(
                                            range: _range,
                                            onRangeChanged: (value) => setState(() => _range = value),
                                            invoices: invoiceSnapshot.data!,
                                            estimates: estimateSnapshot.data!,
                                            jobs: jobsSnapshot.data!,
                                            clients: clientsSnapshot.data!,
                                            employees: employeesSnapshot.data!,
                                            teams: teamsSnapshot.data!,
                                            entries: entriesSnapshot.data!,
                                            forms: formsSnapshot.data!,
                                            expenses: expensesSnapshot.data!,
                                            rangeStart: rangeStart,
                                            rangeEnd: rangeEnd,
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

class _ReportsTabs extends StatelessWidget {
  const _ReportsTabs({
    required this.range,
    required this.onRangeChanged,
    required this.invoices,
    required this.estimates,
    required this.jobs,
    required this.clients,
    required this.employees,
    required this.teams,
    required this.entries,
    required this.forms,
    required this.expenses,
    required this.rangeStart,
    required this.rangeEnd,
  });

  final _ReportRange range;
  final ValueChanged<_ReportRange> onRangeChanged;
  final List<Invoice> invoices;
  final List<Estimate> estimates;
  final List<ScheduledWork> jobs;
  final List<ClientProfile> clients;
  final List<EmployeeProfile> employees;
  final List<Team> teams;
  final List<TimeEntry> entries;
  final List<JobCompletionForm> forms;
  final List<Expense> expenses;
  final DateTime rangeStart;
  final DateTime rangeEnd;

  @override
  Widget build(BuildContext context) {
    // range-scoped copies used only for the Net Profit figure — the
    // dashboard's own revenue chart/stat tiles stay all-time as before.
    final rangeInvoices = invoices
        .where((invoice) => !invoice.createdAt.isBefore(rangeStart) && !invoice.createdAt.isAfter(rangeEnd))
        .toList();
    final rangeExpenses =
        expenses.where((expense) => !expense.date.isBefore(rangeStart) && !expense.date.isAfter(rangeEnd)).toList();

    final payoutRows = ReportingService.employeePayoutReport(entries: entries, employees: employees);
    final totalPayout = payoutRows.fold<double>(0, (sum, row) => sum + row.payout);
    final netProfit = ReportingService.netProfit(
      paidRevenue: ReportingService.totalPaidRevenue(rangeInvoices),
      totalPayout: totalPayout,
      totalExpenses: ReportingService.totalExpenses(rangeExpenses),
    );

    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          const Material(
            color: Colors.transparent,
            child: TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Dashboard'),
                Tab(text: 'Completed Jobs'),
                Tab(text: 'Employee Payout'),
                Tab(text: 'Expenses'),
                Tab(text: 'Equipment'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _DashboardTab(
                  range: range,
                  onRangeChanged: onRangeChanged,
                  invoices: invoices,
                  estimates: estimates,
                  jobs: jobs,
                  clients: clients,
                  employees: employees,
                  entries: entries,
                  netProfit: netProfit,
                ),
                _CompletedJobsTab(
                  rows: ReportingService.completedJobsReport(
                    jobs: jobs,
                    forms: forms,
                    invoices: invoices,
                    clients: clients,
                  ),
                  teamNameFor: {for (final team in teams) team.id: team.name},
                ),
                _EmployeePayoutTab(rows: payoutRows),
                _ExpensesTab(expenses: expenses),
                const _EquipmentReportsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab({
    required this.range,
    required this.onRangeChanged,
    required this.invoices,
    required this.estimates,
    required this.jobs,
    required this.clients,
    required this.employees,
    required this.entries,
    required this.netProfit,
  });

  final _ReportRange range;
  final ValueChanged<_ReportRange> onRangeChanged;
  final List<Invoice> invoices;
  final List<Estimate> estimates;
  final List<ScheduledWork> jobs;
  final List<ClientProfile> clients;
  final List<EmployeeProfile> employees;
  final List<TimeEntry> entries;
  final double netProfit;

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
        const SizedBox(height: 12),
        _StatTile(
          label: 'Net Profit (selected range: revenue − payroll − expenses)',
          value: _currency.format(netProfit),
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

class _CompletedJobsTab extends StatelessWidget {
  const _CompletedJobsTab({required this.rows, required this.teamNameFor});

  final List<CompletedJobRow> rows;
  final Map<String, String> teamNameFor;

  static final NumberFormat _currency = NumberFormat.simpleCurrency();
  static final DateFormat _dateFormat = DateFormat('MMM d, yyyy');

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(16), child: Text('No completed jobs yet.')),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Job')),
          DataColumn(label: Text('Client')),
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Duration')),
          DataColumn(label: Text('Team')),
          DataColumn(label: Text('Income')),
        ],
        rows: [
          for (final row in rows)
            DataRow(cells: [
              DataCell(Text(row.estimateNumber)),
              DataCell(Text(row.clientName)),
              DataCell(Text(_dateFormat.format(row.date))),
              DataCell(Text(row.duration == null
                  ? '—'
                  : '${row.duration!.inHours}h ${row.duration!.inMinutes.remainder(60)}m')),
              DataCell(Text(row.teamId == null ? 'Unassigned' : (teamNameFor[row.teamId] ?? row.teamId!))),
              DataCell(Text(_currency.format(row.income))),
            ]),
        ],
      ),
    );
  }
}

class _EmployeePayoutTab extends StatelessWidget {
  const _EmployeePayoutTab({required this.rows});

  final List<EmployeePayoutRow> rows;

  static final NumberFormat _currency = NumberFormat.simpleCurrency();

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(16), child: Text('No employees yet.')),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Employee')),
          DataColumn(label: Text('Hours')),
          DataColumn(label: Text('Rate')),
          DataColumn(label: Text('Payout')),
        ],
        rows: [
          for (final row in rows)
            DataRow(cells: [
              DataCell(Text(row.name)),
              DataCell(Text(row.hours.toStringAsFixed(1))),
              DataCell(Text(row.rate == 0 ? '—' : '${_currency.format(row.rate)}/hr')),
              DataCell(Text(_currency.format(row.payout))),
            ]),
        ],
      ),
    );
  }
}

class _ExpensesTab extends StatefulWidget {
  const _ExpensesTab({required this.expenses});

  final List<Expense> expenses;

  @override
  State<_ExpensesTab> createState() => _ExpensesTabState();
}

class _ExpensesTabState extends State<_ExpensesTab> {
  static final NumberFormat _currency = NumberFormat.simpleCurrency();
  static final DateFormat _dateFormat = DateFormat('MMM d, yyyy');

  Future<void> _addExpense() async {
    await showDialog<void>(context: context, builder: (_) => const _AddExpenseDialog());
  }

  Future<void> _confirmDelete(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Expense'),
        content: Text("Delete '${expense.description}'? This can't be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ExpenseService.deleteExpense(expense.id);
  }

  @override
  Widget build(BuildContext context) {
    final total = ReportingService.totalExpenses(widget.expenses);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Total: ${_currency.format(total)}', style: Theme.of(context).textTheme.titleMedium),
            FilledButton.icon(
              onPressed: _addExpense,
              icon: const Icon(Icons.add),
              label: const Text('Add Expense'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (widget.expenses.isEmpty)
          const Text('No expenses logged yet.')
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Description')),
                DataColumn(label: Text('Category')),
                DataColumn(label: Text('Amount')),
                DataColumn(label: Text('')),
              ],
              rows: [
                for (final expense in widget.expenses)
                  DataRow(cells: [
                    DataCell(Text(_dateFormat.format(expense.date))),
                    DataCell(Text(expense.description)),
                    DataCell(Text(ExpenseCategory.displayLabel(expense.category))),
                    DataCell(Text(_currency.format(expense.amount))),
                    DataCell(IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete',
                      onPressed: () => _confirmDelete(expense),
                    )),
                  ]),
              ],
            ),
          ),
      ],
    );
  }
}

class _AddExpenseDialog extends StatefulWidget {
  const _AddExpenseDialog();

  @override
  State<_AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<_AddExpenseDialog> {
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  String _category = ExpenseCategory.material;
  DateTime _date = DateTime.now();
  bool _isSaving = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final description = _descriptionController.text.trim();
    final amount = double.tryParse(_amountController.text.trim());
    if (description.isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A description and amount greater than 0 are required.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ExpenseService.createExpense(
        description: description,
        category: _category,
        amount: amount,
        date: _date,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save expense: $error')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Expense'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
              items: [
                for (final category in ExpenseCategory.all)
                  DropdownMenuItem(value: category, child: Text(ExpenseCategory.displayLabel(category))),
              ],
              onChanged: (value) => setState(() => _category = value ?? _category),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount (\$)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(DateFormat('MMM d, yyyy').format(_date)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _isSaving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

/// Equipment usage reporting: two bar charts derived entirely from data already
/// written by the equipment feature — most-requested (by reservation count) and
/// most-broken (by broken-report count). No new collections or writes. Broken
/// reports carry only an equipmentId, so equipment items are streamed once to
/// resolve ids to display names.
class _EquipmentReportsTab extends StatelessWidget {
  const _EquipmentReportsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<EquipmentItem>>(
      stream: EquipmentService.watchAll(includeArchived: true),
      builder: (context, equipmentSnapshot) {
        return StreamBuilder<List<EquipmentReservation>>(
          stream: EquipmentReservationService.watchAllReservations(),
          builder: (context, reservationSnapshot) {
            return StreamBuilder<List<BrokenReport>>(
              stream: BrokenReportService.watchAllReports(),
              builder: (context, brokenSnapshot) {
                final loading = !equipmentSnapshot.hasData ||
                    !reservationSnapshot.hasData ||
                    !brokenSnapshot.hasData;
                if (loading) {
                  return const Center(child: CircularProgressIndicator());
                }

                final equipment = equipmentSnapshot.data!;
                final reservations = reservationSnapshot.data!;
                final broken = brokenSnapshot.data!;

                final nameForId = {for (final item in equipment) item.id: item.name};

                // most requested: active (non-cancelled) reservations grouped
                // by denormalized name — a cancelled reservation isn't real
                // demand and shouldn't count toward "most requested."
                final requestCounts = <String, int>{};
                for (final reservation in reservations.where((r) => r.isActive)) {
                  final name = reservation.equipmentName.trim().isEmpty
                      ? 'Unknown'
                      : reservation.equipmentName.trim();
                  requestCounts[name] = (requestCounts[name] ?? 0) + 1;
                }

                // most broken: reports grouped by resolved equipment name
                final brokenCounts = <String, int>{};
                for (final report in broken) {
                  final name = nameForId[report.equipmentId] ?? 'Unknown';
                  brokenCounts[name] = (brokenCounts[name] ?? 0) + 1;
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('Most Requested Equipment', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    const Text('By number of reservations'),
                    const SizedBox(height: 12),
                    _CountBarChart(
                      entries: _topEntries(requestCounts, 8),
                      emptyMessage: 'No equipment reservations yet.',
                    ),
                    const SizedBox(height: 24),
                    Text('Most Broken Equipment', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    const Text('By number of broken reports (all time)'),
                    const SizedBox(height: 12),
                    _CountBarChart(
                      entries: _topEntries(brokenCounts, 8),
                      emptyMessage: 'No broken reports yet.',
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  static List<MapEntry<String, int>> _topEntries(Map<String, int> counts, int limit) {
    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).toList();
  }
}

/// integer-count bar chart matching the dashboard's revenue chart conventions
/// (primary-color rods, index-based bottom labels, hidden top/right titles).
class _CountBarChart extends StatelessWidget {
  const _CountBarChart({required this.entries, required this.emptyMessage});

  final List<MapEntry<String, int>> entries;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: entries.isEmpty
          ? Center(child: Text(emptyMessage))
          : BarChart(
              BarChartData(
                barGroups: [
                  for (var i = 0; i < entries.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: entries[i].value.toDouble(),
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
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= entries.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _shortLabel(entries[index].key),
                            style: const TextStyle(fontSize: 10),
                            textAlign: TextAlign.center,
                          ),
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
    );
  }

  static String _shortLabel(String name) {
    if (name.length <= 10) return name;
    return '${name.substring(0, 9)}…';
  }
}

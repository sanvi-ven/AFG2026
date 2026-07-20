import 'package:intl/intl.dart';

import '../../models/client_profile.dart';
import '../../models/employee_profile.dart';
import '../../models/estimate.dart';
import '../../models/expense.dart';
import '../../models/invoice.dart';
import '../../models/job_completion_form.dart';
import '../../models/scheduled_work.dart';
import '../../models/time_entry.dart';
import 'client_profile_service.dart';

/// pure aggregation helpers for the owner reporting dashboard.
/// operates on already-fetched lists from the existing services — no new
/// Firestore collection or server-side aggregation is introduced.
class ReportingService {
  ReportingService._();

  static final DateFormat _monthFormat = DateFormat('yyyy-MM');

  /// paid invoice revenue bucketed by month. There's no `paidAt`/`dueDate`
  /// field on [Invoice] — `createdAt` is used as the practical proxy for
  /// "when this revenue landed."
  static Map<String, double> paidRevenueByMonth(List<Invoice> invoices) {
    final buckets = <String, double>{};
    for (final invoice in invoices) {
      if (invoice.status != InvoiceStatus.paid) continue;
      final key = _monthFormat.format(invoice.createdAt);
      buckets[key] = (buckets[key] ?? 0) + invoice.total;
    }
    return buckets;
  }

  static double totalPaidRevenue(List<Invoice> invoices) {
    return invoices
        .where((invoice) => invoice.status == InvoiceStatus.paid)
        .fold<double>(0, (sum, invoice) => sum + invoice.total);
  }

  /// approved estimates not yet converted to an invoice or scheduled job.
  static double expectedRevenueFromEstimates(List<Estimate> estimates) {
    return estimates
        .where((estimate) => estimate.isConvertible)
        .fold<double>(0, (sum, estimate) => sum + estimate.total);
  }

  /// jobs already scheduled/completed but not yet invoiced.
  static double expectedRevenueFromScheduledWork(List<ScheduledWork> jobs) {
    return jobs
        .where((job) => job.status != ScheduledWorkStatus.invoiced)
        .fold<double>(0, (sum, job) => sum + job.total);
  }

  static List<ClientTotal> busiestClients(
    List<ClientProfile> profiles, {
    List<Invoice> invoices = const [],
    List<Estimate> estimates = const [],
    List<ScheduledWork> scheduledWork = const [],
  }) {
    final totals = <String, double>{};
    final counts = <String, int>{};

    void tally(String clientId, double amount) {
      if (clientId.trim().isEmpty) return;
      totals[clientId] = (totals[clientId] ?? 0) + amount;
      counts[clientId] = (counts[clientId] ?? 0) + 1;
    }

    for (final invoice in invoices) {
      tally(invoice.clientId, invoice.total);
    }
    for (final estimate in estimates) {
      tally(estimate.clientId, estimate.total);
    }
    for (final job in scheduledWork) {
      tally(job.clientId, job.total);
    }

    final clientTotals = totals.entries
        .map((entry) => ClientTotal(
              clientId: entry.key,
              displayName: ClientProfileService.displayNameFor(profiles, entry.key),
              total: entry.value,
              count: counts[entry.key] ?? 0,
            ))
        .toList();
    clientTotals.sort((a, b) => b.total.compareTo(a.total));
    return clientTotals;
  }

  /// total clocked hours per employee across the given entries (expects
  /// entries already scoped to the desired date range).
  static Map<String, Duration> employeeHoursByEmployee(List<TimeEntry> entries) {
    final hours = <String, Duration>{};
    for (final entry in entries) {
      final clockInAt = entry.clockInAt;
      final clockOutAt = entry.clockOutAt;
      if (clockInAt == null || clockOutAt == null) continue;
      final worked = clockOutAt.difference(clockInAt);
      hours[entry.employeeId] = (hours[entry.employeeId] ?? Duration.zero) + worked;
    }
    return hours;
  }

  /// per-completed-job income + duration, joining scheduled work with
  /// completion forms (by workId, for duration) and invoices (by invoiceId,
  /// for actual billed income — falls back to the job's own total if it
  /// hasn't been invoiced yet).
  static List<CompletedJobRow> completedJobsReport({
    required List<ScheduledWork> jobs,
    required List<JobCompletionForm> forms,
    required List<Invoice> invoices,
    required List<ClientProfile> clients,
  }) {
    final formsByWorkId = {for (final form in forms) form.workId: form};
    final invoicesById = {for (final invoice in invoices) invoice.id: invoice};

    final rows = <CompletedJobRow>[];
    for (final job in jobs.where((j) => j.isCompleted || j.isInvoiced)) {
      final form = formsByWorkId[job.id];
      final invoice = job.invoiceId != null ? invoicesById[job.invoiceId] : null;
      rows.add(CompletedJobRow(
        jobId: job.id,
        estimateNumber: job.estimateNumber,
        clientName: ClientProfileService.displayNameFor(clients, job.clientId),
        date: job.scheduledDate,
        duration: form?.endTime.difference(form.startTime),
        income: invoice?.total ?? job.total,
        teamId: job.teamId,
      ));
    }
    rows.sort((a, b) => b.date.compareTo(a.date));
    return rows;
  }

  /// hours worked on a single time entry (0 if not yet clocked out)
  static double hoursForEntry(TimeEntry entry) {
    final clockInAt = entry.clockInAt;
    final clockOutAt = entry.clockOutAt;
    if (clockInAt == null || clockOutAt == null) return 0;
    return clockOutAt.difference(clockInAt).inMinutes / 60.0;
  }

  /// the hourly rate that actually applies to this entry — its own
  /// wageOverride when set, else the employee's normal hourlyRate (0 if
  /// neither is set)
  static double effectiveRateForEntry(TimeEntry entry, EmployeeProfile? employee) =>
      entry.wageOverride ?? employee?.hourlyRate ?? 0;

  /// calculated pay for a single time entry: hoursForEntry × effectiveRateForEntry
  static double payoutForEntry(TimeEntry entry, EmployeeProfile? employee) =>
      hoursForEntry(entry) * effectiveRateForEntry(entry, employee);

  /// per-employee hours worked and calculated payout. Each entry's payout
  /// uses its own wageOverride when set (e.g. a one-off holiday/overtime
  /// rate), falling back to the employee's normal hourlyRate (0 if unset) —
  /// so a per-shift override actually moves the payout total, not just the
  /// displayed base rate.
  static List<EmployeePayoutRow> employeePayoutReport({
    required List<TimeEntry> entries,
    required List<EmployeeProfile> employees,
  }) {
    return employees.map((employee) {
      var hours = 0.0;
      var payout = 0.0;
      for (final entry in entries.where((e) => e.employeeId == employee.employeeId)) {
        hours += hoursForEntry(entry);
        payout += payoutForEntry(entry, employee);
      }
      return EmployeePayoutRow(
        employeeId: employee.employeeId,
        name: employee.fullName,
        hours: hours,
        rate: employee.hourlyRate ?? 0,
        payout: payout,
      );
    }).toList();
  }

  static double totalExpenses(List<Expense> expenses) =>
      expenses.fold<double>(0, (sum, expense) => sum + expense.amount);

  /// paidRevenue − totalPayout − totalExpenses, all pre-filtered to the same
  /// date range by the caller.
  static double netProfit({
    required double paidRevenue,
    required double totalPayout,
    required double totalExpenses,
  }) =>
      paidRevenue - totalPayout - totalExpenses;
}

class ClientTotal {
  const ClientTotal({
    required this.clientId,
    required this.displayName,
    required this.total,
    required this.count,
  });

  final String clientId;
  final String displayName;
  final double total;
  final int count;
}

class CompletedJobRow {
  const CompletedJobRow({
    required this.jobId,
    required this.estimateNumber,
    required this.clientName,
    required this.date,
    required this.duration,
    required this.income,
    required this.teamId,
  });

  final String jobId;
  final String estimateNumber;
  final String clientName;
  final DateTime date;
  final Duration? duration;
  final double income;
  final String? teamId;
}

class EmployeePayoutRow {
  const EmployeePayoutRow({
    required this.employeeId,
    required this.name,
    required this.hours,
    required this.rate,
    required this.payout,
  });

  final String employeeId;
  final String name;
  final double hours;
  final double rate;
  final double payout;
}

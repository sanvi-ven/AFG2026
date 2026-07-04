import 'package:intl/intl.dart';

import '../../models/client_profile.dart';
import '../../models/estimate.dart';
import '../../models/invoice.dart';
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

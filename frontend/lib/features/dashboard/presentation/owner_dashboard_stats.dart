import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/broken_report_service.dart';
import '../../../core/services/equipment_service.dart';
import '../../../core/services/estimate_service.dart';
import '../../../core/services/invoice_service.dart';
import '../../../core/services/message_service.dart';
import '../../../core/services/reminder_check_service.dart';
import '../../../core/services/reporting_service.dart';
import '../../../core/services/request_service.dart';
import '../../../core/services/scheduled_work_service.dart';
import '../../../core/services/time_entry_service.dart';
import '../../../models/invoice.dart';

/// a snapshot counts as "ready to render" once it has either real data or a
/// terminal error — only the initial-connection wait should show a spinner.
extension _SnapshotReady<T> on AsyncSnapshot<T> {
  bool get isReady => hasData || hasError;
}

/// owner-only "what needs attention right now" stat cards shown on the
/// Anchor/dashboard home screen. Each card is its own live Firestore stream
/// and doubles as a link into the relevant section — there's no separate
/// quick-link menu anymore.
class OwnerDashboardStats extends StatelessWidget {
  const OwnerDashboardStats({required this.authToken, super.key});

  final String? authToken;

  void _open(BuildContext context, String route) {
    Navigator.pushNamed(
      context,
      route,
      arguments: {'role': 'owner', 'authToken': authToken},
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startOfWeek =
        DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 7));
    final dateFmt = DateFormat('yyyy-MM-dd');

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _requestsCard(context),
        _estimatesCard(context),
        _jobsCard(context, startOfWeek: startOfWeek, endOfWeek: endOfWeek),
        _equipmentCard(context),
        _invoicesCard(context),
        _messagesCard(context),
        _revenueCard(context, now: now),
        _payrollCard(context,
            startOfWeek: startOfWeek, endOfWeek: endOfWeek, dateFmt: dateFmt),
      ],
    );
  }

  Widget _requestsCard(BuildContext context) {
    return StreamBuilder(
      stream: RequestService.watchAllRequests(),
      builder: (context, snapshot) {
        final pending = (snapshot.data ?? const []).where((r) => r.isNew).length;
        return _StatCard(
          icon: Icons.inbox_outlined,
          label: 'Pending requests',
          value: snapshot.isReady ? '$pending' : null,
          onTap: () => _open(context, AppRouter.requests),
        );
      },
    );
  }

  Widget _estimatesCard(BuildContext context) {
    return StreamBuilder(
      stream: EstimateService.watchEstimates(role: 'owner'),
      builder: (context, snapshot) {
        final estimates = snapshot.data ?? const [];
        final awaitingAction = estimates.where((e) => e.isPending).length;
        final needsScheduling =
            estimates.where((e) => e.isApproved && !e.isScheduled).length;
        return _StatCard(
          icon: Icons.request_quote_outlined,
          label: 'Estimates needing action',
          value: snapshot.isReady ? '$awaitingAction' : null,
          subtitle: snapshot.isReady ? '$needsScheduling need scheduling' : null,
          onTap: () => _open(context, AppRouter.estimates),
        );
      },
    );
  }

  Widget _jobsCard(
    BuildContext context, {
    required DateTime startOfWeek,
    required DateTime endOfWeek,
  }) {
    return StreamBuilder(
      stream: ScheduledWorkService.watchJobsForDay(day: DateTime.now(), role: 'owner'),
      builder: (context, todaySnapshot) {
        return StreamBuilder(
          stream: ScheduledWorkService.watchJobsForRange(
              start: startOfWeek, end: endOfWeek, role: 'owner'),
          builder: (context, weekSnapshot) {
            final ready = todaySnapshot.isReady && weekSnapshot.isReady;
            return _StatCard(
              icon: Icons.event_available_outlined,
              label: "Today's jobs",
              value: ready ? '${(todaySnapshot.data ?? const []).length}' : null,
              subtitle: ready
                  ? '${(weekSnapshot.data ?? const []).length} this week'
                  : null,
              onTap: () => _open(context, AppRouter.todaysRoute),
            );
          },
        );
      },
    );
  }

  Widget _equipmentCard(BuildContext context) {
    return StreamBuilder(
      stream: EquipmentService.watchAll(),
      builder: (context, itemsSnapshot) {
        return StreamBuilder(
          stream: BrokenReportService.watchOpenReports(),
          builder: (context, reportsSnapshot) {
            final lowStock =
                (itemsSnapshot.data ?? const []).where((item) => item.isLowStock).length;
            final broken = reportsSnapshot.data?.length ?? 0;
            final ready = itemsSnapshot.isReady && reportsSnapshot.isReady;
            return _StatCard(
              icon: Icons.build_outlined,
              label: 'Equipment alerts',
              value: ready ? '${lowStock + broken}' : null,
              subtitle: ready ? '$lowStock low stock · $broken broken' : null,
              onTap: () => _open(context, AppRouter.equipmentCatalog),
            );
          },
        );
      },
    );
  }

  Widget _invoicesCard(BuildContext context) {
    return StreamBuilder(
      stream: InvoiceService.watchInvoices(role: 'owner'),
      builder: (context, snapshot) {
        final invoices = snapshot.data ?? const [];
        final unpaid = invoices.where((i) => i.status != InvoiceStatus.paid);
        final unpaidTotal = unpaid.fold<double>(0, (sum, i) => sum + i.total);
        final overdue = invoices.where(ReminderCheckService.isInvoiceOverdue).length;
        return _StatCard(
          icon: Icons.receipt_long_outlined,
          label: 'Unpaid invoices',
          value: snapshot.isReady
              ? '\$${unpaidTotal.toStringAsFixed(0)}'
              : null,
          subtitle: snapshot.isReady ? '$overdue overdue' : null,
          onTap: () => _open(context, AppRouter.invoices),
        );
      },
    );
  }

  Widget _messagesCard(BuildContext context) {
    return StreamBuilder(
      stream: MessageService.watchClientThreads(),
      builder: (context, snapshot) {
        final unread = (snapshot.data ?? const [])
            .fold<int>(0, (sum, thread) => sum + thread.unreadFromClientCount);
        return _StatCard(
          icon: Icons.mark_chat_unread_outlined,
          label: 'Unread messages',
          value: snapshot.isReady ? '$unread' : null,
          onTap: () => _open(context, AppRouter.messages),
        );
      },
    );
  }

  Widget _revenueCard(BuildContext context, {required DateTime now}) {
    return StreamBuilder(
      stream: InvoiceService.watchInvoices(role: 'owner'),
      builder: (context, snapshot) {
        final byMonth =
            ReportingService.paidRevenueByMonth(snapshot.data ?? const []);
        final key = DateFormat('yyyy-MM').format(now);
        final revenue = byMonth[key] ?? 0;
        return _StatCard(
          icon: Icons.trending_up_outlined,
          label: 'Revenue this month',
          value: snapshot.isReady ? '\$${revenue.toStringAsFixed(0)}' : null,
          onTap: () => _open(context, AppRouter.reports),
        );
      },
    );
  }

  Widget _payrollCard(
    BuildContext context, {
    required DateTime startOfWeek,
    required DateTime endOfWeek,
    required DateFormat dateFmt,
  }) {
    return StreamBuilder(
      stream: TimeEntryService.watchEntriesInRange(
        dateFmt.format(startOfWeek),
        dateFmt.format(endOfWeek.subtract(const Duration(days: 1))),
      ),
      builder: (context, snapshot) {
        final byEmployee =
            ReportingService.employeeHoursByEmployee(snapshot.data ?? const []);
        final totalHours = byEmployee.values
            .fold<Duration>(Duration.zero, (sum, d) => sum + d)
            .inMinutes /
            60.0;
        return _StatCard(
          icon: Icons.schedule_outlined,
          label: 'Hours this week',
          value: snapshot.isReady ? totalHours.toStringAsFixed(1) : null,
          onTap: () => _open(context, AppRouter.reports),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  /// null while the stream is still loading its first snapshot
  final String? value;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(label,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                value == null
                    ? const SizedBox(
                        height: 28,
                        width: 28,
                        child: Padding(
                          padding: EdgeInsets.all(4),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Text(value!,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/estimate_pdf_service.dart';
import '../../../core/services/estimate_service.dart';
import '../../../core/services/invoice_service.dart';
import '../../../core/services/scheduled_work_service.dart';
import '../../../core/state/client_session.dart';
import '../../../models/invoice.dart';
import '../../../models/scheduled_work.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/google_calendar_booking_button.dart';
import '../../../shared/widgets/google_calendar_widget.dart';

class AppointmentsPage extends StatefulWidget {
  const AppointmentsPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  @override
  State<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<AppointmentsPage> {
  static const String _calendarUrl =
      'https://calendar.google.com/calendar/embed?mode=WEEK&height=600&wkst=1&ctz=America%2FNew_York&showPrint=0&showTitle=0&showNav=1&showTabs=1&showCalendars=0&showTz=0&src=immc17289%40gmail.com&color=%23039BE5';

  static const String _schedulingUrl =
      'https://calendar.google.com/calendar/appointments/schedules/AcZssZ0vl6GyDUbhfZVYEi-NzQpylnetU7nK0p2b9fgeN4vv_SpQKa-NuMxTtvUVm5wNEeUPBtIYvfrW?gv=true';

  String? _completingWorkId;
  String? _convertingWorkId;
  String? _downloadingEstimatePdfWorkId;
  String? _markingPaidWorkId;

  Future<void> _openGoogleCalendar() async {
    const url = 'https://calendar.google.com/calendar/u/0/r/week';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _markComplete(ScheduledWork work) async {
    setState(() => _completingWorkId = work.id);
    try {
      await ScheduledWorkService.markCompleted(workId: work.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Work marked as complete.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to mark complete: $error')),
      );
    } finally {
      if (mounted) setState(() => _completingWorkId = null);
    }
  }

  Future<void> _convertToInvoice(ScheduledWork work) async {
    setState(() => _convertingWorkId = work.id);
    try {
      final ts = DateTime.now().millisecondsSinceEpoch.toString();
      final invoiceNumber = 'INV-${ts.substring(ts.length - 6)}';

      final invoiceId = await InvoiceService.createInvoiceFromEstimate(
        invoiceNumber: invoiceNumber,
        clientId: work.clientId,
        services: work.services,
        sourceEstimateId: work.estimateId,
      );
      await ScheduledWorkService.markInvoiced(workId: work.id, invoiceId: invoiceId);
      await EstimateService.markConverted(estimateId: work.estimateId, invoiceId: invoiceId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invoice $invoiceNumber created and sent to client.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to convert to invoice: $error')),
      );
    } finally {
      if (mounted) setState(() => _convertingWorkId = null);
    }
  }

  Future<void> _markInvoicePaid(ScheduledWork work) async {
    final invoiceId = work.invoiceId;
    if (invoiceId == null || invoiceId.isEmpty) return;
    setState(() => _markingPaidWorkId = work.id);
    try {
      await InvoiceService.updateStatus(invoiceId: invoiceId, status: InvoiceStatus.paid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice marked as paid.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to mark invoice as paid: $error')),
      );
    } finally {
      if (mounted) setState(() => _markingPaidWorkId = null);
    }
  }

  Future<void> _downloadEstimatePdf(ScheduledWork work) async {
    setState(() => _downloadingEstimatePdfWorkId = work.id);
    try {
      // Fetch the estimate to generate its PDF
      final estimateDoc = await EstimateService.fetchById(work.estimateId);
      if (!mounted) return;
      if (estimateDoc == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Estimate not found.')),
        );
        return;
      }
      final savedPath = await EstimatePdfService.generateAndDownloadEstimatePdf(estimate: estimateDoc);
      if (!mounted) return;
      final message = savedPath == null ? 'Estimate PDF downloaded.' : 'Estimate PDF saved: $savedPath';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to download estimate PDF: $error')),
      );
    } finally {
      if (mounted) setState(() => _downloadingEstimatePdfWorkId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ClientSession.profile.value;
    final clientId = profile?.signupId;

    return AppScaffold(
      title: 'Appointments',
      role: widget.role,
      authToken: widget.authToken,
      selectedRoute: '/appointments',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          Text('Upcoming & Past Work', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (widget.role == 'client' && (clientId == null || clientId.trim().isEmpty))
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Client ID not found. Please log in from the client email flow first.'),
              ),
            )
          else
            StreamBuilder<List<ScheduledWork>>(
              stream: ScheduledWorkService.watchScheduledWork(
                role: widget.role,
                clientId: clientId,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Failed to load scheduled work: ${snapshot.error}'),
                    ),
                  );
                }

                final items = snapshot.data ?? const <ScheduledWork>[];
                if (items.isEmpty) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        widget.role == 'owner'
                            ? 'No work scheduled yet. Approve an estimate and click "Schedule Work" to get started.'
                            : 'No upcoming work scheduled for you yet.',
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ScheduledWorkCard(
                          work: item,
                          role: widget.role,
                          isCompleting: _completingWorkId == item.id,
                          isConverting: _convertingWorkId == item.id,
                          isDownloadingPdf: _downloadingEstimatePdfWorkId == item.id,
                          isMarkingPaid: _markingPaidWorkId == item.id,
                          onMarkComplete: () => _markComplete(item),
                          onConvertToInvoice: () => _convertToInvoice(item),
                          onDownloadEstimatePdf: () => _downloadEstimatePdf(item),
                          onMarkPaid: () => _markInvoicePaid(item),
                        ),
                      ),
                  ],
                );
              },
            ),
          const SizedBox(height: 28),
          if (widget.role == 'client') ...[
            GoogleCalendarBookingButton(scheduleUrl: _schedulingUrl),
            const SizedBox(height: 24),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.role == 'client' ? 'Your Calendar' : 'Appointments Calendar',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (widget.role == 'owner')
                FilledButton.icon(
                  onPressed: _openGoogleCalendar,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open in Google'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const GoogleCalendarWidget(
            calendarSrc: _AppointmentsPageState._calendarUrl,
            height: 520,
          ),
        ],
      ),
    );
  }
}

class _ScheduledWorkCard extends StatefulWidget {
  const _ScheduledWorkCard({
    required this.work,
    required this.role,
    required this.isCompleting,
    required this.isConverting,
    required this.isDownloadingPdf,
    required this.isMarkingPaid,
    required this.onMarkComplete,
    required this.onConvertToInvoice,
    required this.onDownloadEstimatePdf,
    required this.onMarkPaid,
  });

  final ScheduledWork work;
  final String role;
  final bool isCompleting;
  final bool isConverting;
  final bool isDownloadingPdf;
  final bool isMarkingPaid;
  final VoidCallback onMarkComplete;
  final VoidCallback onConvertToInvoice;
  final VoidCallback onDownloadEstimatePdf;
  final VoidCallback onMarkPaid;

  @override
  State<_ScheduledWorkCard> createState() => _ScheduledWorkCardState();
}

class _ScheduledWorkCardState extends State<_ScheduledWorkCard> {
  // We stream the invoice status to show paid/unpaid in real time.
  Invoice? _invoice;
  bool _loadingInvoice = false;

  @override
  void initState() {
    super.initState();
    if (widget.work.isInvoiced && widget.work.invoiceId != null) {
      _loadInvoice();
    }
  }

  @override
  void didUpdateWidget(_ScheduledWorkCard old) {
    super.didUpdateWidget(old);
    final becameInvoiced = !old.work.isInvoiced && widget.work.isInvoiced;
    final invoiceChanged = old.work.invoiceId != widget.work.invoiceId;
    if ((becameInvoiced || invoiceChanged) && widget.work.invoiceId != null) {
      _loadInvoice();
    }
  }

  Future<void> _loadInvoice() async {
    final invoiceId = widget.work.invoiceId;
    if (invoiceId == null || invoiceId.isEmpty) return;
    setState(() => _loadingInvoice = true);
    try {
      final inv = await InvoiceService.getInvoiceById(invoiceId);
      if (mounted) setState(() => _invoice = inv);
    } finally {
      if (mounted) setState(() => _loadingInvoice = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final work = widget.work;
    final dateFormatter = DateFormat('MMM d, yyyy');
    final timeFormatter = DateFormat('h:mm a');
    final isPast = work.scheduledDate.isBefore(DateTime.now());

    final statusColor = switch (work.status) {
      ScheduledWorkStatus.completed => Colors.blue,
      ScheduledWorkStatus.invoiced => Colors.green,
      _ => isPast ? Colors.orange : Theme.of(context).colorScheme.primary,
    };
    final statusText = switch (work.status) {
      ScheduledWorkStatus.completed => 'Completed',
      ScheduledWorkStatus.invoiced => 'Invoiced',
      _ => isPast ? 'Past Due' : 'Scheduled',
    };

    final invoicePaid = _invoice?.status == InvoiceStatus.paid;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    work.estimateNumber,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 14),
                const SizedBox(width: 6),
                Text(dateFormatter.format(work.scheduledDate)),
                const SizedBox(width: 12),
                const Icon(Icons.access_time_outlined, size: 14),
                const SizedBox(width: 6),
                Text(timeFormatter.format(work.scheduledDate)),
              ],
            ),
            if (widget.role == 'owner') ...[
              const SizedBox(height: 4),
              Text('Client ID: ${work.clientId}'),
            ],
            const SizedBox(height: 10),
            Text('Services', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final item in work.services)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(item.name)),
                    Text('\$${item.price.toStringAsFixed(2)}'),
                  ],
                ),
              ),
            const Divider(height: 16),
            Row(
              children: [
                const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w700))),
                Text('\$${work.total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            // Invoice paid status (visible to both roles when invoiced)
            if (work.isInvoiced) ...[
              const SizedBox(height: 8),
              if (_loadingInvoice)
                const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              else
                Row(
                  children: [
                    Icon(
                      invoicePaid ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 16,
                      color: invoicePaid ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      invoicePaid ? 'Invoice paid' : 'Invoice not yet paid',
                      style: TextStyle(
                        color: invoicePaid ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
            ],
            const SizedBox(height: 12),
            // Download estimate PDF (both roles)
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: widget.isDownloadingPdf ? null : widget.onDownloadEstimatePdf,
                  icon: widget.isDownloadingPdf
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download_outlined),
                  label: const Text('Download Estimate'),
                ),
                // Owner-only actions
                if (widget.role == 'owner') ...[
                  if (work.isScheduled)
                    FilledButton.icon(
                      onPressed: widget.isCompleting ? null : widget.onMarkComplete,
                      icon: widget.isCompleting
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check_circle_outline),
                      label: const Text('Mark Complete'),
                    ),
                  if (work.isCompleted)
                    FilledButton.icon(
                      onPressed: widget.isConverting ? null : widget.onConvertToInvoice,
                      icon: widget.isConverting
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.swap_horiz),
                      label: const Text('Convert to Invoice'),
                    ),
                  if (work.isInvoiced && !invoicePaid)
                    OutlinedButton.icon(
                      onPressed: widget.isMarkingPaid ? null : widget.onMarkPaid,
                      icon: widget.isMarkingPaid
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.payments_outlined),
                      label: const Text('Mark as Paid'),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

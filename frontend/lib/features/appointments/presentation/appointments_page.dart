///made with the help of chatgpt 4.0, prompt: Help me build a Flutter template appointments page for a business management app that integrates Google Calendar scheduling
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/client_profile_service.dart';
import '../../../core/services/employee_profile_service.dart';
import '../../../core/services/estimate_pdf_service.dart';
import '../../../core/services/estimate_service.dart';
import '../../../core/services/invoice_service.dart';
import '../../../core/services/scheduled_work_service.dart';
import '../../../core/services/team_service.dart';
import '../../../core/state/client_session.dart';
import '../../../models/client_profile.dart';
import '../../../models/employee_profile.dart';
import '../../../models/invoice.dart';
import '../../../models/scheduled_work.dart';
import '../../../models/team.dart';
import '../../../shared/utils/list_highlight_controller.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/google_calendar_booking_button.dart';
import '../../../shared/widgets/google_calendar_widget.dart';
import '../../../shared/widgets/sort_control.dart';

/// page for managing appointments, scheduled work, and calendar bookings
class AppointmentsPage extends StatefulWidget {
  const AppointmentsPage(
      {required this.role, this.authToken, this.highlightId, super.key});

  final String role;
  final String? authToken;
  final String? highlightId;

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
  String? _archivingWorkId;
  String? _deletingWorkId;
  String? _reschedulingWorkId;
  ListSortMode _sortMode = ListSortMode.newestFirst;
  late final ListHighlightController _highlight =
      ListHighlightController(widget.highlightId);

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
      final invoiceNumber = work.estimateNumber;
      final sourceEstimate = await EstimateService.fetchById(work.estimateId);

      final invoiceId = await InvoiceService.createInvoiceFromEstimate(
        invoiceNumber: invoiceNumber,
        clientId: work.clientId,
        services: work.services,
        sourceEstimateId: work.estimateId,
        notes: sourceEstimate?.notes ?? '',
        terms: sourceEstimate?.terms ?? '',
      );
      await ScheduledWorkService.markInvoiced(
          workId: work.id, invoiceId: invoiceId);
      await EstimateService.markConverted(
          estimateId: work.estimateId, invoiceId: invoiceId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Invoice $invoiceNumber created and sent to client.')),
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
      await InvoiceService.updateStatus(
          invoiceId: invoiceId, status: InvoiceStatus.paid);
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

  Future<void> _archiveWork(ScheduledWork work) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Archive Appointment'),
        content: Text(
          'Archive this job (${work.estimateNumber})? It will be moved to your archived section.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Archive')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _archivingWorkId = work.id);
    try {
      await ScheduledWorkService.archiveWork(work.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to archive job: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _archivingWorkId = null);
    }
  }

  Future<void> _deleteWorkPermanently(ScheduledWork work) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Job Permanently'),
        content:
            const Text("Permanently delete this job? This can't be undone."),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingWorkId = work.id);
    try {
      await ScheduledWorkService.deleteWorkPermanently(work.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(error.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingWorkId = null);
    }
  }

  Future<void> _rescheduleWork(ScheduledWork work) async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: work.scheduledDate.isAfter(DateTime.now())
          ? work.scheduledDate
          : DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(work.scheduledDate),
    );
    if (pickedTime == null || !mounted) return;

    final newDate = DateTime(pickedDate.year, pickedDate.month, pickedDate.day,
        pickedTime.hour, pickedTime.minute);

    setState(() => _reschedulingWorkId = work.id);
    try {
      await ScheduledWorkService.rescheduleWork(
          workId: work.id, newDate: newDate);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Rescheduled to ${DateFormat('MMM d, yyyy · h:mm a').format(newDate)}.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reschedule: $error')),
      );
    } finally {
      if (mounted) setState(() => _reschedulingWorkId = null);
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
      final savedPath = await EstimatePdfService.generateAndDownloadEstimatePdf(
          estimate: estimateDoc);
      if (!mounted) return;
      final message = savedPath == null
          ? 'Estimate PDF downloaded.'
          : 'Estimate PDF saved: $savedPath';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to download estimate PDF: $error')),
      );
    } finally {
      if (mounted) setState(() => _downloadingEstimatePdfWorkId = null);
    }
  }

  void _viewEstimate(ScheduledWork work) {
    Navigator.pushNamed(
      context,
      AppRouter.estimates,
      arguments: {
        'role': widget.role,
        'authToken': widget.authToken,
        'highlightId': work.estimateId
      },
    );
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
          Text('Upcoming & Past Work',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (widget.role == 'client' &&
              (clientId == null || clientId.trim().isEmpty))
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'Client ID not found. Please log in from the client email flow first.'),
              ),
            )
          else
            StreamBuilder<List<Team>>(
              stream: widget.role == 'owner'
                  ? TeamService.watchAllTeams()
                  : const Stream.empty(),
              builder: (context, teamsSnapshot) {
                final teams = teamsSnapshot.data ?? const <Team>[];

                return StreamBuilder<List<EmployeeProfile>>(
                  stream: widget.role == 'owner'
                      ? EmployeeProfileService.watchAllProfiles()
                      : const Stream.empty(),
                  builder: (context, employeesSnapshot) {
                    final employees =
                        employeesSnapshot.data ?? const <EmployeeProfile>[];

                    return StreamBuilder<List<ClientProfile>>(
                      // owner needs the full directory for "sort by client"
                      // names; a client session only ever needs its own name,
                      // and doesn't have access to read the rest once
                      // Firestore rules are scoped by role.
                      stream: widget.role == 'owner'
                          ? ClientProfileService.watchAllProfiles()
                          : Stream.value(
                              profile != null ? [profile] : const <ClientProfile>[]),
                      builder: (context, clientsSnapshot) {
                        final clients =
                            clientsSnapshot.data ?? const <ClientProfile>[];

                        return StreamBuilder<List<ScheduledWork>>(
                          stream: ScheduledWorkService.watchScheduledWork(
                            role: widget.role,
                            clientId: clientId,
                          ),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }
                            if (snapshot.hasError) {
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                      'Failed to load scheduled work: ${snapshot.error}'),
                                ),
                              );
                            }

                            final items =
                                snapshot.data ?? const <ScheduledWork>[];
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

                            final sorted = [...items];
                            switch (_sortMode) {
                              case ListSortMode.newestFirst:
                                sorted.sort((a, b) =>
                                    b.scheduledDate.compareTo(a.scheduledDate));
                                break;
                              case ListSortMode.oldestFirst:
                                sorted.sort((a, b) =>
                                    a.scheduledDate.compareTo(b.scheduledDate));
                                break;
                              case ListSortMode.client:
                                sorted.sort((a, b) =>
                                    ClientProfileService.displayNameFor(
                                            clients, a.clientId)
                                        .toLowerCase()
                                        .compareTo(
                                            ClientProfileService.displayNameFor(
                                                    clients, b.clientId)
                                                .toLowerCase()));
                                break;
                            }

                            _highlight.maybeScrollTo(
                              sorted.map((e) => e.id).toList(),
                              () {
                                if (mounted) setState(() {});
                              },
                            );

                            final active = sorted
                                .where((item) => !item.isArchived)
                                .toList();
                            final archived = sorted
                                .where((item) => item.isArchived)
                                .toList();

                            Widget workCard(ScheduledWork item) => KeyedSubtree(
                                  key: _highlight.keyFor(item.id),
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _ScheduledWorkCard(
                                      work: item,
                                      role: widget.role,
                                      teams: teams,
                                      employees: employees,
                                      isHighlighted:
                                          _highlight.isHighlighted(item.id),
                                      isCompleting:
                                          _completingWorkId == item.id,
                                      isConverting:
                                          _convertingWorkId == item.id,
                                      isDownloadingPdf:
                                          _downloadingEstimatePdfWorkId ==
                                              item.id,
                                      isMarkingPaid:
                                          _markingPaidWorkId == item.id,
                                      isArchiving: _archivingWorkId == item.id,
                                      isDeleting: _deletingWorkId == item.id,
                                      isRescheduling:
                                          _reschedulingWorkId == item.id,
                                      onMarkComplete: () => _markComplete(item),
                                      onConvertToInvoice: () =>
                                          _convertToInvoice(item),
                                      onDownloadEstimatePdf: () =>
                                          _downloadEstimatePdf(item),
                                      onMarkPaid: () => _markInvoicePaid(item),
                                      onViewEstimate: () => _viewEstimate(item),
                                      onArchive: widget.role == 'owner'
                                          ? () => _archiveWork(item)
                                          : null,
                                      onDeletePermanently: widget.role ==
                                              'owner'
                                          ? () => _deleteWorkPermanently(item)
                                          : null,
                                      onReschedule: widget.role == 'owner'
                                          ? () => _rescheduleWork(item)
                                          : null,
                                    ),
                                  ),
                                );

                            return Column(
                              children: [
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: SortControl(
                                    value: _sortMode,
                                    onChanged: (mode) =>
                                        setState(() => _sortMode = mode),
                                  ),
                                ),
                                for (final item in active) workCard(item),
                                if (widget.role == 'owner' &&
                                    archived.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  ExpansionTile(
                                    title: Text(
                                      'Archived (${archived.length})',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .outline),
                                    ),
                                    tilePadding: const EdgeInsets.symmetric(
                                        horizontal: 4),
                                    childrenPadding: EdgeInsets.zero,
                                    children: [
                                      for (final item in archived)
                                        workCard(item),
                                    ],
                                  ),
                                ],
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
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
                widget.role == 'client'
                    ? 'Your Calendar'
                    : 'Appointments Calendar',
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
    required this.teams,
    required this.employees,
    required this.isHighlighted,
    required this.isCompleting,
    required this.isConverting,
    required this.isDownloadingPdf,
    required this.isMarkingPaid,
    required this.isArchiving,
    required this.isDeleting,
    required this.isRescheduling,
    required this.onMarkComplete,
    required this.onConvertToInvoice,
    required this.onDownloadEstimatePdf,
    required this.onMarkPaid,
    required this.onViewEstimate,
    this.onArchive,
    this.onDeletePermanently,
    this.onReschedule,
  });

  final ScheduledWork work;
  final String role;
  final List<Team> teams;
  final List<EmployeeProfile> employees;
  final bool isHighlighted;
  final bool isCompleting;
  final bool isConverting;
  final bool isDownloadingPdf;
  final bool isMarkingPaid;
  final bool isArchiving;
  final bool isDeleting;
  final bool isRescheduling;
  final VoidCallback onMarkComplete;
  final VoidCallback onConvertToInvoice;
  final VoidCallback onDownloadEstimatePdf;
  final VoidCallback onMarkPaid;
  final VoidCallback onViewEstimate;
  final VoidCallback? onArchive;
  final VoidCallback? onDeletePermanently;
  final VoidCallback? onReschedule;

  @override
  State<_ScheduledWorkCard> createState() => _ScheduledWorkCardState();
}

class _ScheduledWorkCardState extends State<_ScheduledWorkCard> {
  // We stream the invoice status to show paid/unpaid in real time.
  Invoice? _invoice;
  bool _loadingInvoice = false;
  late bool _assignToEmployees = widget.work.employeeIds.isNotEmpty;

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

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: widget.isHighlighted
            ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
            : null,
      ),
      child: Card(
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
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                          color: statusColor, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (work.recurringGroupId != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text('Recurring',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 12)),
                    ),
                  ],
                  if (!work.isArchived && widget.onArchive != null) ...[
                    const SizedBox(width: 4),
                    widget.isArchiving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : IconButton(
                            onPressed: widget.onArchive,
                            icon: const Icon(Icons.archive_outlined),
                            tooltip: 'Archive job',
                            color: Theme.of(context).colorScheme.outline,
                            iconSize: 20,
                          ),
                  ] else if (work.isArchived &&
                      widget.onDeletePermanently != null) ...[
                    const SizedBox(width: 4),
                    widget.isDeleting
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : IconButton(
                            onPressed: widget.onDeletePermanently,
                            icon: const Icon(Icons.delete_forever_outlined),
                            tooltip: 'Delete permanently',
                            color: Theme.of(context).colorScheme.error,
                            iconSize: 20,
                          ),
                  ],
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
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                        value: false,
                        label: Text('Team'),
                        icon: Icon(Icons.groups_outlined)),
                    ButtonSegment(
                        value: true,
                        label: Text('Employees'),
                        icon: Icon(Icons.person_outlined)),
                  ],
                  selected: {_assignToEmployees},
                  onSelectionChanged: (selection) =>
                      setState(() => _assignToEmployees = selection.first),
                ),
                const SizedBox(height: 8),
                if (_assignToEmployees)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final employee in widget.employees)
                        FilterChip(
                          label: Text(employee.fullName),
                          selected:
                              work.employeeIds.contains(employee.employeeId),
                          onSelected: (selected) {
                            final updated = [...work.employeeIds];
                            if (selected) {
                              updated.add(employee.employeeId);
                            } else {
                              updated.remove(employee.employeeId);
                            }
                            ScheduledWorkService.assignEmployees(
                                workId: work.id, employeeIds: updated);
                          },
                        ),
                    ],
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: work.teamId,
                    decoration: const InputDecoration(
                        labelText: 'Assigned team',
                        border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<String>(
                          value: null, child: Text('Unassigned')),
                      for (final team in widget.teams)
                        DropdownMenuItem<String>(
                            value: team.id, child: Text(team.name)),
                    ],
                    onChanged: (value) => ScheduledWorkService.assignTeam(
                        workId: work.id, teamId: value),
                  ),
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
                  const Expanded(
                      child: Text('Total',
                          style: TextStyle(fontWeight: FontWeight.w700))),
                  Text('\$${work.total.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              // Invoice paid status (visible to both roles when invoiced)
              if (work.isInvoiced) ...[
                const SizedBox(height: 8),
                if (_loadingInvoice)
                  const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Row(
                    children: [
                      Icon(
                        invoicePaid
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
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
                    onPressed: widget.isDownloadingPdf
                        ? null
                        : widget.onDownloadEstimatePdf,
                    icon: widget.isDownloadingPdf
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download_outlined),
                    label: const Text('Download Estimate'),
                  ),
                  OutlinedButton.icon(
                    onPressed: widget.onViewEstimate,
                    icon: const Icon(Icons.request_quote_outlined),
                    label: const Text('View Original Estimate'),
                  ),
                  // Owner-only actions
                  if (widget.role == 'owner') ...[
                    if (work.isScheduled)
                      FilledButton.icon(
                        onPressed:
                            widget.isCompleting ? null : widget.onMarkComplete,
                        icon: widget.isCompleting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.check_circle_outline),
                        label: const Text('Mark Complete'),
                      ),
                    if (work.isCompleted)
                      FilledButton.icon(
                        onPressed: widget.isConverting
                            ? null
                            : widget.onConvertToInvoice,
                        icon: widget.isConverting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.swap_horiz),
                        label: const Text('Convert to Invoice'),
                      ),
                    if (work.isInvoiced && !invoicePaid)
                      OutlinedButton.icon(
                        onPressed:
                            widget.isMarkingPaid ? null : widget.onMarkPaid,
                        icon: widget.isMarkingPaid
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.payments_outlined),
                        label: const Text('Mark as Paid'),
                      ),
                    if (widget.onReschedule != null)
                      OutlinedButton.icon(
                        onPressed:
                            widget.isRescheduling ? null : widget.onReschedule,
                        icon: widget.isRescheduling
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.edit_calendar_outlined),
                        label: const Text('Reschedule'),
                      ),
                    if (work.recurringGroupId != null)
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _SeriesDetailPage(
                              recurringGroupId: work.recurringGroupId!,
                              estimateNumber: work.estimateNumber,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.event_repeat_outlined),
                        label: const Text('Manage Series'),
                      ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// owner-only view of every job in one recurring series, with a bulk
/// "cancel remaining occurrences" action and per-job archive
class _SeriesDetailPage extends StatefulWidget {
  const _SeriesDetailPage(
      {required this.recurringGroupId, required this.estimateNumber});

  final String recurringGroupId;
  final String estimateNumber;

  @override
  State<_SeriesDetailPage> createState() => _SeriesDetailPageState();
}

class _SeriesDetailPageState extends State<_SeriesDetailPage> {
  bool _isCancelling = false;
  String? _archivingWorkId;

  Future<void> _cancelRemaining() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel Remaining Occurrences'),
        content: const Text(
          "Cancel all upcoming, not-yet-completed jobs in this series? This can't be undone.",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Back')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isCancelling = true);
    try {
      final count = await ScheduledWorkService.cancelRemainingInSeries(
          widget.recurringGroupId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count upcoming job(s) cancelled.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to cancel remaining occurrences: $error')),
      );
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  Future<void> _archiveJob(ScheduledWork work) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Archive Job'),
        content: Text(
            'Archive the job on ${DateFormat('MMM d, yyyy · h:mm a').format(work.scheduledDate)}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Archive')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _archivingWorkId = work.id);
    try {
      await ScheduledWorkService.archiveWork(work.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to archive job: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _archivingWorkId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: Text('${widget.estimateNumber} — Recurring Series')),
      body: StreamBuilder<List<ScheduledWork>>(
        stream: ScheduledWorkService.watchSeries(widget.recurringGroupId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final jobs = snapshot.data ?? const <ScheduledWork>[];
          if (jobs.isEmpty) {
            return const Center(child: Text('No jobs found for this series.'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FilledButton.icon(
                onPressed: _isCancelling ? null : _cancelRemaining,
                icon: _isCancelling
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.event_busy_outlined),
                label: const Text('Cancel Remaining Occurrences'),
              ),
              const SizedBox(height: 16),
              for (final work in jobs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SeriesJobRow(
                    work: work,
                    isArchiving: _archivingWorkId == work.id,
                    onArchive: work.isArchived ? null : () => _archiveJob(work),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SeriesJobRow extends StatelessWidget {
  const _SeriesJobRow(
      {required this.work, required this.isArchiving, this.onArchive});

  final ScheduledWork work;
  final bool isArchiving;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (work.status) {
      ScheduledWorkStatus.completed => Colors.blue,
      ScheduledWorkStatus.invoiced => Colors.green,
      _ => Theme.of(context).colorScheme.primary,
    };
    final statusText = switch (work.status) {
      ScheduledWorkStatus.completed => 'Completed',
      ScheduledWorkStatus.invoiced => 'Invoiced',
      _ => 'Scheduled',
    };

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        title:
            Text(DateFormat('MMM d, yyyy · h:mm a').format(work.scheduledDate)),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(statusText,
                  style: TextStyle(
                      color: statusColor, fontWeight: FontWeight.w700)),
            ),
            if (work.isArchived) ...[
              const SizedBox(width: 8),
              Text('Archived', style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
        trailing: onArchive == null
            ? null
            : isArchiving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    onPressed: onArchive,
                    icon: const Icon(Icons.archive_outlined),
                    tooltip: 'Archive job',
                  ),
      ),
    );
  }
}

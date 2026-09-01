import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/client_profile_service.dart';
import '../../../core/services/employee_profile_service.dart';
import '../../../core/services/invite_code_service.dart';
import '../../../core/services/job_completion_service.dart';
import '../../../core/services/reporting_service.dart';
import '../../../core/services/scheduled_work_service.dart';
import '../../../core/services/team_service.dart';
import '../../../core/services/time_entry_service.dart';
import '../../../models/client_profile.dart';
import '../../../models/employee_profile.dart';
import '../../../models/invite_code.dart';
import '../../../models/job_completion_form.dart';
import '../../../models/scheduled_work.dart';
import '../../../models/team.dart';
import '../../../models/time_entry.dart';
import '../../../shared/utils/time_entry_pay_format.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/csv_export_buttons.dart';

/// owner-only admin hub: employee roster, teams, invite codes,
/// submitted job completion reports, and time entry review
class TeamAdminPage extends StatelessWidget {
  const TeamAdminPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  @override
  Widget build(BuildContext context) {
    if (role != 'owner') {
      return const SizedBox.shrink();
    }
    return DefaultTabController(
      length: 5,
      child: AppScaffold(
        title: 'Team',
        role: role,
        authToken: authToken,
        selectedRoute: AppRouter.teamAdmin,
        body: Column(
          children: [
            const Material(
              color: Colors.transparent,
              child: TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: 'Employees'),
                  Tab(text: 'Teams'),
                  Tab(text: 'Invite Codes'),
                  Tab(text: 'Job Completions'),
                  Tab(text: 'Time Entries'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  const _EmployeesTab(),
                  const _TeamsTab(),
                  const _InviteCodesTab(),
                  _JobCompletionsTab(role: role, authToken: authToken),
                  const _TimeEntriesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmployeesTab extends StatelessWidget {
  const _EmployeesTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<EmployeeProfile>>(
      stream: EmployeeProfileService.watchAllProfiles(),
      builder: (context, employeeSnapshot) {
        final employees = employeeSnapshot.data ?? const <EmployeeProfile>[];

        return StreamBuilder<List<Team>>(
          stream: TeamService.watchAllTeams(),
          builder: (context, teamSnapshot) {
            final teams = teamSnapshot.data ?? const <Team>[];

            if (employees.isEmpty) {
              return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No employees yet. Share an invite code to get started.')));
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: employees.length,
              itemBuilder: (context, index) {
                final employee = employees[index];
                final currentTeam = teams.where((t) => t.id == employee.teamId).toList();

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(employee.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            Switch(
                              value: employee.active,
                              onChanged: (value) => EmployeeProfileService.setActive(employee.employeeId, value),
                            ),
                          ],
                        ),
                        Text(employee.email, style: Theme.of(context).textTheme.bodySmall),
                        Text(employee.phoneNumber, style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: currentTeam.isEmpty ? null : currentTeam.first.id,
                          decoration: const InputDecoration(labelText: 'Team', border: OutlineInputBorder()),
                          items: [
                            const DropdownMenuItem<String>(value: null, child: Text('Unassigned')),
                            for (final team in teams) DropdownMenuItem<String>(value: team.id, child: Text(team.name)),
                          ],
                          onChanged: (value) => EmployeeProfileService.assignTeam(employee.employeeId, value),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: ValueKey('rate-${employee.employeeId}'),
                          initialValue: employee.hourlyRate?.toStringAsFixed(2) ?? '',
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Hourly rate (\$)', border: OutlineInputBorder()),
                          onFieldSubmitted: (value) => EmployeeProfileService.setHourlyRate(
                            employee.employeeId,
                            double.tryParse(value.trim()),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _TeamsTab extends StatefulWidget {
  const _TeamsTab();

  @override
  State<_TeamsTab> createState() => _TeamsTabState();
}

class _TeamsTabState extends State<_TeamsTab> {
  final _newTeamController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _newTeamController.dispose();
    super.dispose();
  }

  Future<void> _createTeam() async {
    final name = _newTeamController.text.trim();
    if (name.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      await TeamService.createTeam(name);
      _newTeamController.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _renameTeam(Team team) async {
    final controller = TextEditingController(text: team.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename team'),
        content: TextField(controller: controller, decoration: const InputDecoration(border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (newName == null || newName.trim().isEmpty) return;
    await TeamService.renameTeam(team.id, newName);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newTeamController,
                    decoration: const InputDecoration(labelText: 'New team name', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _isSaving ? null : _createTeam,
                  child: const Text('Create'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        StreamBuilder<List<Team>>(
          stream: TeamService.watchAllTeams(),
          builder: (context, snapshot) {
            final teams = snapshot.data ?? const <Team>[];
            if (teams.isEmpty) {
              return const Padding(padding: EdgeInsets.all(12), child: Text('No teams yet.'));
            }
            return Column(
              children: [
                for (final team in teams)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(team.name),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _renameTeam(team),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _InviteCodesTab extends StatefulWidget {
  const _InviteCodesTab();

  @override
  State<_InviteCodesTab> createState() => _InviteCodesTabState();
}

class _InviteCodesTabState extends State<_InviteCodesTab> {
  final _codeController = TextEditingController();
  final _labelController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _codeController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_codeController.text.trim().isEmpty) return;
    setState(() => _isSaving = true);
    try {
      await InviteCodeService.generate(_codeController.text, label: _labelController.text);
      _codeController.clear();
      _labelController.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmDelete(InviteCode code) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Invite Code'),
        content: Text(
          "Delete ${code.code}? This can't be undone and the code will stop working immediately.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await InviteCodeService.deleteCode(code.code);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Code (e.g. CREW2026)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _labelController,
                  decoration: const InputDecoration(labelText: 'Label (optional)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: _isSaving ? null : _generate,
                  child: const Text('Generate code'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        StreamBuilder<List<InviteCode>>(
          stream: InviteCodeService.watchAll(),
          builder: (context, snapshot) {
            final codes = snapshot.data ?? const <InviteCode>[];
            if (codes.isEmpty) {
              return const Padding(padding: EdgeInsets.all(12), child: Text('No invite codes yet.'));
            }
            return Column(
              children: [
                for (final code in codes)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(code.code),
                      subtitle: Text(code.label.isEmpty ? 'No label' : code.label),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Delete invite code',
                        onPressed: () => _confirmDelete(code),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _JobCompletionsTab extends StatelessWidget {
  const _JobCompletionsTab({required this.role, this.authToken});

  final String role;
  final String? authToken;

  void _viewInAppointments(BuildContext context, String workId) {
    Navigator.pushNamed(
      context,
      AppRouter.appointments,
      arguments: {'role': role, 'authToken': authToken, 'highlightId': workId},
    );
  }

  void _viewInvoice(BuildContext context, String invoiceId) {
    Navigator.pushNamed(
      context,
      AppRouter.invoices,
      arguments: {'role': role, 'authToken': authToken, 'highlightId': invoiceId},
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<JobCompletionForm>>(
      stream: JobCompletionService.watchAllForms(),
      builder: (context, formsSnapshot) {
        final forms = formsSnapshot.data ?? const <JobCompletionForm>[];
        if (forms.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No job completion reports submitted yet.'),
          );
        }

        return StreamBuilder<List<ScheduledWork>>(
          stream: ScheduledWorkService.watchScheduledWork(role: 'owner'),
          builder: (context, jobsSnapshot) {
            final jobsById = {
              for (final job in jobsSnapshot.data ?? const <ScheduledWork>[]) job.id: job,
            };

            return StreamBuilder<List<ClientProfile>>(
              stream: ClientProfileService.watchAllProfiles(),
              builder: (context, clientsSnapshot) {
                final clients = clientsSnapshot.data ?? const <ClientProfile>[];

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final form in forms)
                      Builder(builder: (context) {
                        final job = jobsById[form.workId];
                        final descriptor = job == null
                            ? 'Job ${form.workId}'
                            : '${ClientProfileService.displayNameFor(clients, job.clientId)} — Est #${job.estimateNumber}';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(descriptor, style: const TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                if (job != null)
                                  Text('Scheduled: ${DateFormat('MMM d, yyyy').format(job.scheduledDate)}'),
                                Text('Submitted by: ${form.submittedByName}'),
                                Text('${DateFormat('MMM d, h:mm a').format(form.startTime)} – ${DateFormat('h:mm a').format(form.endTime)}'),
                                if (form.notes.isNotEmpty) Text('Notes: ${form.notes}'),
                                if (form.beforePhotoUrls.isNotEmpty || form.afterPhotoUrls.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      for (final url in [...form.beforePhotoUrls, ...form.afterPhotoUrls])
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: Image.network(url, width: 56, height: 56, fit: BoxFit.cover),
                                        ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () => _viewInAppointments(context, form.workId),
                                      icon: const Icon(Icons.event_outlined, size: 16),
                                      label: const Text('View in Appointments'),
                                    ),
                                    if (job?.invoiceId != null)
                                      OutlinedButton.icon(
                                        onPressed: () => _viewInvoice(context, job!.invoiceId!),
                                        icon: const Icon(Icons.receipt_long_outlined, size: 16),
                                        label: const Text('View Invoice'),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _TimeEntriesTab extends StatelessWidget {
  const _TimeEntriesTab();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startOfRange = now.subtract(const Duration(days: 30));
    final format = DateFormat('yyyy-MM-dd');

    return StreamBuilder<List<EmployeeProfile>>(
      stream: EmployeeProfileService.watchAllProfiles(),
      builder: (context, employeeSnapshot) {
        final employees = {
          for (final employee in employeeSnapshot.data ?? const <EmployeeProfile>[])
            employee.employeeId: employee,
        };

        return StreamBuilder<List<TimeEntry>>(
          stream: TimeEntryService.watchEntriesInRange(format.format(startOfRange), format.format(now)),
          builder: (context, snapshot) {
            final entries = snapshot.data ?? const <TimeEntry>[];
            if (entries.isEmpty) {
              return const Padding(padding: EdgeInsets.all(16), child: Text('No time entries in the last 30 days.'));
            }

            final exportRows = <List<Object?>>[
              ['Employee', 'Date', 'Clock In', 'Clock Out', 'Hours', 'Rate', 'Payout', 'Notes', 'Paid'],
              for (final entry in entries)
                [
                  employees[entry.employeeId]?.fullName ?? entry.employeeId,
                  entry.date,
                  entry.clockInAt,
                  entry.clockOutAt,
                  ReportingService.hoursForEntry(entry),
                  ReportingService.effectiveRateForEntry(entry, employees[entry.employeeId]),
                  ReportingService.payoutForEntry(entry, employees[entry.employeeId]),
                  entry.notes,
                  entry.isPaid ? 'Yes' : 'No',
                ],
            ];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: ExportButtons(rows: exportRows, fileNamePrefix: 'time_entries'),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                final entry = entries[index];
                final employee = employees[entry.employeeId];
                final subtitleLines = [
                  '${entry.date} · ${entry.clockInAt == null ? '—' : DateFormat('h:mm a').format(entry.clockInAt!)}'
                      ' – ${entry.clockOutAt == null ? 'in progress' : DateFormat('h:mm a').format(entry.clockOutAt!)}',
                  formatEntryPay(entry, employee),
                  if (entry.notes.isNotEmpty) entry.notes,
                ];

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => _EditTimeEntryDialog(entry: entry, employee: employee),
                    ),
                    title: Text(employee?.fullName ?? entry.employeeId),
                    subtitle: Text(subtitleLines.join('\n')),
                    isThreeLine: subtitleLines.length > 1,
                    trailing: entry.isPaid
                        ? const Chip(
                            avatar: Icon(Icons.check_circle, size: 16, color: Colors.green),
                            label: Text('Paid'),
                            visualDensity: VisualDensity.compact,
                          )
                        : null,
                  ),
                );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _EditTimeEntryDialog extends StatefulWidget {
  const _EditTimeEntryDialog({required this.entry, required this.employee});

  final TimeEntry entry;
  final EmployeeProfile? employee;

  @override
  State<_EditTimeEntryDialog> createState() => _EditTimeEntryDialogState();
}

class _EditTimeEntryDialogState extends State<_EditTimeEntryDialog> {
  late TimeOfDay? _clockIn =
      widget.entry.clockInAt == null ? null : TimeOfDay.fromDateTime(widget.entry.clockInAt!);
  late TimeOfDay? _clockOut =
      widget.entry.clockOutAt == null ? null : TimeOfDay.fromDateTime(widget.entry.clockOutAt!);
  late final _wageController =
      TextEditingController(text: widget.entry.wageOverride?.toStringAsFixed(2) ?? '');
  late final _notesController = TextEditingController(text: widget.entry.notes);
  late bool _isPaid = widget.entry.isPaid;
  bool _isSaving = false;

  @override
  void dispose() {
    _wageController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  DateTime? _dateTimeFor(TimeOfDay? time) {
    if (time == null) return null;
    final date = DateTime.tryParse(widget.entry.date) ?? DateTime.now();
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickTime({required bool isClockIn}) async {
    final initial = (isClockIn ? _clockIn : _clockOut) ?? TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      if (isClockIn) {
        _clockIn = picked;
      } else {
        _clockOut = picked;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await TimeEntryService.updateEntry(
        id: widget.entry.id,
        clockInAt: _dateTimeFor(_clockIn),
        clockOutAt: _dateTimeFor(_clockOut),
        wageOverride: double.tryParse(_wageController.text.trim()),
        notes: _notesController.text,
        isPaid: _isPaid,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shift updated.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update shift: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultRate = widget.employee?.hourlyRate;
    return AlertDialog(
      title: Text('Edit Shift — ${widget.employee?.fullName ?? widget.entry.employeeId}, ${widget.entry.date}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Clock in'),
              subtitle: Text(_clockIn?.format(context) ?? '—'),
              trailing: TextButton(onPressed: () => _pickTime(isClockIn: true), child: const Text('Edit')),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Clock out'),
              subtitle: Text(_clockOut?.format(context) ?? '—'),
              trailing: TextButton(onPressed: () => _pickTime(isClockIn: false), child: const Text('Edit')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _wageController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Hourly wage override',
                border: const OutlineInputBorder(),
                hintText: defaultRate == null
                    ? 'Leave blank — no default rate set'
                    : 'Leave blank to use \$${defaultRate.toStringAsFixed(2)}/hr',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder()),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _isPaid,
              onChanged: (value) => setState(() => _isPaid = value ?? false),
              title: const Text('Paid'),
              controlAffinity: ListTileControlAffinity.leading,
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

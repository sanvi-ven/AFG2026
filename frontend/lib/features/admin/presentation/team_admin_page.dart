import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/employee_profile_service.dart';
import '../../../core/services/invite_code_service.dart';
import '../../../core/services/job_completion_service.dart';
import '../../../core/services/team_service.dart';
import '../../../core/services/time_entry_service.dart';
import '../../../models/employee_profile.dart';
import '../../../models/invite_code.dart';
import '../../../models/job_completion_form.dart';
import '../../../models/team.dart';
import '../../../models/time_entry.dart';
import '../../../shared/widgets/app_scaffold.dart';

/// owner-only admin hub: employee roster, teams, invite codes,
/// submitted job completion reports, and time entry review
class TeamAdminPage extends StatelessWidget {
  const TeamAdminPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  @override
  Widget build(BuildContext context) {
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
            const Expanded(
              child: TabBarView(
                children: [
                  _EmployeesTab(),
                  _TeamsTab(),
                  _InviteCodesTab(),
                  _JobCompletionsTab(),
                  _TimeEntriesTab(),
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
                      trailing: Switch(
                        value: code.active,
                        onChanged: (value) => value
                            ? null
                            : InviteCodeService.deactivate(code.code),
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
  const _JobCompletionsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<JobCompletionForm>>(
      stream: JobCompletionService.watchAllForms(),
      builder: (context, snapshot) {
        final forms = snapshot.data ?? const <JobCompletionForm>[];
        if (forms.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No job completion reports submitted yet.'),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final form in forms)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Job ${form.workId}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
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
                    ],
                  ),
                ),
              ),
          ],
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
            employee.employeeId: employee.fullName,
        };

        return StreamBuilder<List<TimeEntry>>(
          stream: TimeEntryService.watchEntriesInRange(format.format(startOfRange), format.format(now)),
          builder: (context, snapshot) {
            final entries = snapshot.data ?? const <TimeEntry>[];
            if (entries.isEmpty) {
              return const Padding(padding: EdgeInsets.all(16), child: Text('No time entries in the last 30 days.'));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(employees[entry.employeeId] ?? entry.employeeId),
                    subtitle: Text(
                      '${entry.date} · ${entry.clockInAt == null ? '—' : DateFormat('h:mm a').format(entry.clockInAt!)}'
                      ' – ${entry.clockOutAt == null ? 'in progress' : DateFormat('h:mm a').format(entry.clockOutAt!)}',
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

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/scheduled_work_service.dart';
import '../../../core/state/employee_session.dart';
import '../../../models/scheduled_work.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/get_directions_button.dart';

/// today/upcoming jobs assigned to the signed-in employee's current team
class EmployeeJobsPage extends StatelessWidget {
  const EmployeeJobsPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: EmployeeSession.profile,
      builder: (context, profile, _) {
        final teamId = profile?.teamId;

        return AppScaffold(
          title: 'My Jobs',
          role: role,
          authToken: authToken,
          selectedRoute: AppRouter.myJobs,
          body: (teamId == null || teamId.isEmpty)
              ? const _EmptyState(
                  message: "You haven't been assigned to a team yet. Check with your employer.",
                )
              : DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      const TabBar(
                        tabs: [
                          Tab(text: 'All Jobs'),
                          Tab(text: "Today's Route"),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _AllJobsTab(teamId: teamId),
                            _TodaysRouteTab(teamId: teamId),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _AllJobsTab extends StatelessWidget {
  const _AllJobsTab({required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ScheduledWork>>(
      stream: ScheduledWorkService.watchScheduledWork(role: 'employee', teamId: teamId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _EmptyState(message: 'Failed to load jobs: ${snapshot.error}');
        }

        final jobs = snapshot.data ?? const <ScheduledWork>[];
        if (jobs.isEmpty) {
          return const _EmptyState(message: 'No jobs scheduled for your team today or upcoming.');
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: jobs.length,
          itemBuilder: (context, index) {
            final job = jobs[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _JobCard(job: job),
            );
          },
        );
      },
    );
  }
}

class _TodaysRouteTab extends StatelessWidget {
  const _TodaysRouteTab({required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ScheduledWork>>(
      stream: ScheduledWorkService.watchJobsForDay(day: DateTime.now(), role: 'employee', teamId: teamId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _EmptyState(message: "Failed to load today's route: ${snapshot.error}");
        }

        final jobs = snapshot.data ?? const <ScheduledWork>[];
        if (jobs.isEmpty) {
          return const _EmptyState(message: 'No jobs scheduled for your team today.');
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: jobs.length,
          itemBuilder: (context, index) {
            final job = jobs[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(14),
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(
                    job.address.isEmpty ? 'Address unavailable' : job.address,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: GetDirectionsButton(address: job.address),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});

  final ScheduledWork job;

  @override
  Widget build(BuildContext context) {
    final dateFormatter = DateFormat('MMM d, yyyy · h:mm a');
    final statusColor = switch (job.status) {
      ScheduledWorkStatus.completed => Colors.blue,
      ScheduledWorkStatus.invoiced => Colors.green,
      _ => Theme.of(context).colorScheme.primary,
    };
    final statusText = switch (job.status) {
      ScheduledWorkStatus.completed => 'Completed',
      ScheduledWorkStatus.invoiced => 'Completed',
      _ => 'Scheduled',
    };

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        title: Text(dateFormatter.format(job.scheduledDate), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (job.address.isNotEmpty)
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 14),
                    const SizedBox(width: 6),
                    Expanded(child: Text(job.address)),
                  ],
                ),
              if (job.phoneNumber.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.phone_outlined, size: 14),
                    const SizedBox(width: 6),
                    Text(job.phoneNumber),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.w700)),
                  ),
                  if (job.address.isNotEmpty) GetDirectionsButton(address: job.address),
                ],
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.pushNamed(
            context,
            AppRouter.jobDetail,
            arguments: {'role': 'employee', 'authToken': 'dev-employee', 'workId': job.id},
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

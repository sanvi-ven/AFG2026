import 'package:flutter/material.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/scheduled_work_service.dart';
import '../../../core/services/team_service.dart';
import '../../../models/scheduled_work.dart';
import '../../../models/team.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/get_directions_button.dart';

/// owner-only cross-team view of everything scheduled for today, grouped by team
class TodaysRoutePage extends StatelessWidget {
  const TodaysRoutePage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  @override
  Widget build(BuildContext context) {
    if (role != 'owner') {
      return const SizedBox.shrink();
    }

    return AppScaffold(
      title: "Today's Route",
      role: role,
      authToken: authToken,
      selectedRoute: AppRouter.todaysRoute,
      body: StreamBuilder<List<Team>>(
        stream: TeamService.watchAllTeams(),
        builder: (context, teamsSnapshot) {
          return StreamBuilder<List<ScheduledWork>>(
            stream: ScheduledWorkService.watchJobsForDay(day: DateTime.now()),
            builder: (context, jobsSnapshot) {
              if (!teamsSnapshot.hasData || !jobsSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final teamNameFor = {for (final team in teamsSnapshot.data!) team.id: team.name};
              final jobs = jobsSnapshot.data!;
              if (jobs.isEmpty) {
                return const Center(child: Text('No jobs scheduled for today.'));
              }

              final grouped = <String, List<ScheduledWork>>{};
              for (final job in jobs) {
                final teamId = job.teamId?.trim() ?? '';
                grouped.putIfAbsent(teamId, () => <ScheduledWork>[]).add(job);
              }
              final teamIds = grouped.keys.toList()
                ..sort((a, b) {
                  if (a.isEmpty) return 1;
                  if (b.isEmpty) return -1;
                  return (teamNameFor[a] ?? a).compareTo(teamNameFor[b] ?? b);
                });

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final teamId in teamIds) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        teamId.isEmpty ? 'Unassigned' : (teamNameFor[teamId] ?? teamId),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    for (final job in grouped[teamId]!)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(14),
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
                      ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}

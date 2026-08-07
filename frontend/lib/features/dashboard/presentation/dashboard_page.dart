import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/owner_settings_service.dart';
import '../../../core/services/reminder_check_service.dart';
import '../../../core/state/client_session.dart';
import '../../../core/state/employee_session.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../models/client_profile.dart';
import '../../../models/owner_settings.dart';
import 'owner_dashboard_stats.dart';

/// main dashboard page for authenticated users with role-based navigation
class DashboardPage extends StatefulWidget {
  const DashboardPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final Future<OwnerSettings> _ownerSettingsFuture;

  @override
  void initState() {
    super.initState();
    _ownerSettingsFuture = widget.role == 'owner'
        ? OwnerSettingsService.fetch().catchError((_) => OwnerSettings.empty())
        : Future.value(OwnerSettings.empty());
    // fire-and-forget: not a real background job, just a pragmatic trigger
    // point so reminders get generated roughly whenever anyone opens the app
    unawaited(ReminderCheckService.checkAndCreateReminders());
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Dashboard',
      role: widget.role,
      authToken: widget.authToken,
      selectedRoute: '/dashboard',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.role == 'owner')
            FutureBuilder<OwnerSettings>(
              future: _ownerSettingsFuture,
              builder: (context, snapshot) {
                final companyName = snapshot.data?.companyName.trim();
                final welcomeName =
                    companyName != null && companyName.isNotEmpty
                        ? companyName
                        : 'Business Owner';

                return Text(
                  'Welcome, $welcomeName',
                  style: Theme.of(context).textTheme.headlineSmall,
                );
              },
            )
          else if (widget.role == 'employee')
            ValueListenableBuilder(
              valueListenable: EmployeeSession.profile,
              builder: (context, profile, _) {
                final welcomeName =
                    profile?.greetingName.trim().isNotEmpty == true
                        ? profile!.greetingName
                        : 'there';
                return Text(
                  'Welcome, $welcomeName',
                  style: Theme.of(context).textTheme.headlineSmall,
                );
              },
            )
          else
            ValueListenableBuilder<ClientProfile?>(
              valueListenable: ClientSession.profile,
              builder: (context, profile, _) {
                final welcomeName =
                    profile?.greetingName.trim().isNotEmpty == true
                        ? profile!.greetingName
                        : 'Client';
                return Text(
                  'Welcome, $welcomeName',
                  style: Theme.of(context).textTheme.headlineSmall,
                );
              },
            ),
          const SizedBox(height: 12),
          if (widget.role == 'owner')
            OwnerDashboardStats(authToken: widget.authToken)
          else if (widget.role == 'employee') ...[
            _linkCard(
              context,
              title: 'My Jobs',
              subtitle: "See today's and upcoming jobs for your team",
              route: AppRouter.myJobs,
            ),
            _linkCard(
              context,
              title: 'My Hours',
              subtitle: 'Clock in/out and view your shift history',
              route: AppRouter.myHours,
            ),
          ] else ...[
            _requestWorkCard(context),
            _linkCard(context,
                title: 'Estimates',
                subtitle: 'Create and review quotes for clients',
                route: AppRouter.estimates),
            _linkCard(
              context,
              title: 'Book Appointment',
              subtitle: 'Pick an available slot from the bookings calendar',
              route: AppRouter.appointments,
            ),
            _linkCard(context,
                title: 'Invoices',
                subtitle: 'View, download, and manage all invoices',
                route: AppRouter.invoices),
            _linkCard(context,
                title: 'Messages',
                subtitle: 'Messages between you and the business owner',
                route: AppRouter.messages),
          ],
        ],
      ),
    );
  }

  /// dashboard tile for a logged-in client to request new work, pre-filled
  /// with their profile info
  Widget _requestWorkCard(BuildContext context) {
    return Card(
      child: ListTile(
        title: const Text('Request Work'),
        subtitle: const Text('Ask for a new quote on additional work'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          final profile = ClientSession.profile.value;
          Navigator.pushNamed(
            context,
            AppRouter.requestWork,
            arguments: {
              'clientId': profile?.signupId,
              'initialName': profile == null
                  ? ''
                  : '${profile.firstName} ${profile.lastName}'.trim(),
              'initialEmail': profile?.email ?? '',
              'initialPhone': profile?.phoneNumber ?? '',
              'initialAddress': profile?.address ?? '',
            },
          );
        },
      ),
    );
  }

  /// build a clickable navigation card for dashboard links
  Widget _linkCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String route,
  }) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.pushNamed(
            context,
            route,
            arguments: {'role': widget.role, 'authToken': widget.authToken},
          );
        },
      ),
    );
  }
}

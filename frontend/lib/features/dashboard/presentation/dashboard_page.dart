import 'package:flutter/material.dart';

import '../../../core/services/owner_settings_service.dart';
import '../../../core/state/client_session.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../models/client_profile.dart';
import '../../../models/owner_settings.dart';

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
                final welcomeName = companyName != null && companyName.isNotEmpty
                    ? companyName
                    : 'Business Owner';

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
                final welcomeName = profile?.greetingName.trim().isNotEmpty == true
                    ? profile!.greetingName
                    : 'Client';
                return Text(
                  'Welcome, $welcomeName',
                  style: Theme.of(context).textTheme.headlineSmall,
                );
              },
            ),
          const SizedBox(height: 12),
          _linkCard(
            context,
            title:
                widget.role == 'client' ? 'Book Appointment' : 'Appointments',
            subtitle: widget.role == 'client'
                ? 'Pick an available slot from the bookings calendar'
                : 'View and manage upcoming bookings',
            route: AppRouter.appointments,
          ),
          _linkCard(context,
              title: 'Unpaid Invoices',
              subtitle: 'Pending and overdue invoice balances',
              route: AppRouter.invoices),
          _linkCard(context,
              title: 'Estimates',
              subtitle: 'Review requests and quotes',
              route: AppRouter.estimates),
          _linkCard(context,
              title: 'Announcements',
              subtitle: 'Latest updates from the business owner',
              route: AppRouter.messages),
        ],
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

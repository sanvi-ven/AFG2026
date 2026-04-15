import 'package:flutter/material.dart';

import '../../../core/state/client_session.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../models/client_profile.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
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
          ValueListenableBuilder<ClientProfile?>(
            valueListenable: ClientSession.profile,
            builder: (context, profile, _) {
              final welcomeName = widget.role == 'owner'
                  ? 'Business Owner'
                  : (profile?.greetingName.trim().isNotEmpty == true
                      ? profile!.greetingName
                      : 'Client');
              return Text(
                'Welcome $welcomeName',
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
              title: 'Unpaid invoices',
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
          if (widget.role == 'owner')
            _linkCard(
              context,
              title: 'Availability',
              subtitle: 'Manage your working hours and blocked times',
              route: AppRouter.availability,
            ),
        ],
      ),
    );
  }

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

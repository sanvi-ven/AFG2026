import 'package:flutter/material.dart';

import '../../../core/router/app_router.dart';
import '../../../shared/widgets/app_scaffold.dart';

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
      selectedRoute: '/dashboard',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Welcome, ${widget.role == 'owner' ? 'Business Owner' : 'Client'}',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          if (widget.role == 'client')
            Card(
              child: ListTile(
                title: const Text('Book Appointment'),
                subtitle: const Text('Pick an available slot from the Bookings calendar'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    AppRouter.appointments,
                    arguments: {'role': widget.role, 'authToken': widget.authToken},
                  );
                },
              ),
            ),
          _card(
            context,
            title: 'Messages',
            subtitle: 'Owner announcements and client updates',
            route: AppRouter.messages,
          ),
          _card(
            context,
            title: 'Unpaid invoices',
            subtitle: 'Pending and overdue invoice balances',
            route: AppRouter.invoices,
          ),
          _card(
            context,
            title: 'Estimates',
            subtitle: 'Review incoming estimate requests',
            route: AppRouter.estimates,
          ),
        ],
      ),
    );
  }

  Widget _card(
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

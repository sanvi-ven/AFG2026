import 'package:flutter/material.dart';

import '../../../shared/widgets/app_scaffold.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({required this.role, super.key});

  final String role;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Dashboard',
      role: role,
      selectedRoute: '/dashboard',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Welcome, ${role == 'owner' ? 'Business Owner' : 'Client'}',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          _card(context, 'Messages', 'Unread and recent conversations'),
          _card(context, 'Upcoming appointments', 'Next bookings and availability'),
          _card(context, 'Unpaid invoices', 'Pending and overdue invoice balances'),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, String title, String subtitle) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

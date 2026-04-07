import 'package:flutter/material.dart';

import '../../../shared/widgets/app_scaffold.dart';

class AppointmentsPage extends StatelessWidget {
  const AppointmentsPage({required this.role, super.key});

  final String role;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Appointments',
      role: role,
      selectedRoute: '/appointments',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (role == 'owner')
            const ListTile(
              leading: Icon(Icons.schedule),
              title: Text('Set available time slots'),
              subtitle: Text('Define working hours and open slots'),
            ),
          const ListTile(
            leading: Icon(Icons.event_available),
            title: Text('Book / manage appointments'),
            subtitle: Text('Create, confirm, cancel, or reschedule'),
          ),
          const ListTile(
            leading: Icon(Icons.sync),
            title: Text('Google Calendar sync'),
            subtitle: Text('Endpoint ready: /appointments/{id}/sync-calendar'),
          ),
        ],
      ),
    );
  }
}

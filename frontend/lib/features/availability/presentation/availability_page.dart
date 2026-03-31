import 'package:flutter/material.dart';

import '../../../shared/widgets/app_scaffold.dart';

class AvailabilityPage extends StatelessWidget {
  const AvailabilityPage({required this.role, super.key});

  final String role;

  @override
  Widget build(BuildContext context) {
    if (role != 'owner') {
      return AppScaffold(
        title: 'Availability',
        role: role,
        selectedRoute: '/availability',
        body: const Center(child: Text('Availability management is for business owners only.')),
      );
    }

    return AppScaffold(
      title: 'Availability',
      role: role,
      selectedRoute: '/availability',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ListTile(
            leading: Icon(Icons.calendar_today_outlined),
            title: Text('Set recurring weekly hours'),
            subtitle: Text('Example: Mon-Fri, 9:00 AM - 5:00 PM'),
          ),
          ListTile(
            leading: Icon(Icons.block),
            title: Text('Block unavailable slots'),
            subtitle: Text('Set holidays and one-off unavailable windows'),
          ),
        ],
      ),
    );
  }
}

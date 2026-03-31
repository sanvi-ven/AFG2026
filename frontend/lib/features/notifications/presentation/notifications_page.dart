import 'package:flutter/material.dart';

import '../../../shared/widgets/app_scaffold.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({required this.role, super.key});

  final String role;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Notifications',
      role: role,
      selectedRoute: '/notifications',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ListTile(
            leading: Icon(Icons.person_pin_circle_outlined),
            title: Text('Send individual notification'),
            subtitle: Text('Endpoint: POST /notifications/single'),
          ),
          if (role == 'owner')
            const ListTile(
              leading: Icon(Icons.campaign_outlined),
              title: Text('Send mass notification to all clients'),
              subtitle: Text('Endpoint: POST /notifications/broadcast'),
            ),
        ],
      ),
    );
  }
}

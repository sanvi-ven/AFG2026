import 'package:flutter/material.dart';

import '../../../shared/widgets/app_scaffold.dart';

class MessagesPage extends StatelessWidget {
  const MessagesPage({required this.role, super.key});

  final String role;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Messages',
      role: role,
      selectedRoute: '/messages',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ListTile(
            leading: Icon(Icons.chat_bubble_outline),
            title: Text('Business ↔ Client messaging'),
            subtitle: Text('Thread list and message composer can be added next'),
          ),
        ],
      ),
    );
  }
}

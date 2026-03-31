import 'package:flutter/material.dart';

import '../../../shared/widgets/app_scaffold.dart';

class InvoicesPage extends StatelessWidget {
  const InvoicesPage({required this.role, super.key});

  final String role;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Invoices',
      role: role,
      selectedRoute: '/invoices',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (role == 'owner')
            const ListTile(
              leading: Icon(Icons.request_quote),
              title: Text('Create estimates and invoices'),
              subtitle: Text('Structured line items, tax, totals, status'),
            ),
          const ListTile(
            leading: Icon(Icons.visibility),
            title: Text('View invoice and payment status'),
            subtitle: Text('No PDF in MVP; render structured data only'),
          ),
        ],
      ),
    );
  }
}

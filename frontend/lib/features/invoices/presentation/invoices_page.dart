import 'package:flutter/material.dart';

import '../../../shared/widgets/app_scaffold.dart';

class InvoicesPage extends StatelessWidget {
  const InvoicesPage({required this.role, super.key});

  final String role;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppScaffold(
      title: 'Invoices',
      role: role,
      selectedRoute: '/invoices',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          _HeroSummary(role: role),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: 'Outstanding',
                  value: role == 'owner' ? '\$2,450' : '\$320',
                  icon: Icons.pending_actions_outlined,
                  color: colorScheme.errorContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricCard(
                  label: 'Paid This Month',
                  value: role == 'owner' ? '\$6,100' : '\$1,260',
                  icon: Icons.check_circle_outline,
                  color: colorScheme.secondaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (role == 'owner')
            const _ActionCard(
              icon: Icons.request_quote,
              title: 'Create estimates and invoices',
              subtitle: 'Build line items, taxes, and due dates in under a minute.',
              actionLabel: 'New Invoice',
            ),
          if (role == 'owner') const SizedBox(height: 12),
          const _ActionCard(
            icon: Icons.visibility,
            title: 'View invoice and payment status',
            subtitle: 'Sent, overdue, and paid invoices.',
            actionLabel: '',
          ),
          const SizedBox(height: 14),
          const _SectionTitle(title: 'Recent Activity'),
          const SizedBox(height: 10),
          if (role == 'owner')
            const _TimelineTile(
              title: 'Invoice INV-1042 sent',
              subtitle: 'Landscape lighting project - Due in 5 days',
              icon: Icons.send_outlined,
            ),
          const _TimelineTile(
            title: 'Payment received',
            subtitle: 'Invoice was paid in full',
            icon: Icons.task_alt,
          ),
          const _TimelineTile(
            title: 'Reminder queued',
            subtitle: 'Upcoming due notice scheduled for tomorrow',
            icon: Icons.notifications_active_outlined,
          ),
        ],
      ),
    );
  }
}

class _HeroSummary extends StatelessWidget {
  const _HeroSummary({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = role == 'owner' ? colorScheme.primary : colorScheme.tertiary;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.9), colorScheme.primary.withValues(alpha: 0.7)],
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role == 'owner' ? 'Cash Flow Snapshot' : 'Billing Overview',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  role == 'owner'
                      ? 'Stay on top of outstanding balances and upcoming payments.'
                      : 'Review what is due soon and what has already been paid.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onPrimary.withValues(alpha: 0.92),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.onPrimary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(Icons.receipt_long, size: 28, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 10),
            Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(subtitle),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(onPressed: () {}, child: Text(actionLabel)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }
}

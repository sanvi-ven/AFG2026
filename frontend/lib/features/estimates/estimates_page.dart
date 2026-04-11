import 'package:flutter/material.dart';

import '../../../core/router/app_router.dart';
import '../../../shared/widgets/app_scaffold.dart';

class EstimatesPage extends StatefulWidget {
  const EstimatesPage({required this.role, super.key});

  final String role;

  @override
  State<EstimatesPage> createState() => _EstimatesPageState();
}

class _EstimatesPageState extends State<EstimatesPage> {
  final List<_EstimateItem> _estimates = <_EstimateItem>[
    const _EstimateItem(
      id: 'EST-2041',
      clientName: 'RP Landscaping.',
      project: 'Lawn mowing',
      amount: '\$480',
      submittedAgo: '10 min ago',
      details: 'Includes labor, fixtures, and a beautiful lawn.',
      priority: _EstimatePriority.high,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final stats = _stats;

    return AppScaffold(
      title: 'Estimates',
      role: widget.role,
      selectedRoute: AppRouter.estimates,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          _buildSummary(context, stats),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _buildStatCard(context, 'Pending', stats.pending, Icons.inbox_outlined)),
              const SizedBox(width: 10),
              Expanded(child: _buildStatCard(context, 'Approved', stats.approved, Icons.check_circle_outline)),
              const SizedBox(width: 10),
              Expanded(child: _buildStatCard(context, 'Denied', stats.denied, Icons.block_outlined)),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Incoming Estimates',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          for (final estimate in _estimates) ...[
            _buildEstimateCard(context, estimate),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  _EstimateStats get _stats {
    final pending = _estimates.where((item) => item.decision == _EstimateDecision.pending).length;
    final approved = _estimates.where((item) => item.decision == _EstimateDecision.approved).length;
    final denied = _estimates.where((item) => item.decision == _EstimateDecision.denied).length;
    return _EstimateStats(pending: pending, approved: approved, denied: denied);
  }

  void _setDecision(String estimateId, _EstimateDecision decision) {
    final estimateIndex = _estimates.indexWhere((item) => item.id == estimateId);
    if (estimateIndex == -1) {
      return;
    }

    setState(() {
      _estimates[estimateIndex] = _estimates[estimateIndex].copyWith(decision: decision);
    });

    final estimate = _estimates[estimateIndex];
    final verb = decision == _EstimateDecision.approved ? 'approved' : 'denied';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${estimate.id} $verb for ${estimate.clientName}.')),
    );
  }

  Widget _buildSummary(BuildContext context, _EstimateStats stats) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorScheme.primary, colorScheme.primary],
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
                  'Review Incoming Estimates',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colorScheme.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Approve, deny, and keep the sales queue moving without losing context.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onPrimary.withValues(alpha: 0.92),
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${stats.pending} pending',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '${stats.approved} approved · ${stats.denied} denied',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onPrimary.withValues(alpha: 0.88),
                    ),
                textAlign: TextAlign.right,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String label, int value, IconData icon) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18),
            const SizedBox(height: 10),
            Text(value.toString(), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildEstimateCard(BuildContext context, _EstimateItem estimate) {
    final colorScheme = Theme.of(context).colorScheme;
    final priorityColor = switch (estimate.priority) {
      _EstimatePriority.high => colorScheme.error,
      _EstimatePriority.medium => colorScheme.tertiary,
      _EstimatePriority.low => colorScheme.primary,
    };

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: priorityColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.request_quote_outlined, color: priorityColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              estimate.project,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          _statusChip(context, estimate.decision),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('${estimate.clientName} · ${estimate.id}'),
                      const SizedBox(height: 6),
                      Text(estimate.details),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _pill(context, Icons.schedule_outlined, estimate.submittedAgo)),
                const SizedBox(width: 10),
                Expanded(child: _pill(context, Icons.attach_money, estimate.amount)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: estimate.decision == _EstimateDecision.approved ? null : () => _setDecision(estimate.id, _EstimateDecision.denied),
                    icon: const Icon(Icons.close),
                    label: const Text('Deny'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: estimate.decision == _EstimateDecision.denied ? null : () => _setDecision(estimate.id, _EstimateDecision.approved),
                    icon: const Icon(Icons.check),
                    label: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(BuildContext context, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, _EstimateDecision status) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = switch (status) {
      _EstimateDecision.pending => 'Pending',
      _EstimateDecision.approved => 'Approved',
      _EstimateDecision.denied => 'Denied',
    };
    final color = switch (status) {
      _EstimateDecision.pending => colorScheme.tertiary,
      _EstimateDecision.approved => colorScheme.primary,
      _EstimateDecision.denied => colorScheme.error,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _EstimateItem {
  const _EstimateItem({
    required this.id,
    required this.clientName,
    required this.project,
    required this.amount,
    required this.submittedAgo,
    required this.details,
    required this.priority,
    this.decision = _EstimateDecision.pending,
  });

  final String id;
  final String clientName;
  final String project;
  final String amount;
  final String submittedAgo;
  final String details;
  final _EstimatePriority priority;
  final _EstimateDecision decision;

  _EstimateItem copyWith({_EstimateDecision? decision}) {
    return _EstimateItem(
      id: id,
      clientName: clientName,
      project: project,
      amount: amount,
      submittedAgo: submittedAgo,
      details: details,
      priority: priority,
      decision: decision ?? this.decision,
    );
  }
}

class _EstimateStats {
  const _EstimateStats({
    required this.pending,
    required this.approved,
    required this.denied,
  });

  final int pending;
  final int approved;
  final int denied;
}

enum _EstimatePriority { low, medium, high }

enum _EstimateDecision { pending, approved, denied }

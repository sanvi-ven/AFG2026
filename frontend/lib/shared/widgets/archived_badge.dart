import 'package:flutter/material.dart';

/// small inline "archived" tag — used wherever an archived employee still
/// shows up in a historical record (a job, a time entry, a pay report) so
/// the record stays intact but it's clear at a glance the person is no
/// longer active.
class ArchivedBadge extends StatelessWidget {
  const ArchivedBadge({this.label = 'Archived', super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.archive_outlined, size: 12, color: scheme.outline),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: scheme.outline)),
        ],
      ),
    );
  }
}

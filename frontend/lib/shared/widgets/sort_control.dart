import 'package:flutter/material.dart';

enum ListSortMode { newestFirst, oldestFirst, client }

/// small dropdown for sorting a list page by date or client name
class SortControl extends StatelessWidget {
  const SortControl({required this.value, required this.onChanged, super.key});

  final ListSortMode value;
  final ValueChanged<ListSortMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<ListSortMode>(
      value: value,
      underline: const SizedBox.shrink(),
      items: const [
        DropdownMenuItem(value: ListSortMode.newestFirst, child: Text('Newest first')),
        DropdownMenuItem(value: ListSortMode.oldestFirst, child: Text('Oldest first')),
        DropdownMenuItem(value: ListSortMode.client, child: Text('Client name')),
      ],
      onChanged: (mode) {
        if (mode != null) onChanged(mode);
      },
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/services/equipment_service.dart';
import '../../../models/equipment.dart';

/// full-catalog search + tap-to-select dialog. Pops with the chosen
/// [EquipmentItem] (or null on cancel). Shared by the basket builder's "Add
/// item" and the kits page's "Add item to kit" — both just need one catalog
/// item picked at a time.
class EquipmentItemPickerDialog extends StatefulWidget {
  const EquipmentItemPickerDialog({super.key});

  @override
  State<EquipmentItemPickerDialog> createState() => _EquipmentItemPickerDialogState();
}

class _EquipmentItemPickerDialogState extends State<EquipmentItemPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add item'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search equipment or supplies',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: StreamBuilder<List<EquipmentItem>>(
                stream: EquipmentService.watchAll(),
                builder: (context, snapshot) {
                  final all = snapshot.data ?? const <EquipmentItem>[];
                  final items = EquipmentService.filterAndSort(
                    items: all,
                    query: _query,
                    sortBy: 'nameAsc',
                  );
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      items.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (items.isEmpty) {
                    return const Center(child: Text('No matching items.'));
                  }
                  return ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return ListTile(
                        leading: Icon(item.isEquipment
                            ? Icons.build_outlined
                            : Icons.inventory_outlined),
                        title: Text(item.name),
                        subtitle: Text(item.isEquipment ? 'Equipment' : 'Supply'),
                        onTap: () => Navigator.of(context).pop(item),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

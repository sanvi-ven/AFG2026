import 'package:flutter/material.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/equipment_kit_service.dart';
import '../../../core/state/employee_session.dart';
import '../../../models/equipment.dart';
import '../../../models/equipment_kit.dart';
import '../../../shared/widgets/app_scaffold.dart';
import 'equipment_item_picker_dialog.dart';

/// list/create/edit/delete equipment kits (preset lists like "Mowing setup").
/// Open to any staff — owner or employee — matching this app's equipment/teams
/// "full parity" design; see equipment_kit.dart for why there's no
/// creator-only edit restriction.
class EquipmentKitsPage extends StatelessWidget {
  const EquipmentKitsPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  String _actorName() {
    if (role == 'owner') return 'Owner';
    return EmployeeSession.profile.value?.fullName ?? 'Unknown';
  }

  Future<void> _addOrEdit(BuildContext context, {EquipmentKit? existing}) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _KitDialog(existing: existing, createdByName: _actorName()),
    );
  }

  Future<void> _confirmDelete(BuildContext context, EquipmentKit kit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete kit'),
        content: Text("Delete \"${kit.name}\"? This can't be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await EquipmentKitService.deleteKit(kit.id);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Equipment Kits',
      role: role,
      authToken: authToken,
      selectedRoute: AppRouter.equipmentCatalog,
      body: StreamBuilder<List<EquipmentKit>>(
        stream: EquipmentKitService.watchAllKits(),
        builder: (context, snapshot) {
          final kits = snapshot.data ?? const <EquipmentKit>[];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Saved kits pre-fill a basket with a standard set of equipment '
                'and supplies — pick one when starting a new basket, then adjust '
                'quantities as needed.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _addOrEdit(context),
                icon: const Icon(Icons.add),
                label: const Text('Add Kit'),
              ),
              const SizedBox(height: 16),
              if (snapshot.connectionState == ConnectionState.waiting && kits.isEmpty)
                const Center(child: CircularProgressIndicator())
              else if (kits.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No kits saved yet.'),
                )
              else
                for (final kit in kits)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(kit.name),
                      subtitle: Text(
                        kit.items
                            .map((i) => '${i.quantity}x ${i.name}')
                            .join(' · '),
                      ),
                      isThreeLine: kit.items.isNotEmpty,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Edit',
                            onPressed: () => _addOrEdit(context, existing: kit),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Delete',
                            onPressed: () => _confirmDelete(context, kit),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _KitDialog extends StatefulWidget {
  const _KitDialog({this.existing, required this.createdByName});

  final EquipmentKit? existing;
  final String createdByName;

  @override
  State<_KitDialog> createState() => _KitDialogState();
}

class _KitDialogState extends State<_KitDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final List<EquipmentKitItem> _items;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _descriptionController = TextEditingController(text: existing?.description ?? '');
    _items = List<EquipmentKitItem>.from(existing?.items ?? const <EquipmentKitItem>[]);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _addItem() async {
    final item = await showDialog<EquipmentItem>(
      context: context,
      builder: (_) => const EquipmentItemPickerDialog(),
    );
    if (item == null || !mounted) return;
    if (_items.any((i) => i.equipmentId == item.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.name} is already in this kit.')),
      );
      return;
    }
    setState(() {
      _items.add(EquipmentKitItem(
        equipmentId: item.id,
        name: item.name,
        type: item.type,
        quantity: 1,
      ));
    });
  }

  void _changeQuantity(int index, int delta) {
    setState(() {
      final current = _items[index];
      final next = current.quantity + delta;
      if (next < 1 || next > 99) return;
      _items[index] = EquipmentKitItem(
        equipmentId: current.equipmentId,
        name: current.name,
        type: current.type,
        quantity: next,
      );
    });
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A name is required.')),
      );
      return;
    }
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one item.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await EquipmentKitService.saveKit(
        id: widget.existing?.id,
        name: name,
        description: _descriptionController.text.trim(),
        items: _items,
        createdByName: widget.createdByName,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: ${error.toString().replaceFirst('Exception: ', '')}')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Kit' : 'Edit Kit'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                    labelText: 'Name (e.g. "Mowing setup")', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                    labelText: 'Description (optional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Text('Items', style: Theme.of(context).textTheme.titleSmall)),
                  TextButton.icon(
                    onPressed: _addItem,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add item'),
                  ),
                ],
              ),
              if (_items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No items added yet.'),
                )
              else
                for (var i = 0; i < _items.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(
                          _items[i].type == EquipmentType.equipment
                              ? Icons.build_outlined
                              : Icons.inventory_outlined,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_items[i].name)),
                        IconButton(
                          onPressed: () => _changeQuantity(i, -1),
                          icon: const Icon(Icons.remove, size: 16),
                          visualDensity: VisualDensity.compact,
                        ),
                        Text('${_items[i].quantity}'),
                        IconButton(
                          onPressed: () => _changeQuantity(i, 1),
                          icon: const Icon(Icons.add, size: 16),
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          onPressed: () => _removeItem(i),
                          icon: const Icon(Icons.close, size: 16),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/service_catalog_service.dart';
import '../../../models/common_service.dart';
import '../../../shared/widgets/app_scaffold.dart';

/// owner-only screen for viewing, adding, editing, and deleting the
/// reusable "common services" catalog used when building estimates
class ServiceCatalogPage extends StatelessWidget {
  const ServiceCatalogPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  Future<void> _addOrEdit(BuildContext context, {CommonService? existing}) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CatalogEntryDialog(existing: existing),
    );
  }

  Future<void> _confirmDelete(BuildContext context, CommonService entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Common Service'),
        content: Text("Delete ${entry.name}? This can't be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ServiceCatalogService.deleteService(entry.id);
  }

  @override
  Widget build(BuildContext context) {
    if (role != 'owner') {
      return const SizedBox.shrink();
    }

    return AppScaffold(
      title: 'Common Services',
      role: role,
      authToken: authToken,
      selectedRoute: AppRouter.serviceCatalog,
      body: StreamBuilder<List<CommonService>>(
        stream: ServiceCatalogService.watchAllServices(),
        builder: (context, snapshot) {
          final services = snapshot.data ?? const <CommonService>[];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FilledButton.icon(
                onPressed: () => _addOrEdit(context),
                icon: const Icon(Icons.add),
                label: const Text('Add Common Service'),
              ),
              const SizedBox(height: 16),
              if (services.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No common services saved yet.'),
                )
              else
                for (final entry in services)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(entry.name),
                      subtitle: Text(
                        [
                          if (entry.description.isNotEmpty) entry.description,
                          entry.isPerUnit
                              ? '\$${entry.unitPrice!.toStringAsFixed(2)} / ${entry.unit?.isEmpty ?? true ? 'unit' : entry.unit}'
                              : '\$${(entry.flatPrice ?? 0).toStringAsFixed(2)} flat',
                        ].join('\n'),
                      ),
                      isThreeLine: entry.description.isNotEmpty,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Edit',
                            onPressed: () => _addOrEdit(context, existing: entry),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Delete',
                            onPressed: () => _confirmDelete(context, entry),
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

class _CatalogEntryDialog extends StatefulWidget {
  const _CatalogEntryDialog({this.existing});

  final CommonService? existing;

  @override
  State<_CatalogEntryDialog> createState() => _CatalogEntryDialogState();
}

class _CatalogEntryDialogState extends State<_CatalogEntryDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceController;
  late final TextEditingController _unitController;
  late bool _isPerUnit;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _descriptionController = TextEditingController(text: existing?.description ?? '');
    _isPerUnit = existing?.isPerUnit ?? false;
    _priceController = TextEditingController(
      text: existing == null
          ? ''
          : (existing.isPerUnit ? existing.unitPrice : existing.flatPrice)?.toStringAsFixed(2) ?? '',
    );
    _unitController = TextEditingController(text: existing?.unit ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final price = double.tryParse(_priceController.text.trim());
    if (name.isEmpty || price == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A name and price are required.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ServiceCatalogService.saveService(
        id: widget.existing?.id,
        name: name,
        description: _descriptionController.text.trim(),
        unit: _isPerUnit ? _unitController.text.trim() : null,
        unitPrice: _isPerUnit ? price : null,
        flatPrice: _isPerUnit ? null : price,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $error')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Common Service' : 'Edit Common Service'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descriptionController,
              maxLines: 2,
              minLines: 1,
              decoration: const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Flat price')),
                ButtonSegment(value: true, label: Text('Price per unit')),
              ],
              selected: {_isPerUnit},
              onSelectionChanged: (selection) => setState(() => _isPerUnit = selection.first),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: _isPerUnit ? 'Price per unit' : 'Price',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                if (_isPerUnit) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _unitController,
                      decoration: const InputDecoration(labelText: 'Unit (e.g. ft)', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ],
            ),
          ],
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

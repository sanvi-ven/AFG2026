import 'package:flutter/material.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/checklist_template_service.dart';
import '../../../models/checklist_template.dart';
import '../../../shared/widgets/app_scaffold.dart';

/// owner-only screen for viewing, adding, editing, and deleting reusable
/// job checklist templates
class ChecklistTemplatesPage extends StatelessWidget {
  const ChecklistTemplatesPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  Future<void> _addOrEdit(BuildContext context, {ChecklistTemplate? existing}) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ChecklistTemplateDialog(existing: existing),
    );
  }

  Future<void> _confirmDelete(BuildContext context, ChecklistTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Checklist Template'),
        content: Text("Delete ${template.name}? This can't be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ChecklistTemplateService.deleteTemplate(template.id);
  }

  @override
  Widget build(BuildContext context) {
    if (role != 'owner') {
      return const SizedBox.shrink();
    }

    return AppScaffold(
      title: 'Checklist Templates',
      role: role,
      authToken: authToken,
      selectedRoute: AppRouter.checklistTemplates,
      body: StreamBuilder<List<ChecklistTemplate>>(
        stream: ChecklistTemplateService.watchAllTemplates(),
        builder: (context, snapshot) {
          final templates = snapshot.data ?? const <ChecklistTemplate>[];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FilledButton.icon(
                onPressed: () => _addOrEdit(context),
                icon: const Icon(Icons.add),
                label: const Text('Add Checklist Template'),
              ),
              const SizedBox(height: 16),
              if (templates.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No checklist templates saved yet.'),
                )
              else
                for (final template in templates)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(template.name),
                      subtitle: Text(template.items.join(' · ')),
                      isThreeLine: template.items.isNotEmpty,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Edit',
                            onPressed: () => _addOrEdit(context, existing: template),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Delete',
                            onPressed: () => _confirmDelete(context, template),
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

class _ChecklistTemplateDialog extends StatefulWidget {
  const _ChecklistTemplateDialog({this.existing});

  final ChecklistTemplate? existing;

  @override
  State<_ChecklistTemplateDialog> createState() => _ChecklistTemplateDialogState();
}

class _ChecklistTemplateDialogState extends State<_ChecklistTemplateDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _itemsController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _itemsController = TextEditingController(text: existing?.items.join('\n') ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _itemsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final items = _itemsController.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (name.isEmpty || items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A name and at least one item are required.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ChecklistTemplateService.saveTemplate(id: widget.existing?.id, name: name, items: items);
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
      title: Text(widget.existing == null ? 'Add Checklist Template' : 'Edit Checklist Template'),
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
              controller: _itemsController,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Checklist items (one per line)',
                border: OutlineInputBorder(),
              ),
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

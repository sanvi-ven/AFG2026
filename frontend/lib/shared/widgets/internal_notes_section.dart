import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/internal_note_service.dart';
import '../../core/state/employee_session.dart';
import '../../models/internal_note.dart';

/// staff-only running log of notes attached to an Estimate or a
/// ScheduledWork job — never mount this for role == 'client'. See
/// InternalNote's own doc comment for why this content lives in a separate
/// Firestore collection rather than a field on the estimate/job doc.
class InternalNotesSection extends StatefulWidget {
  const InternalNotesSection({
    required this.entityType,
    required this.entityId,
    required this.role,
    super.key,
  });

  /// InternalNoteEntityType.estimate or .scheduledWork
  final String entityType;
  final String entityId;

  /// 'owner' or 'employee' — the caller is responsible for never mounting
  /// this widget for a client
  final String role;

  @override
  State<InternalNotesSection> createState() => _InternalNotesSectionState();
}

class _InternalNotesSectionState extends State<InternalNotesSection> {
  final _noteController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  bool get _isOwner => widget.role == 'owner';

  /// same shape as equipment_detail_page.dart's _actor() — the owner role
  /// has no profile doc/profile_id claim, so it gets a fixed sentinel
  /// instead of a real Firestore doc id.
  ({String id, String name}) _actor() {
    if (_isOwner) return (id: 'owner', name: 'Owner');
    final profile = EmployeeSession.profile.value;
    if (profile != null) return (id: profile.employeeId, name: profile.fullName);
    return (id: 'unknown', name: 'Unknown');
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _addNote() async {
    final text = _noteController.text.trim();
    if (text.isEmpty) return;
    final actor = _actor();

    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await InternalNoteService.addNote(
        entityType: widget.entityType,
        entityId: widget.entityId,
        text: text,
        authorId: actor.id,
        authorName: actor.name,
        authorRole: widget.role,
      );
      _noteController.clear();
    } catch (error) {
      if (mounted) setState(() => _error = 'Failed to add note: $error');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _deleteNote(InternalNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Note'),
        content: const Text("Delete this internal note? This can't be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await InternalNoteService.deleteNote(note.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete note: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final actor = _actor();
    final canPostAsSelf = actor.id != 'unknown';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Internal Notes', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 2),
        Text(
          'Visible to staff only — never shown to the client.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<InternalNote>>(
          stream: InternalNoteService.watchForEntity(widget.entityId),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            final notes = snapshot.data!;
            if (notes.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('No internal notes yet.'),
              );
            }
            return Column(
              children: [
                for (final note in notes)
                  _InternalNoteRow(
                    note: note,
                    canDelete: _isOwner || note.authorId == actor.id,
                    onDelete: () => _deleteNote(note),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _noteController,
          enabled: canPostAsSelf && !_isSubmitting,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Add an internal note',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: canPostAsSelf && !_isSubmitting ? _addNote : null,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add, size: 16),
            label: const Text('Add Note'),
          ),
        ),
      ],
    );
  }
}

class _InternalNoteRow extends StatelessWidget {
  const _InternalNoteRow({required this.note, required this.canDelete, required this.onDelete});

  final InternalNote note;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final roleLabel = note.authorRole == 'owner' ? 'Owner' : 'Employee';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${note.authorName} ($roleLabel) · '
                  '${DateFormat('MMM d, yyyy · h:mm a').format(note.createdAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(note.text),
              ],
            ),
          ),
          if (canDelete)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: onDelete,
              tooltip: 'Delete note',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }
}

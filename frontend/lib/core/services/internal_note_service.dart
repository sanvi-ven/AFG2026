import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/internal_note.dart';

/// manages staff-only internal notes attached to an Estimate or a
/// ScheduledWork job. See InternalNote's own doc comment for why these live
/// in their own top-level collection rather than as a field on the parent
/// estimate/job doc — firestore.rules enforces `isStaff()`-only read/write
/// on this collection, which is the real security boundary; nothing here
/// re-checks authorship client-side beyond what the UI already gates,
/// matching this codebase's existing convention elsewhere (e.g.
/// NotificationService.markRead has no client-side ownership re-check
/// either).
class InternalNoteService {
  InternalNoteService._();

  static final CollectionReference<Map<String, dynamic>> _collection =
      FirebaseFirestore.instance.collection('internal_notes');

  /// notes for one estimate/job, newest first. Queries by entityId alone —
  /// Firestore auto-IDs from estimates/scheduled_work can never collide
  /// across collections, so entityType isn't needed to disambiguate.
  static Stream<List<InternalNote>> watchForEntity(String entityId) {
    return _collection.where('entityId', isEqualTo: entityId).snapshots().map((snapshot) {
      final notes = snapshot.docs
          .map((doc) => InternalNote.fromMap({...doc.data(), 'id': doc.id}))
          .toList();
      notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return notes;
    });
  }

  static Future<void> addNote({
    required String entityType,
    required String entityId,
    required String text,
    required String authorId,
    required String authorName,
    required String authorRole,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final doc = _collection.doc();
    final note = InternalNote(
      id: doc.id,
      entityType: entityType,
      entityId: entityId.trim(),
      text: trimmed,
      authorId: authorId,
      authorName: authorName,
      authorRole: authorRole,
      createdAt: DateTime.now(),
    );
    await doc.set(note.toMap());
  }

  static Future<void> deleteNote(String noteId) => _collection.doc(noteId).delete();
}

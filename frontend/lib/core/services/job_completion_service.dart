import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/job_completion_form.dart';
import 'scheduled_work_service.dart';

/// manages the one-time job completion report a crew member files per job
class JobCompletionService {
  JobCompletionService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _collection =
      _firestore.collection('job_completion_forms');

  /// stream the completion form for a job, if one has been submitted
  static Stream<JobCompletionForm?> watchFormForWork(String workId) {
    return _collection.doc(workId).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return null;
      return JobCompletionForm.fromMap(data);
    });
  }

  /// owner review: all submitted completion forms, most recent first
  static Stream<List<JobCompletionForm>> watchAllForms() {
    return _collection.snapshots().map((snapshot) {
      final forms = snapshot.docs.map((doc) => JobCompletionForm.fromMap(doc.data())).toList();
      forms.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return forms;
    });
  }

  /// submit a job's completion form exactly once; throws if a teammate already submitted one.
  /// on success, also marks the underlying ScheduledWork as completed.
  static Future<void> submit({
    required String workId,
    String? teamId,
    required String submittedByEmployeeId,
    required String submittedByName,
    required DateTime startTime,
    required DateTime endTime,
    required String notes,
    required List<String> beforePhotoUrls,
    required List<String> afterPhotoUrls,
  }) async {
    final doc = _collection.doc(workId);

    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(doc);
      if (existing.exists) {
        throw Exception('This job has already been marked complete by a teammate.');
      }

      final form = JobCompletionForm(
        workId: workId,
        teamId: teamId,
        submittedByEmployeeId: submittedByEmployeeId,
        submittedByName: submittedByName,
        startTime: startTime,
        endTime: endTime,
        notes: notes.trim(),
        beforePhotoUrls: beforePhotoUrls,
        afterPhotoUrls: afterPhotoUrls,
        createdAt: DateTime.now(),
      );

      transaction.set(doc, form.toMap());
    });

    await ScheduledWorkService.markCompleted(workId: workId);
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/job_completion_service.dart';
import '../../../core/services/job_photo_upload_service.dart';
import '../../../core/services/scheduled_work_service.dart';
import '../../../core/state/employee_session.dart';
import '../../../models/job_completion_form.dart';
import '../../../models/scheduled_work.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/get_directions_button.dart';

/// job detail + one-time completion form (start/end time, notes, before/after photos)
class JobDetailPage extends StatefulWidget {
  const JobDetailPage({required this.role, required this.workId, this.authToken, super.key});

  final String role;
  final String workId;
  final String? authToken;

  @override
  State<JobDetailPage> createState() => _JobDetailPageState();
}

class _JobDetailPageState extends State<JobDetailPage> {
  DateTime? _startTime;
  DateTime? _endTime;
  final _notesController = TextEditingController();
  final List<String> _beforePhotoUrls = [];
  final List<String> _afterPhotoUrls = [];
  bool _isUploadingBefore = false;
  bool _isUploadingAfter = false;
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool isStart}) async {
    final now = DateTime.now();
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (pickedTime == null || !mounted) return;

    final picked = DateTime(now.year, now.month, now.day, pickedTime.hour, pickedTime.minute);
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  Future<void> _addPhoto({required bool isBefore}) async {
    setState(() {
      if (isBefore) {
        _isUploadingBefore = true;
      } else {
        _isUploadingAfter = true;
      }
    });
    try {
      final url = await JobPhotoUploadService.pickAndUpload(
        workId: widget.workId,
        phase: isBefore ? 'before' : 'after',
      );
      if (url == null || !mounted) return;
      setState(() {
        if (isBefore) {
          _beforePhotoUrls.add(url);
        } else {
          _afterPhotoUrls.add(url);
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload photo: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingBefore = false;
          _isUploadingAfter = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    final profile = EmployeeSession.profile.value;
    if (profile == null) return;

    if (_startTime == null || _endTime == null) {
      setState(() => _error = 'Set both a start time and end time.');
      return;
    }
    if (_endTime!.isBefore(_startTime!)) {
      setState(() => _error = 'End time must be after start time.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await JobCompletionService.submit(
        workId: widget.workId,
        teamId: profile.teamId,
        submittedByEmployeeId: profile.employeeId,
        submittedByName: profile.fullName,
        startTime: _startTime!,
        endTime: _endTime!,
        notes: _notesController.text,
        beforePhotoUrls: _beforePhotoUrls,
        afterPhotoUrls: _afterPhotoUrls,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job marked complete.')),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Job Detail',
      role: widget.role,
      authToken: widget.authToken,
      selectedRoute: '/jobs',
      body: StreamBuilder<JobCompletionForm?>(
        stream: JobCompletionService.watchFormForWork(widget.workId),
        builder: (context, formSnapshot) {
          final existingForm = formSnapshot.data;
          return StreamBuilder<List<ScheduledWork>>(
            stream: ScheduledWorkService.watchScheduledWork(
              role: 'employee',
              teamId: EmployeeSession.profile.value?.teamId,
            ),
            builder: (context, jobsSnapshot) {
              final job = (jobsSnapshot.data ?? const <ScheduledWork>[])
                  .where((item) => item.id == widget.workId)
                  .toList();
              if (job.isEmpty) {
                return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Job not found.')));
              }
              return _buildBody(context, job.first, existingForm);
            },
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, ScheduledWork job, JobCompletionForm? existingForm) {
    final dateFormatter = DateFormat('MMM d, yyyy · h:mm a');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateFormatter.format(job.scheduledDate), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                if (job.address.isNotEmpty) ...[
                  Row(children: [const Icon(Icons.location_on_outlined, size: 16), const SizedBox(width: 6), Expanded(child: Text(job.address))]),
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerLeft, child: GetDirectionsButton(address: job.address)),
                ],
                if (job.phoneNumber.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(children: [const Icon(Icons.phone_outlined, size: 16), const SizedBox(width: 6), Text(job.phoneNumber)]),
                ],
                const SizedBox(height: 10),
                Text('Services', style: Theme.of(context).textTheme.titleSmall),
                for (final item in job.services) Text('• ${item.name}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (existingForm != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.check_circle, color: Colors.green, size: 18),
                      SizedBox(width: 8),
                      Text('Completion form submitted', style: TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Submitted by: ${existingForm.submittedByName}'),
                  Text('Start: ${DateFormat('h:mm a').format(existingForm.startTime)}'),
                  Text('End: ${DateFormat('h:mm a').format(existingForm.endTime)}'),
                  if (existingForm.notes.isNotEmpty) Text('Notes: ${existingForm.notes}'),
                ],
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Job Completion Form', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickTime(isStart: true),
                          icon: const Icon(Icons.play_arrow),
                          label: Text(_startTime == null ? 'Start time' : DateFormat('h:mm a').format(_startTime!)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickTime(isStart: false),
                          icon: const Icon(Icons.stop),
                          label: Text(_endTime == null ? 'End time' : DateFormat('h:mm a').format(_endTime!)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Notes (anything go wrong?)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PhotoRow(
                    label: 'Before photos',
                    urls: _beforePhotoUrls,
                    isUploading: _isUploadingBefore,
                    onAdd: () => _addPhoto(isBefore: true),
                  ),
                  const SizedBox(height: 12),
                  _PhotoRow(
                    label: 'After photos',
                    urls: _afterPhotoUrls,
                    isUploading: _isUploadingAfter,
                    onAdd: () => _addPhoto(isBefore: false),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Mark Job Complete'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({required this.label, required this.urls, required this.isUploading, required this.onAdd});

  final String label;
  final List<String> urls;
  final bool isUploading;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final url in urls)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(url, width: 72, height: 72, fit: BoxFit.cover),
              ),
            OutlinedButton.icon(
              onPressed: isUploading ? null : onAdd,
              icon: isUploading
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_a_photo_outlined),
              label: const Text('Add'),
            ),
          ],
        ),
      ],
    );
  }
}

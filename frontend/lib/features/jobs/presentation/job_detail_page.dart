import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/equipment_reservation_service.dart';
import '../../../core/services/equipment_service.dart';
import '../../../core/services/job_completion_service.dart';
import '../../../core/services/job_photo_upload_service.dart';
import '../../../core/services/scheduled_work_service.dart';
import '../../../core/state/employee_session.dart';
import '../../../models/equipment.dart';
import '../../../models/equipment_reservation.dart';
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
              employeeId: EmployeeSession.profile.value?.employeeId,
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
        if (job.checklistItems.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Checklist', style: Theme.of(context).textTheme.titleMedium),
                  for (var i = 0; i < job.checklistItems.length; i++)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: job.checklistItems[i].done,
                      title: Text(job.checklistItems[i].label),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (checked) => ScheduledWorkService.updateChecklistItem(
                        workId: job.id,
                        index: i,
                        done: checked ?? false,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _buildEquipmentSection(context, job),
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

  // --- equipment section ----------------------------------------------------

  Widget _buildEquipmentSection(BuildContext context, ScheduledWork job) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Equipment',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton.icon(
                  onPressed: () => _assignEquipment(context, job),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Assign equipment'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            StreamBuilder<List<EquipmentReservation>>(
              stream: EquipmentReservationService.watchForWork(job.id),
              builder: (context, snapshot) {
                final reservations =
                    snapshot.data ?? const <EquipmentReservation>[];
                if (snapshot.connectionState == ConnectionState.waiting &&
                    reservations.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (reservations.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No equipment assigned to this job yet.'),
                  );
                }
                return Column(
                  children: [
                    for (final reservation in reservations)
                      _JobEquipmentRow(
                        reservation: reservation,
                        onCheckOut: () => _markCheckedOut(context, reservation),
                        onReturn: () => _markReturned(context, reservation),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markCheckedOut(
      BuildContext context, EquipmentReservation reservation) async {
    try {
      await EquipmentReservationService.markCheckedOut(reservation.id);
      if (!context.mounted) return;
      _snack(context, 'Unit #${reservation.unitNumber} checked out.');
    } catch (error) {
      if (!context.mounted) return;
      _snack(context, _errorText(error));
    }
  }

  Future<void> _markReturned(
      BuildContext context, EquipmentReservation reservation) async {
    try {
      await EquipmentReservationService.markReturned(reservation.id);
      if (!context.mounted) return;
      _snack(context, 'Unit #${reservation.unitNumber} returned.');
    } catch (error) {
      if (!context.mounted) return;
      _snack(context, _errorText(error));
    }
  }

  Future<void> _assignEquipment(BuildContext context, ScheduledWork job) async {
    final request = await showDialog<_AssignRequest>(
      context: context,
      builder: (_) => _AssignEquipmentDialog(job: job),
    );
    if (request == null || !context.mounted) return;

    try {
      final actor = _actor();
      final created = await EquipmentReservationService.reserveUnits(
        equipment: request.item,
        quantity: request.quantity,
        startTime: request.start,
        endTime: request.end,
        employeeId: actor.id,
        employeeName: actor.name,
        workId: job.id,
        jobAddress: job.address,
      );
      if (!context.mounted) return;
      final units = created.map((r) => '#${r.unitNumber}').join(', ');
      _snack(
          context,
          created.length == 1
              ? 'Assigned ${request.item.name} unit $units to this job.'
              : 'Assigned ${request.item.name} units $units to this job.');
    } catch (error) {
      if (!context.mounted) return;
      _snack(context, _errorText(error));
    }
  }

  /// who is acting — the owner is attributed as 'owner'/'Owner'; an employee
  /// comes from the active session (mirrors EquipmentDetailPage._actor).
  ({String id, String name}) _actor() {
    if (widget.role == 'owner') return (id: 'owner', name: 'Owner');
    final profile = EmployeeSession.profile.value;
    if (profile != null) {
      return (id: profile.employeeId, name: profile.fullName);
    }
    return (id: 'unknown', name: 'Unknown');
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _errorText(Object error) =>
      error.toString().replaceFirst('Exception: ', '');
}

/// one row in the job's Equipment section: unit, time window, status, and
/// check-out/return actions on active, not-yet-returned reservations.
class _JobEquipmentRow extends StatelessWidget {
  const _JobEquipmentRow({
    required this.reservation,
    required this.onCheckOut,
    required this.onReturn,
  });

  final EquipmentReservation reservation;
  final VoidCallback onCheckOut;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('h:mm a');
    final window =
        '${timeFmt.format(reservation.startTime)} – ${timeFmt.format(reservation.endTime)}';

    final ({String label, Color color}) status;
    if (reservation.isCancelled) {
      status = (label: 'Cancelled', color: Colors.grey);
    } else if (reservation.returnedAt != null) {
      status = (label: 'Returned', color: Colors.blue);
    } else if (reservation.checkedOutAt != null) {
      status = (label: 'Checked out', color: Colors.green);
    } else {
      status = (label: 'Not checked out', color: Colors.amber.shade800);
    }

    final canAct =
        reservation.isActive && reservation.returnedAt == null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  child: Text('#${reservation.unitNumber}',
                      style: const TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(reservation.equipmentName,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('${reservation.date} · $window',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: status.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(status.label,
                      style: TextStyle(
                          fontSize: 12,
                          color: status.color,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            if (canAct) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (reservation.checkedOutAt == null)
                    OutlinedButton.icon(
                      onPressed: onCheckOut,
                      icon: const Icon(Icons.logout, size: 16),
                      label: const Text('Check out'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: onReturn,
                      icon: const Icon(Icons.login, size: 16),
                      label: const Text('Return'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// the collected inputs from [_AssignEquipmentDialog], handed back to the page
/// which owns the actual service call + SnackBar.
class _AssignRequest {
  const _AssignRequest({
    required this.item,
    required this.quantity,
    required this.start,
    required this.end,
  });

  final EquipmentItem item;
  final int quantity;
  final DateTime start;
  final DateTime end;
}

/// pick an Equipment item + quantity + date/time window for assigning gear to a
/// job. Adapts EquipmentDetailPage's _ReserveDialog: same manual
/// showDatePicker/showTimePicker pattern, with an item picker up front and the
/// window pre-filled from the job's scheduled date (end = start + 4h).
class _AssignEquipmentDialog extends StatefulWidget {
  const _AssignEquipmentDialog({required this.job});

  final ScheduledWork job;

  @override
  State<_AssignEquipmentDialog> createState() => _AssignEquipmentDialogState();
}

class _AssignEquipmentDialogState extends State<_AssignEquipmentDialog> {
  EquipmentItem? _item;
  int _quantity = 1;
  late DateTime _date;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;

  @override
  void initState() {
    super.initState();
    final scheduled = widget.job.scheduledDate;
    _date = DateTime(scheduled.year, scheduled.month, scheduled.day);
    _startTime = TimeOfDay.fromDateTime(scheduled);
    final naiveEnd = scheduled.add(const Duration(hours: 4));
    // both start and end always get recombined onto the same _date (the
    // job's day) in _combine(), so a default that rolls past midnight would
    // silently become "before start" once re-stamped onto that single date.
    // Clamp the default to the same calendar day; the user can still pick
    // any time they want via the pickers.
    final sameDayEnd = naiveEnd.year == scheduled.year &&
            naiveEnd.month == scheduled.month &&
            naiveEnd.day == scheduled.day
        ? naiveEnd
        : DateTime(scheduled.year, scheduled.month, scheduled.day, 23, 59);
    _endTime = TimeOfDay.fromDateTime(sameDayEnd);
  }

  int _maxQuantity(EquipmentItem item) => item.units
      .where((u) => u.status == EquipmentUnitStatus.active)
      .length;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickStart() async {
    final picked =
        await showTimePicker(context: context, initialTime: _startTime);
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _pickEnd() async {
    final picked =
        await showTimePicker(context: context, initialTime: _endTime);
    if (picked != null) setState(() => _endTime = picked);
  }

  DateTime _combine(TimeOfDay time) =>
      DateTime(_date.year, _date.month, _date.day, time.hour, time.minute);

  void _submit() {
    final item = _item;
    if (item == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick an equipment item.')),
      );
      return;
    }
    final start = _combine(_startTime);
    final end = _combine(_endTime);
    if (!start.isBefore(end)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time.')),
      );
      return;
    }
    Navigator.of(context).pop(_AssignRequest(
      item: item,
      quantity: _quantity,
      start: start,
      end: end,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('MMM d, yyyy').format(_date);
    return AlertDialog(
      title: const Text('Assign equipment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Equipment'),
            const SizedBox(height: 4),
            StreamBuilder<List<EquipmentItem>>(
              stream: EquipmentService.watchAll(),
              builder: (context, snapshot) {
                final items = (snapshot.data ?? const <EquipmentItem>[])
                    .where((item) => item.isEquipment)
                    .toList()
                  ..sort((a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                if (snapshot.connectionState == ConnectionState.waiting &&
                    items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (items.isEmpty) {
                  return const Text('No equipment items available.');
                }
                // drop a stale selection if it's no longer in the list
                final selected = _item != null &&
                        items.any((i) => i.id == _item!.id)
                    ? items.firstWhere((i) => i.id == _item!.id)
                    : null;
                return DropdownButton<EquipmentItem>(
                  isExpanded: true,
                  value: selected,
                  hint: const Text('Select equipment'),
                  items: [
                    for (final item in items)
                      DropdownMenuItem(
                        value: item,
                        child: Text(item.name,
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (item) {
                    setState(() {
                      _item = item;
                      final max = item == null ? 1 : _maxQuantity(item);
                      if (_quantity > max) _quantity = max < 1 ? 1 : max;
                    });
                  },
                );
              },
            ),
            const SizedBox(height: 16),
            const Text('Quantity'),
            const SizedBox(height: 4),
            Builder(builder: (context) {
              final max = _item == null ? 0 : _maxQuantity(_item!);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton.outlined(
                        onPressed: _quantity > 1
                            ? () => setState(() => _quantity--)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text('$_quantity',
                            style: Theme.of(context).textTheme.titleLarge),
                      ),
                      IconButton.outlined(
                        onPressed: _quantity < max
                            ? () => setState(() => _quantity++)
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  Text(
                    _item == null
                        ? 'Pick an item to see availability'
                        : '$max unit(s) available',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              );
            }),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Date'),
              subtitle: Text(dateLabel),
              onTap: _pickDate,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_outlined),
              title: const Text('Start time'),
              subtitle: Text(_startTime.format(context)),
              onTap: _pickStart,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_outlined),
              title: const Text('End time'),
              subtitle: Text(_endTime.format(context)),
              onTap: _pickEnd,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Assign')),
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

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/equipment_basket_service.dart';
import '../../../core/services/equipment_kit_service.dart';
import '../../../core/services/scheduled_work_service.dart';
import '../../../core/state/employee_session.dart';
import '../../../models/equipment.dart';
import '../../../models/equipment_kit.dart';
import '../../../models/scheduled_work.dart';
import '../../../shared/widgets/app_scaffold.dart';
import 'equipment_item_picker_dialog.dart';

/// build a basket: optionally start from a saved kit, add/remove equipment
/// and supply items with quantities, pick one shared date/time window, and
/// (when not already opened from a job) optionally link it to one. Reachable
/// both standalone (Equipment tab's "New basket") and pre-linked to a job
/// (job detail page's "Assign equipment").
class EquipmentBasketBuilderPage extends StatefulWidget {
  const EquipmentBasketBuilderPage({
    required this.role,
    this.authToken,
    this.workId,
    this.jobAddress,
    this.initialDate,
    super.key,
  });

  final String role;
  final String? authToken;

  /// when set, this basket is pre-linked to a job and the job-picker is
  /// hidden — matches how a single-item reservation could already be linked
  /// to a job via EquipmentReservation.workId.
  final String? workId;
  final String? jobAddress;
  final DateTime? initialDate;

  @override
  State<EquipmentBasketBuilderPage> createState() =>
      _EquipmentBasketBuilderPageState();
}

class _DraftLine {
  _DraftLine({
    required this.equipmentId,
    required this.name,
    required this.type,
    required this.quantity,
  });

  final String equipmentId;
  final String name;
  final String type;
  int quantity;

  bool get isEquipment => type == EquipmentType.equipment;
}

class _EquipmentBasketBuilderPageState
    extends State<EquipmentBasketBuilderPage> {
  final List<_DraftLine> _lines = [];
  String _kitId = '';
  String _kitName = '';

  late DateTime _date = widget.initialDate != null
      ? DateTime(widget.initialDate!.year, widget.initialDate!.month,
          widget.initialDate!.day)
      : DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  late TimeOfDay _startTime = widget.initialDate != null
      ? TimeOfDay.fromDateTime(widget.initialDate!)
      : TimeOfDay.now();
  late TimeOfDay _endTime = _defaultEndTime();

  ScheduledWork? _linkedJob;
  bool _isSaving = false;
  String? _error;

  bool get _isJobLinked => (widget.workId ?? '').isNotEmpty;

  TimeOfDay _defaultEndTime() {
    final start = widget.initialDate ??
        DateTime(_date.year, _date.month, _date.day, _startTime.hour, _startTime.minute);
    final naiveEnd = start.add(const Duration(hours: 4));
    if (naiveEnd.year == start.year &&
        naiveEnd.month == start.month &&
        naiveEnd.day == start.day) {
      return TimeOfDay.fromDateTime(naiveEnd);
    }
    return const TimeOfDay(hour: 23, minute: 59);
  }

  ({String id, String name}) _actor() {
    if (widget.role == 'owner') return (id: 'owner', name: 'Owner');
    final profile = EmployeeSession.profile.value;
    if (profile != null) {
      return (id: profile.employeeId, name: profile.fullName);
    }
    return (id: 'unknown', name: 'Unknown');
  }

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
    final picked = await showTimePicker(context: context, initialTime: _startTime);
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(context: context, initialTime: _endTime);
    if (picked != null) setState(() => _endTime = picked);
  }

  DateTime _combine(TimeOfDay time) =>
      DateTime(_date.year, _date.month, _date.day, time.hour, time.minute);

  void _applyKit(EquipmentKit kit) {
    setState(() {
      _kitId = kit.id;
      _kitName = kit.name;
      _lines
        ..clear()
        ..addAll(kit.items.map((item) => _DraftLine(
              equipmentId: item.equipmentId,
              name: item.name,
              type: item.type,
              quantity: item.quantity,
            )));
    });
  }

  Future<void> _addItem() async {
    final item = await showDialog<EquipmentItem>(
      context: context,
      builder: (_) => const EquipmentItemPickerDialog(),
    );
    if (item == null) return;
    final existingIndex = _lines.indexWhere((l) => l.equipmentId == item.id);
    if (existingIndex >= 0) {
      _snack('${item.name} is already in this basket — adjust its quantity below.');
      return;
    }
    setState(() {
      _lines.add(_DraftLine(
        equipmentId: item.id,
        name: item.name,
        type: item.type,
        quantity: 1,
      ));
    });
  }

  void _removeLine(_DraftLine line) {
    setState(() => _lines.remove(line));
  }

  void _changeQuantity(_DraftLine line, int delta) {
    setState(() {
      final next = line.quantity + delta;
      if (next >= 1 && next <= 99) line.quantity = next;
    });
  }

  Future<void> _submit() async {
    if (_lines.isEmpty) {
      _snack('Add at least one item to the basket.');
      return;
    }
    final start = _combine(_startTime);
    final end = _combine(_endTime);
    if (!start.isBefore(end)) {
      _snack('End time must be after start time.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final actor = _actor();
      final equipmentLines = _lines
          .where((l) => l.isEquipment)
          .map((l) => BasketLineRequest(equipmentId: l.equipmentId, quantity: l.quantity))
          .toList();
      final supplyLines = _lines
          .where((l) => !l.isEquipment)
          .map((l) => BasketLineRequest(equipmentId: l.equipmentId, quantity: l.quantity))
          .toList();

      await EquipmentBasketService.createBasket(
        equipmentLines: equipmentLines,
        supplyLines: supplyLines,
        startTime: start,
        endTime: end,
        employeeId: actor.id,
        employeeName: actor.name,
        workId: widget.workId ?? _linkedJob?.id ?? '',
        jobAddress: widget.jobAddress ?? _linkedJob?.address ?? '',
        kitId: _kitId,
        kitName: _kitName,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('MMM d, yyyy').format(_date);

    return AppScaffold(
      title: 'New Basket',
      role: widget.role,
      authToken: widget.authToken,
      selectedRoute: AppRouter.equipmentCatalog,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.jobAddress != null && widget.jobAddress!.isNotEmpty)
            Card(
              color: Colors.indigo.withValues(alpha: 0.06),
              child: ListTile(
                leading: const Icon(Icons.work_outline, color: Colors.indigo),
                title: const Text('Linked to job'),
                subtitle: Text(widget.jobAddress!),
              ),
            ),
          const SizedBox(height: 8),
          Text('Start from a kit (optional)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          StreamBuilder<List<EquipmentKit>>(
            stream: EquipmentKitService.watchAllKits(),
            builder: (context, snapshot) {
              final kits = snapshot.data ?? const <EquipmentKit>[];
              if (kits.isEmpty) {
                return Text(
                  'No saved kits yet — add items below, or save a kit from the Equipment tab.',
                  style: Theme.of(context).textTheme.bodySmall,
                );
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final kit in kits)
                    ChoiceChip(
                      label: Text(kit.name),
                      selected: _kitId == kit.id,
                      onSelected: (_) => _applyKit(kit),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text('Items', style: Theme.of(context).textTheme.titleMedium),
              ),
              TextButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add),
                label: const Text('Add item'),
              ),
            ],
          ),
          if (_lines.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No items added yet.'),
            )
          else
            for (final line in _lines) _DraftLineRow(
              line: line,
              onIncrement: () => _changeQuantity(line, 1),
              onDecrement: () => _changeQuantity(line, -1),
              onRemove: () => _removeLine(line),
            ),
          const SizedBox(height: 20),
          Text('When', style: Theme.of(context).textTheme.titleMedium),
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
          if (!_isJobLinked) ...[
            const SizedBox(height: 20),
            Text('Link to a job (optional)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            _JobPicker(
              role: widget.role,
              selected: _linkedJob,
              onChanged: (job) => setState(() => _linkedJob = job),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _isSaving ? null : _submit,
            child: _isSaving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Create basket'),
          ),
        ],
      ),
    );
  }
}

class _DraftLineRow extends StatelessWidget {
  const _DraftLineRow({
    required this.line,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });

  final _DraftLine line;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isEquipment = line.isEquipment;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Icon(isEquipment ? Icons.build_outlined : Icons.inventory_outlined,
                color: isEquipment ? Colors.blue : Colors.teal, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(line.name)),
            IconButton(
              onPressed: onDecrement,
              icon: const Icon(Icons.remove, size: 18),
              visualDensity: VisualDensity.compact,
            ),
            Text('${line.quantity}'),
            IconButton(
              onPressed: onIncrement,
              icon: const Icon(Icons.add, size: 18),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

/// optional job-link dropdown for a standalone basket — owner sees every open
/// job, an employee sees their own (mirrors ScheduledWorkService's existing
/// role-based filtering).
class _JobPicker extends StatelessWidget {
  const _JobPicker({required this.role, required this.selected, required this.onChanged});

  final String role;
  final ScheduledWork? selected;
  final void Function(ScheduledWork?) onChanged;

  @override
  Widget build(BuildContext context) {
    final profile = EmployeeSession.profile.value;
    return StreamBuilder<List<ScheduledWork>>(
      stream: ScheduledWorkService.watchScheduledWork(
        role: role,
        teamId: profile?.teamId,
        employeeId: profile?.employeeId,
      ),
      builder: (context, snapshot) {
        final jobs = (snapshot.data ?? const <ScheduledWork>[])
            .where((job) => !job.isCompleted && !job.isInvoiced)
            .toList();
        final value = selected != null && jobs.any((j) => j.id == selected!.id)
            ? jobs.firstWhere((j) => j.id == selected!.id)
            : null;
        return DropdownButton<ScheduledWork?>(
          isExpanded: true,
          value: value,
          hint: const Text('No job'),
          items: [
            const DropdownMenuItem<ScheduledWork?>(value: null, child: Text('No job')),
            for (final job in jobs)
              DropdownMenuItem<ScheduledWork?>(
                value: job,
                child: Text(
                  '${job.address} · ${DateFormat('MMM d').format(job.scheduledDate)}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onChanged,
        );
      },
    );
  }
}

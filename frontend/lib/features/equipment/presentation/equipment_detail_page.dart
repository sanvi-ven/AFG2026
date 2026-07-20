import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/broken_report_service.dart';
import '../../../core/services/equipment_service.dart';
import '../../../core/state/employee_session.dart';
import '../../../models/broken_report.dart';
import '../../../models/equipment.dart';
import '../../../shared/widgets/app_scaffold.dart';

/// detail view of a catalog item, visible to both roles. Renders the photo
/// gallery + header + badges (Phase 1), and — for Equipment — a per-unit status
/// grid whose chips open a bottom sheet for mark-broken / log-repair /
/// mark-fixed actions (Phase 2). Owner-only: edit, archive/restore, adjust unit
/// count (Equipment), and restock (Supply). Reservation section (Phase 3) and
/// service badges (Phase 4) slot into the section [ListView] later.
class EquipmentDetailPage extends StatelessWidget {
  const EquipmentDetailPage({
    required this.role,
    this.authToken,
    required this.equipmentId,
    super.key,
  });

  final String role;
  final String? authToken;
  final String equipmentId;

  bool get _isOwner => role == 'owner';

  /// who is acting — the owner is attributed as 'owner'/'Owner' (matching
  /// ownerNotificationRecipientId); an employee comes from the active session.
  ({String id, String name}) _actor() {
    if (_isOwner) return (id: 'owner', name: 'Owner');
    final profile = EmployeeSession.profile.value;
    if (profile != null) {
      return (id: profile.employeeId, name: profile.fullName);
    }
    return (id: 'unknown', name: 'Unknown');
  }

  void _openEdit(BuildContext context) {
    Navigator.pushNamed(
      context,
      AppRouter.equipmentForm,
      arguments: {
        'role': role,
        'authToken': authToken,
        'existingId': equipmentId,
      },
    );
  }

  Future<void> _toggleArchive(BuildContext context, EquipmentItem item) async {
    final archiving = !item.isArchived;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(archiving ? 'Archive item' : 'Restore item'),
        content: Text(archiving
            ? 'Archive "${item.name}"? It will be hidden from the catalog.'
            : 'Restore "${item.name}" to the catalog?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(archiving ? 'Archive' : 'Restore')),
        ],
      ),
    );
    if (confirmed != true) return;

    if (archiving) {
      await EquipmentService.archiveEquipment(item.id);
    } else {
      await EquipmentService.restoreEquipment(item.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Equipment',
      role: role,
      authToken: authToken,
      selectedRoute: AppRouter.equipmentCatalog,
      body: StreamBuilder<EquipmentItem?>(
        stream: EquipmentService.watchOne(equipmentId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Failed to load: ${snapshot.error}'));
          }
          final item = snapshot.data;
          if (item == null) {
            return const Center(child: Text('This item no longer exists.'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildGallery(item),
              const SizedBox(height: 16),
              _buildHeader(context, item),
              const SizedBox(height: 16),
              if (_isOwner) _buildOwnerActions(context, item),
              if (item.isEquipment) ...[
                const SizedBox(height: 24),
                _buildUnitSection(context, item),
              ],
              // Phase 3: reservation / request section slots in here.
              // Phase 4: service history + due badges slot in here.
            ],
          );
        },
      ),
    );
  }

  Widget _buildGallery(EquipmentItem item) {
    if (item.photoUrls.isEmpty) {
      return Container(
        height: 160,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.build_outlined, size: 48, color: Colors.grey.shade500),
      );
    }

    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: item.photoUrls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              item.photoUrls[index],
              width: 200,
              height: 160,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 200,
                height: 160,
                color: Colors.grey.shade200,
                alignment: Alignment.center,
                child: Icon(Icons.broken_image_outlined,
                    color: Colors.grey.shade500),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, EquipmentItem item) {
    final quantityLabel = item.isSupply && item.unitOfMeasure.isNotEmpty
        ? '${item.quantity} ${item.unitOfMeasure}'
        : '${item.quantity}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.name, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _TypeBadge(type: item.type),
            if (item.isArchived) const _Pill(label: 'Archived', color: Colors.grey),
            if (item.isLowStock)
              const _Pill(label: 'Low stock', color: Colors.orange),
          ],
        ),
        const SizedBox(height: 12),
        Text(item.isSupply ? 'On hand: $quantityLabel' : 'Units: $quantityLabel',
            style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }

  Widget _buildOwnerActions(BuildContext context, EquipmentItem item) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: () => _openEdit(context),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Edit'),
        ),
        OutlinedButton.icon(
          onPressed: () => _toggleArchive(context, item),
          icon: Icon(
              item.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
              size: 18),
          label: Text(item.isArchived ? 'Restore' : 'Archive'),
        ),
        if (item.isEquipment)
          OutlinedButton.icon(
            onPressed: () => _adjustUnits(context, item),
            icon: const Icon(Icons.tune_outlined, size: 18),
            label: const Text('Adjust Units'),
          ),
        if (item.isSupply)
          OutlinedButton.icon(
            onPressed: () => _restock(context, item),
            icon: const Icon(Icons.add_box_outlined, size: 18),
            label: const Text('Restock'),
          ),
      ],
    );
  }

  // --- per-unit status grid (Equipment only) --------------------------------

  Widget _buildUnitSection(BuildContext context, EquipmentItem item) {
    final units = List<EquipmentUnit>.from(item.units)
      ..sort((a, b) => a.unitNumber.compareTo(b.unitNumber));

    return StreamBuilder<List<BrokenReport>>(
      stream: BrokenReportService.watchForEquipment(item.id),
      builder: (context, snapshot) {
        final reports = snapshot.data ?? const <BrokenReport>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Units', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (units.isEmpty)
              const Text('No units.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final unit in units)
                    _UnitChip(
                      unit: unit,
                      onTap: () =>
                          _showUnitSheet(context, item, unit, reports),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }

  BrokenReport? _openReportFor(List<BrokenReport> reports, int unitNumber) {
    for (final report in reports) {
      if (report.unitNumber == unitNumber && report.isOpen) return report;
    }
    return null;
  }

  Future<void> _showUnitSheet(
    BuildContext pageContext,
    EquipmentItem item,
    EquipmentUnit unit,
    List<BrokenReport> reports,
  ) async {
    final openReport = _openReportFor(reports, unit.unitNumber);

    await showModalBottomSheet<void>(
      context: pageContext,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: 16 + MediaQuery.of(sheetCtx).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Unit #${unit.unitNumber}',
                          style:
                              Theme.of(sheetCtx).textTheme.titleLarge),
                      const SizedBox(width: 12),
                      _StatusPill(status: unit.status),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _serviceInfo(sheetCtx, unit),
                  if (openReport != null) ...[
                    const SizedBox(height: 16),
                    _reportDetails(sheetCtx, openReport),
                  ],
                  const SizedBox(height: 20),
                  ..._unitActions(pageContext, sheetCtx, item, unit, openReport),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _serviceInfo(BuildContext context, EquipmentUnit unit) {
    final last = unit.lastServiceDate;
    final next = unit.nextServiceDueDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          last == null
              ? 'Not yet serviced'
              : 'Last serviced: ${_fmtDate(last)}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (next != null) ...[
          const SizedBox(height: 4),
          Text('Next service due: ${_fmtDate(next)}',
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    );
  }

  Widget _reportDetails(BuildContext context, BrokenReport report) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Reported issue',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(report.note.isEmpty ? '(no note)' : report.note),
        const SizedBox(height: 4),
        Text(
          'by ${report.reportedByEmployeeName} · ${_fmtDateTime(report.reportedAt)}',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.grey.shade600),
        ),
        if (report.repairAttempts.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Repair attempts (${report.repairAttempts.length})',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          for (final attempt in report.repairAttempts)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(attempt.note.isEmpty ? '(no note)' : attempt.note),
                  Text(
                    'by ${attempt.employeeName} · ${_fmtDateTime(attempt.attemptedAt)}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  List<Widget> _unitActions(
    BuildContext pageContext,
    BuildContext sheetCtx,
    EquipmentItem item,
    EquipmentUnit unit,
    BrokenReport? openReport,
  ) {
    if (unit.status == EquipmentUnitStatus.active) {
      return [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              Navigator.of(sheetCtx).pop();
              _markBroken(pageContext, item, unit);
            },
            icon: const Icon(Icons.report_problem_outlined, size: 18),
            label: const Text('Mark broken'),
          ),
        ),
      ];
    }

    // broken or inRepair — need the open report to act on.
    if (openReport == null) {
      return [
        const Text(
          'No open report found for this unit. It may have just been '
          'resolved — reopen this sheet.',
        ),
      ];
    }

    return [
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () {
            Navigator.of(sheetCtx).pop();
            _logRepair(pageContext, openReport);
          },
          icon: const Icon(Icons.build_outlined, size: 18),
          label: const Text('Log repair attempt'),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () {
            Navigator.of(sheetCtx).pop();
            _markFixed(pageContext, openReport);
          },
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('Mark fixed'),
        ),
      ),
    ];
  }

  // --- action handlers (try/catch + SnackBar + mounted guard) ---------------

  Future<void> _markBroken(
      BuildContext context, EquipmentItem item, EquipmentUnit unit) async {
    final note = await _promptNote(
      context,
      title: 'Mark unit #${unit.unitNumber} broken',
      label: 'What is wrong?',
      requireNote: true,
    );
    if (note == null) return;

    try {
      final actor = _actor();
      await BrokenReportService.reportBroken(
        equipmentId: item.id,
        unitNumber: unit.unitNumber,
        note: note,
        employeeId: actor.id,
        employeeName: actor.name,
      );
      if (!context.mounted) return;
      _snack(context, 'Unit #${unit.unitNumber} marked broken.');
    } catch (error) {
      if (!context.mounted) return;
      _snack(context, _errorText(error));
    }
  }

  Future<void> _logRepair(BuildContext context, BrokenReport report) async {
    final note = await _promptNote(
      context,
      title: 'Log repair attempt',
      label: 'What did you try?',
      requireNote: true,
    );
    if (note == null) return;

    try {
      final actor = _actor();
      await BrokenReportService.logRepairAttempt(
        brokenReportId: report.id,
        note: note,
        employeeId: actor.id,
        employeeName: actor.name,
      );
      if (!context.mounted) return;
      _snack(context, 'Repair attempt logged.');
    } catch (error) {
      if (!context.mounted) return;
      _snack(context, _errorText(error));
    }
  }

  Future<void> _markFixed(BuildContext context, BrokenReport report) async {
    final note = await _promptNote(
      context,
      title: 'Mark unit #${report.unitNumber} fixed',
      label: 'Resolution note (optional)',
      requireNote: false,
    );
    if (note == null) return;

    try {
      await BrokenReportService.markFixed(
        brokenReportId: report.id,
        resolvedNote: note,
      );
      if (!context.mounted) return;
      _snack(context, 'Unit #${report.unitNumber} marked fixed.');
    } catch (error) {
      if (!context.mounted) return;
      _snack(context, _errorText(error));
    }
  }

  Future<void> _adjustUnits(BuildContext context, EquipmentItem item) async {
    final current = item.units.length;
    final newQuantity = await _promptInt(
      context,
      title: 'Adjust units',
      label: 'Number of units',
      initialValue: current,
      helperText: 'Currently $current. Broken / in-repair units can\'t be '
          'removed until resolved.',
      allowNegative: false,
    );
    if (newQuantity == null || newQuantity == current) return;

    try {
      await EquipmentService.adjustEquipmentUnitCount(
        equipmentId: item.id,
        newQuantity: newQuantity,
      );
      if (!context.mounted) return;
      _snack(context, 'Units updated to $newQuantity.');
    } catch (error) {
      if (!context.mounted) return;
      _snack(context, _errorText(error));
    }
  }

  Future<void> _restock(BuildContext context, EquipmentItem item) async {
    final delta = await _promptInt(
      context,
      title: 'Restock ${item.name}',
      label: 'Change in on-hand quantity',
      initialValue: 0,
      helperText: 'Use a negative number to consume stock. On hand: '
          '${item.quantity}.',
      allowNegative: true,
    );
    if (delta == null || delta == 0) return;

    try {
      await EquipmentService.adjustSupplyQuantity(
        equipmentId: item.id,
        delta: delta,
      );
      if (!context.mounted) return;
      _snack(context, 'Stock adjusted by $delta.');
    } catch (error) {
      if (!context.mounted) return;
      _snack(context, _errorText(error));
    }
  }

  // --- dialogs --------------------------------------------------------------

  /// prompt for a note. Returns null if cancelled, the trimmed text otherwise
  /// (empty allowed only when [requireNote] is false).
  Future<String?> _promptNote(
    BuildContext context, {
    required String title,
    required String label,
    required bool requireNote,
  }) {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(labelText: label),
            validator: requireNote
                ? (value) => (value == null || value.trim().isEmpty)
                    ? 'Please enter a note.'
                    : null
                : null,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (requireNote && !(formKey.currentState?.validate() ?? false)) {
                return;
              }
              Navigator.of(ctx).pop(controller.text.trim());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  /// prompt for an integer. Returns null if cancelled or invalid-and-dismissed.
  Future<int?> _promptInt(
    BuildContext context, {
    required String title,
    required String label,
    required int initialValue,
    required String helperText,
    required bool allowNegative,
  }) {
    final controller = TextEditingController(text: '$initialValue');
    final formKey = GlobalKey<FormState>();

    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.numberWithOptions(
                signed: allowNegative, decimal: false),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                  RegExp(allowNegative ? r'[0-9-]' : r'[0-9]')),
            ],
            decoration: InputDecoration(
              labelText: label,
              helperText: helperText,
              helperMaxLines: 3,
            ),
            validator: (value) {
              final parsed = int.tryParse((value ?? '').trim());
              if (parsed == null) return 'Enter a whole number.';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.of(ctx).pop(int.parse(controller.text.trim()));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // --- small helpers --------------------------------------------------------

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _errorText(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtDateTime(DateTime d) =>
      '${_fmtDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _UnitChip extends StatelessWidget {
  const _UnitChip({required this.unit, required this.onTap});

  final EquipmentUnit unit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(unit.status);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Unit #${unit.unitNumber}',
                style: TextStyle(color: color, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(_statusLabel(unit.status),
                style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return _Pill(label: _statusLabel(status), color: _statusColor(status));
  }
}

Color _statusColor(String status) {
  switch (status) {
    case EquipmentUnitStatus.broken:
      return Colors.red;
    case EquipmentUnitStatus.inRepair:
      return Colors.orange;
    case EquipmentUnitStatus.active:
    default:
      return Colors.green;
  }
}

String _statusLabel(String status) {
  switch (status) {
    case EquipmentUnitStatus.broken:
      return 'Broken';
    case EquipmentUnitStatus.inRepair:
      return 'In repair';
    case EquipmentUnitStatus.active:
    default:
      return 'Active';
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final isEquipment = type == EquipmentType.equipment;
    return _Pill(
      label: isEquipment ? 'Equipment' : 'Supply',
      color: isEquipment ? Colors.blue : Colors.teal,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

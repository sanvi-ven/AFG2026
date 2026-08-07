import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/broken_report_service.dart';
import '../../../core/services/equipment_reservation_service.dart';
import '../../../core/services/equipment_service.dart';
import '../../../core/services/service_record_service.dart';
import '../../../core/state/employee_session.dart';
import '../../../models/broken_report.dart';
import '../../../models/equipment.dart';
import '../../../models/equipment_reservation.dart';
import '../../../models/service_record.dart';
import '../../../shared/widgets/app_scaffold.dart';

/// detail view of a catalog item, visible to both roles with full parity:
/// edit, archive/restore, adjust unit count (Equipment), restock (Supply),
/// and cancel any reservation are available to owner and employee alike.
/// Renders the photo gallery + header + badges (Phase 1), and — for
/// Equipment — a per-unit status grid whose chips open a bottom sheet for
/// mark-broken / log-repair / mark-fixed actions (Phase 2). Reservation
/// section (Phase 3) and service badges (Phase 4) slot into the section
/// [ListView] later.
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

  /// how far ahead a unit's next-service date counts as "due soon" — shared
  /// with ReminderCheckService so the badge and the notification always agree.
  static const _serviceDueLeadTime = equipmentServiceDueLeadTime;

  bool get _isOwner => role == 'owner';

  /// true when a unit's next service is within the lead time (or already past)
  /// and not currently snoozed.
  bool _isServiceDue(EquipmentUnit unit) {
    final due = unit.nextServiceDueDate;
    if (due == null) return false;
    final now = DateTime.now();
    final snoozed = unit.serviceDueSnoozedUntil;
    if (snoozed != null && snoozed.isAfter(now)) return false;
    return !due.isAfter(now.add(_serviceDueLeadTime));
  }

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

    try {
      if (archiving) {
        await EquipmentService.archiveEquipment(item.id);
      } else {
        await EquipmentService.restoreEquipment(item.id);
      }
      if (!context.mounted) return;
      _snack(context, archiving ? 'Item archived.' : 'Item restored.');
    } catch (error) {
      if (!context.mounted) return;
      _snack(context, _errorText(error));
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
              _buildCatalogActions(context, item),
              if (item.isEquipment) ...[
                const SizedBox(height: 24),
                _buildUnitSection(context, item),
                const SizedBox(height: 24),
                _buildRequestSection(context, item),
                const SizedBox(height: 24),
                _buildReservationHistory(context, item),
                const SizedBox(height: 24),
                _buildServiceHistory(context, item),
                const SizedBox(height: 24),
                _buildActivityTimeline(context, item),
              ],
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

  Widget _buildCatalogActions(BuildContext context, EquipmentItem item) {
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

  // --- reservations (Equipment only) ----------------------------------------

  /// number of units currently in an active (reservable) state — the physical
  /// ceiling on how many can be requested at once. The real per-window
  /// conflict check happens in the service.
  int _availableUnitCount(EquipmentItem item) => item.units
      .where((u) => u.status == EquipmentUnitStatus.active)
      .length;

  Widget _buildRequestSection(BuildContext context, EquipmentItem item) {
    final available = _availableUnitCount(item);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Request', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          available == 0
              ? 'No active units are available to reserve right now.'
              : 'Reserve a unit for a day and time window. It\'s approved '
                  'automatically if a unit is free.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: available == 0
                ? null
                : () => _requestEquipment(context, item),
            icon: const Icon(Icons.event_available_outlined, size: 18),
            label: const Text('Request this equipment'),
          ),
        ),
      ],
    );
  }

  Widget _buildReservationHistory(BuildContext context, EquipmentItem item) {
    return StreamBuilder<List<EquipmentReservation>>(
      stream: EquipmentReservationService.watchForEquipment(item.id),
      builder: (context, snapshot) {
        final reservations = snapshot.data ?? const <EquipmentReservation>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reservations',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (snapshot.connectionState == ConnectionState.waiting &&
                reservations.isEmpty)
              const Center(child: CircularProgressIndicator())
            else if (reservations.isEmpty)
              const Text('No reservations yet.')
            else
              for (final reservation in reservations)
                _ReservationRow(
                  reservation: reservation,
                  canCancel: reservation.isActive,
                  onCancel: () => _cancelReservation(context, reservation),
                ),
          ],
        );
      },
    );
  }

  Future<void> _requestEquipment(
      BuildContext context, EquipmentItem item) async {
    final available = _availableUnitCount(item);
    if (available == 0) {
      _snack(context, 'No active units are available to reserve.');
      return;
    }

    final request = await showDialog<_ReserveRequest>(
      context: context,
      builder: (_) => _ReserveDialog(maxQuantity: available),
    );
    if (request == null || !context.mounted) return;

    try {
      final actor = _actor();
      final created = await EquipmentReservationService.reserveUnits(
        equipment: item,
        quantity: request.quantity,
        startTime: request.start,
        endTime: request.end,
        employeeId: actor.id,
        employeeName: actor.name,
      );
      if (!context.mounted) return;
      final units = created.map((r) => '#${r.unitNumber}').join(', ');
      _snack(
          context,
          created.length == 1
              ? 'Reserved unit $units.'
              : 'Reserved units $units.');
    } catch (error) {
      if (!context.mounted) return;
      _snack(context, _errorText(error));
    }
  }

  Future<void> _cancelReservation(
      BuildContext context, EquipmentReservation reservation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel reservation'),
        content: Text(
            'Cancel ${reservation.employeeName}\'s reservation of unit '
            '#${reservation.unitNumber} on ${reservation.date}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Back')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Cancel reservation')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await EquipmentReservationService.cancelReservation(id: reservation.id);
      if (!context.mounted) return;
      _snack(context, 'Reservation cancelled.');
    } catch (error) {
      if (!context.mounted) return;
      _snack(context, _errorText(error));
    }
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
                      serviceDue: _isServiceDue(unit),
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
                  const SizedBox(height: 8),
                  ..._serviceActions(pageContext, sheetCtx, item, unit),
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
    final due = _isServiceDue(unit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Service', style: Theme.of(context).textTheme.titleSmall),
            if (due) ...[
              const SizedBox(width: 8),
              _Pill(label: 'Service due', color: Colors.amber.shade800),
            ],
          ],
        ),
        const SizedBox(height: 4),
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

  /// service-related actions in the unit sheet: "Log service" (both roles),
  /// plus "Snooze" when the unit is currently due.
  List<Widget> _serviceActions(
    BuildContext pageContext,
    BuildContext sheetCtx,
    EquipmentItem item,
    EquipmentUnit unit,
  ) {
    return [
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () {
            Navigator.of(sheetCtx).pop();
            _logService(pageContext, item, unit);
          },
          icon: const Icon(Icons.build_outlined, size: 18),
          label: const Text('Log service'),
        ),
      ),
      if (_isServiceDue(unit)) ...[
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.of(sheetCtx).pop();
              _snoozeService(pageContext, item, unit);
            },
            icon: const Icon(Icons.snooze_outlined, size: 18),
            label: const Text('Snooze service reminder'),
          ),
        ),
      ],
    ];
  }

  Widget _buildServiceHistory(BuildContext context, EquipmentItem item) {
    return StreamBuilder<List<ServiceRecord>>(
      stream: ServiceRecordService.watchForEquipment(item.id),
      builder: (context, snapshot) {
        final records = snapshot.data ?? const <ServiceRecord>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Service history',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (snapshot.connectionState == ConnectionState.waiting &&
                records.isEmpty)
              const Center(child: CircularProgressIndicator())
            else if (records.isEmpty)
              const Text('No service logged yet.')
            else
              for (final record in records) _ServiceRow(record: record),
          ],
        );
      },
    );
  }

  // --- activity timeline (Equipment only) -----------------------------------

  /// a compact, chronological (newest-first) merge of broken reports, repair
  /// attempts, service records, and reservations for this item — synthesized
  /// client-side from the three streams the page already uses elsewhere (no new
  /// collection/service). This is an overview; the dedicated history sections
  /// above still carry the full detail.
  Widget _buildActivityTimeline(BuildContext context, EquipmentItem item) {
    return StreamBuilder<List<BrokenReport>>(
      stream: BrokenReportService.watchForEquipment(item.id),
      builder: (context, brokenSnap) {
        return StreamBuilder<List<ServiceRecord>>(
          stream: ServiceRecordService.watchForEquipment(item.id),
          builder: (context, serviceSnap) {
            return StreamBuilder<List<EquipmentReservation>>(
              stream: EquipmentReservationService.watchForEquipment(item.id),
              builder: (context, reservationSnap) {
                // only show the spinner if NONE of the three sources have
                // emitted yet — otherwise a fast-resolving stream (broken
                // reports is usually smallest) can flash "No activity yet."
                // before the slower service/reservation streams finish.
                final waiting = [brokenSnap, serviceSnap, reservationSnap]
                    .every((s) =>
                        s.connectionState == ConnectionState.waiting &&
                        !s.hasData);
                final events = _buildActivityEvents(
                  broken: brokenSnap.data ?? const <BrokenReport>[],
                  services: serviceSnap.data ?? const <ServiceRecord>[],
                  reservations:
                      reservationSnap.data ?? const <EquipmentReservation>[],
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Activity',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    if (waiting && events.isEmpty)
                      const Center(child: CircularProgressIndicator())
                    else if (events.isEmpty)
                      const Text('No activity yet.')
                    else
                      for (final event in events.take(20))
                        _ActivityRow(event: event),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  /// merge the three sources into a single newest-first list of timeline events.
  List<_ActivityEvent> _buildActivityEvents({
    required List<BrokenReport> broken,
    required List<ServiceRecord> services,
    required List<EquipmentReservation> reservations,
  }) {
    final timeFmt = DateFormat('h:mm a');
    final events = <_ActivityEvent>[];

    for (final report in broken) {
      events.add(_ActivityEvent(
        timestamp: report.reportedAt,
        icon: Icons.report_problem_outlined,
        color: Colors.red,
        description: 'Unit #${report.unitNumber} marked broken',
      ));
      for (final attempt in report.repairAttempts) {
        events.add(_ActivityEvent(
          timestamp: attempt.attemptedAt,
          icon: Icons.build_outlined,
          color: Colors.orange,
          description: 'Repair attempt on unit #${report.unitNumber}',
        ));
      }
      if (report.resolvedAt != null) {
        events.add(_ActivityEvent(
          timestamp: report.resolvedAt!,
          icon: Icons.check_circle_outline,
          color: Colors.green,
          description: 'Unit #${report.unitNumber} marked fixed',
        ));
      }
    }

    for (final record in services) {
      events.add(_ActivityEvent(
        timestamp: record.createdAt,
        icon: Icons.handyman_outlined,
        color: Colors.blue,
        description: 'Service logged on unit #${record.unitNumber}',
      ));
    }

    for (final reservation in reservations) {
      final window =
          '${timeFmt.format(reservation.startTime)}–${timeFmt.format(reservation.endTime)}';
      events.add(_ActivityEvent(
        timestamp: reservation.createdAt,
        icon: Icons.event_available_outlined,
        color: Colors.indigo,
        description:
            'Unit #${reservation.unitNumber} reserved by ${reservation.employeeName} for $window',
      ));
      if (reservation.isCancelled && reservation.cancelledAt != null) {
        events.add(_ActivityEvent(
          timestamp: reservation.cancelledAt!,
          icon: Icons.event_busy_outlined,
          color: Colors.grey,
          description:
              'Reservation of unit #${reservation.unitNumber} cancelled',
        ));
      }
    }

    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return events;
  }

  Future<void> _logService(
      BuildContext context, EquipmentItem item, EquipmentUnit unit) async {
    final request = await showDialog<_LogServiceRequest>(
      context: context,
      builder: (_) => _LogServiceDialog(
        defaultInterval:
            unit.serviceIntervalDays ?? item.defaultServiceIntervalDays,
      ),
    );
    if (request == null || !context.mounted) return;

    try {
      final actor = _actor();
      await ServiceRecordService.logService(
        equipmentId: item.id,
        unitNumber: unit.unitNumber,
        servicedDate: request.servicedDate,
        note: request.note,
        mode: request.mode,
        explicitNextDate: request.explicitNextDate,
        intervalDays: request.intervalDays,
        recordedByRole: role,
        recordedById: actor.id,
        recordedByName: actor.name,
      );
      if (!context.mounted) return;
      _snack(context, 'Service logged for unit #${unit.unitNumber}.');
    } catch (error) {
      if (!context.mounted) return;
      _snack(context, _errorText(error));
    }
  }

  Future<void> _snoozeService(
      BuildContext context, EquipmentItem item, EquipmentUnit unit) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      helpText: 'Snooze service reminder until',
      initialDate: now.add(const Duration(days: 7)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null || !context.mounted) return;
    // showDatePicker returns a date-only DateTime (midnight) — normalize to
    // end-of-day so "snooze until tomorrow" actually means ~24h, not however
    // many hours remain until midnight tonight.
    final until = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);

    try {
      await EquipmentService.snoozeUnitServiceDue(
        equipmentId: item.id,
        unitNumber: unit.unitNumber,
        until: until,
      );
      if (!context.mounted) return;
      _snack(context, 'Service reminder snoozed to ${_fmtDate(picked)}.');
    } catch (error) {
      if (!context.mounted) return;
      _snack(context, _errorText(error));
    }
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
    ).whenComplete(controller.dispose);
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
    ).whenComplete(controller.dispose);
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

/// the collected inputs from [_ReserveDialog], handed back to the page which
/// owns the actual service call + SnackBar.
class _ReserveRequest {
  const _ReserveRequest({
    required this.quantity,
    required this.start,
    required this.end,
  });

  final int quantity;
  final DateTime start;
  final DateTime end;
}

/// quantity + date + start/end-time picker for a reservation. Follows the
/// codebase's manual showDatePicker + showTimePicker pattern (no date-range
/// package), keeping separate start/end time-of-day state fields.
class _ReserveDialog extends StatefulWidget {
  const _ReserveDialog({required this.maxQuantity});

  final int maxQuantity;

  @override
  State<_ReserveDialog> createState() => _ReserveDialogState();
}

class _ReserveDialogState extends State<_ReserveDialog> {
  int _quantity = 1;
  DateTime _date = DateTime.now();
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime ?? _startTime ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _endTime = picked);
  }

  DateTime _combine(TimeOfDay time) =>
      DateTime(_date.year, _date.month, _date.day, time.hour, time.minute);

  void _submit() {
    if (_startTime == null || _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a start and end time.')),
      );
      return;
    }
    final start = _combine(_startTime!);
    final end = _combine(_endTime!);
    if (!start.isBefore(end)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time.')),
      );
      return;
    }
    Navigator.of(context).pop(_ReserveRequest(
      quantity: _quantity,
      start: start,
      end: end,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('MMM d, yyyy').format(_date);
    return AlertDialog(
      title: const Text('Request equipment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Quantity'),
            const SizedBox(height: 4),
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
                  onPressed: _quantity < widget.maxQuantity
                      ? () => setState(() => _quantity++)
                      : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            Text('${widget.maxQuantity} unit(s) available',
                style: Theme.of(context).textTheme.bodySmall),
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
              subtitle:
                  Text(_startTime == null ? 'Not set' : _startTime!.format(context)),
              onTap: _pickStart,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_outlined),
              title: const Text('End time'),
              subtitle:
                  Text(_endTime == null ? 'Not set' : _endTime!.format(context)),
              onTap: _pickEnd,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Reserve')),
      ],
    );
  }
}

/// one row in the detail-page reservation history: unit, date, time window,
/// employee, and an active/cancelled indicator (+ owner-only cancel action).
class _ReservationRow extends StatelessWidget {
  const _ReservationRow({
    required this.reservation,
    required this.canCancel,
    required this.onCancel,
  });

  final EquipmentReservation reservation;
  final bool canCancel;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('h:mm a');
    final window =
        '${timeFmt.format(reservation.startTime)} – ${timeFmt.format(reservation.endTime)}';
    final cancelled = reservation.isCancelled;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          child: Text('#${reservation.unitNumber}',
              style: const TextStyle(fontSize: 12)),
        ),
        title: Text('${reservation.date} · $window'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(reservation.employeeName),
            if (reservation.isLinkedToJob) ...[
              const SizedBox(height: 4),
              _Pill(
                label: 'Job: ${reservation.jobAddress}',
                color: Colors.indigo,
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Pill(
              label: cancelled ? 'Cancelled' : 'Active',
              color: cancelled ? Colors.grey : Colors.green,
            ),
            if (canCancel) ...[
              const SizedBox(width: 4),
              IconButton(
                onPressed: onCancel,
                icon: const Icon(Icons.cancel_outlined),
                tooltip: 'Cancel reservation',
                iconSize: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// the collected inputs from [_LogServiceDialog], handed back to the page which
/// owns the actual service call + SnackBar.
class _LogServiceRequest {
  const _LogServiceRequest({
    required this.servicedDate,
    required this.note,
    required this.mode,
    this.explicitNextDate,
    this.intervalDays,
  });

  final DateTime servicedDate;
  final String note;
  final String mode;
  final DateTime? explicitNextDate;
  final int? intervalDays;
}

/// serviced-date + note + a mode toggle (explicit next date vs interval days)
/// for logging a service record. Follows the codebase's manual showDatePicker
/// pattern; the interval field is prefilled from the unit/item default.
class _LogServiceDialog extends StatefulWidget {
  const _LogServiceDialog({this.defaultInterval});

  final int? defaultInterval;

  @override
  State<_LogServiceDialog> createState() => _LogServiceDialogState();
}

class _LogServiceDialogState extends State<_LogServiceDialog> {
  DateTime _servicedDate = DateTime.now();
  final _noteController = TextEditingController();
  late final TextEditingController _intervalController;
  String _mode = ServiceDueMode.intervalDays;
  DateTime? _explicitNextDate;

  @override
  void initState() {
    super.initState();
    _intervalController = TextEditingController(
      text: widget.defaultInterval != null ? '${widget.defaultInterval}' : '',
    );
  }

  @override
  void dispose() {
    _noteController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  Future<void> _pickServicedDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _servicedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _servicedDate = picked);
  }

  Future<void> _pickExplicitNextDate() async {
    final base = _explicitNextDate ?? _servicedDate.add(const Duration(days: 90));
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: _servicedDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _explicitNextDate = picked);
  }

  void _submit() {
    if (_mode == ServiceDueMode.intervalDays) {
      final interval = int.tryParse(_intervalController.text.trim());
      if (interval == null || interval <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a positive number of days.')),
        );
        return;
      }
      Navigator.of(context).pop(_LogServiceRequest(
        servicedDate: _servicedDate,
        note: _noteController.text.trim(),
        mode: ServiceDueMode.intervalDays,
        intervalDays: interval,
      ));
    } else {
      if (_explicitNextDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pick the next service date.')),
        );
        return;
      }
      Navigator.of(context).pop(_LogServiceRequest(
        servicedDate: _servicedDate,
        note: _noteController.text.trim(),
        mode: ServiceDueMode.explicitDate,
        explicitNextDate: _explicitNextDate,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Log service'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Serviced on'),
              subtitle: Text(DateFormat('MMM d, yyyy').format(_servicedDate)),
              onTap: _pickServicedDate,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Note (what was done)',
              ),
            ),
            const SizedBox(height: 16),
            Text('Next service due',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: ServiceDueMode.intervalDays,
                    label: Text('Interval'),
                    icon: Icon(Icons.repeat)),
                ButtonSegment(
                    value: ServiceDueMode.explicitDate,
                    label: Text('Date'),
                    icon: Icon(Icons.event)),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) =>
                  setState(() => _mode = selection.first),
            ),
            const SizedBox(height: 12),
            if (_mode == ServiceDueMode.intervalDays)
              TextField(
                controller: _intervalController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: 'Days until next service',
                  suffixText: 'days',
                ),
              )
            else
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Next service date'),
                subtitle: Text(_explicitNextDate == null
                    ? 'Not set'
                    : DateFormat('MMM d, yyyy').format(_explicitNextDate!)),
                onTap: _pickExplicitNextDate,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

/// one row in the detail-page service history: serviced date, note, next-due
/// date, and who logged it.
class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.record});

  final ServiceRecord record;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('MMM d, yyyy');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          child: Text('#${record.unitNumber}',
              style: const TextStyle(fontSize: 12)),
        ),
        title: Text('Serviced ${dateFmt.format(record.servicedDate)}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (record.note.isNotEmpty) Text(record.note),
            Text('Next due: ${dateFmt.format(record.nextServiceDueDate)}'),
            Text(
              'by ${record.recordedByName.isEmpty ? 'Unknown' : record.recordedByName}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey.shade600),
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _UnitChip extends StatelessWidget {
  const _UnitChip({
    required this.unit,
    required this.serviceDue,
    required this.onTap,
  });

  final EquipmentUnit unit;
  final bool serviceDue;
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Unit #${unit.unitNumber}',
                    style:
                        TextStyle(color: color, fontWeight: FontWeight.w700)),
                if (serviceDue) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.build_circle_outlined,
                      size: 14, color: Colors.amber.shade800),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(_statusLabel(unit.status),
                style: TextStyle(color: color, fontSize: 11)),
            if (serviceDue)
              Text('Service due',
                  style:
                      TextStyle(color: Colors.amber.shade800, fontSize: 10)),
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

/// one synthesized timeline entry merged from broken/service/reservation data.
class _ActivityEvent {
  const _ActivityEvent({
    required this.timestamp,
    required this.icon,
    required this.color,
    required this.description,
  });

  final DateTime timestamp;
  final IconData icon;
  final Color color;
  final String description;
}

/// one compact row in the activity timeline: icon + description + timestamp.
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.event});

  final _ActivityEvent event;

  @override
  Widget build(BuildContext context) {
    final stamp = DateFormat('MMM d, yyyy · h:mm a').format(event.timestamp);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(event.icon, size: 18, color: event.color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.description,
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(stamp,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

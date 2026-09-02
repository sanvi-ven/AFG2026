import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/equipment_basket.dart';
import '../../../models/equipment_reservation.dart';

/// shared basket display used by the owner schedule tab, "My Equipment", and
/// the job detail page's Equipment card — a header (kit/job context, time
/// window, derived status) with bulk check-out/return/cancel actions, and an
/// expandable line list where each line keeps its own per-item action too
/// (an item coming back early/broken shouldn't be blocked on the rest of the
/// basket). Any action whose callback is left null simply doesn't render,
/// so callers can offer exactly the actions that make sense for their screen
/// (e.g. no cancel in a read-only "Past" list).
class EquipmentBasketCard extends StatefulWidget {
  const EquipmentBasketCard({
    required this.basket,
    required this.reservations,
    this.onCheckOutAll,
    this.onReturnAll,
    this.onCancelAll,
    this.onCheckOutOne,
    this.onReturnOne,
    this.onCancelOne,
    this.initiallyExpanded = false,
    super.key,
  });

  final EquipmentBasket basket;

  /// this basket's own reservations (already filtered by basketId).
  final List<EquipmentReservation> reservations;

  final VoidCallback? onCheckOutAll;
  final VoidCallback? onReturnAll;
  final VoidCallback? onCancelAll;
  final void Function(EquipmentReservation reservation)? onCheckOutOne;
  final void Function(EquipmentReservation reservation)? onReturnOne;
  final void Function(EquipmentReservation reservation)? onCancelOne;
  final bool initiallyExpanded;

  @override
  State<EquipmentBasketCard> createState() => _EquipmentBasketCardState();
}

class _EquipmentBasketCardState extends State<EquipmentBasketCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final basket = widget.basket;
    final activeReservations =
        widget.reservations.where((r) => r.isActive).toList()
          ..sort((a, b) => a.unitNumber.compareTo(b.unitNumber));
    final status = basket.computeStatus(widget.reservations);
    final timeFmt = DateFormat('h:mm a');
    final window =
        '${timeFmt.format(basket.startTime)} – ${timeFmt.format(basket.endTime)}';
    final lineCount = activeReservations.length + basket.supplyLines.length;

    final canCheckOutAll = widget.onCheckOutAll != null &&
        (status == EquipmentBasketStatus.reserved ||
            status == EquipmentBasketStatus.partiallyCheckedOut);
    final canReturnAll = widget.onReturnAll != null &&
        (status == EquipmentBasketStatus.checkedOut ||
            status == EquipmentBasketStatus.partiallyReturned);
    final canCancelAll = widget.onCancelAll != null &&
        (status == EquipmentBasketStatus.reserved ||
            status == EquipmentBasketStatus.partiallyCheckedOut);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  const Icon(Icons.shopping_basket_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          basket.startedFromKit
                              ? basket.kitName
                              : 'Basket ($lineCount item${lineCount == 1 ? '' : 's'})',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text('${basket.date} · $window',
                            style: Theme.of(context).textTheme.bodySmall),
                        if (basket.isLinkedToJob) ...[
                          const SizedBox(height: 4),
                          _Pill(
                              label: 'Job: ${basket.jobAddress}',
                              color: Colors.indigo),
                        ],
                      ],
                    ),
                  ),
                  _StatusChip(status: status),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
            if (_expanded) ...[
              const Divider(height: 20),
              for (final reservation in activeReservations)
                _BasketReservationRow(
                  reservation: reservation,
                  onCheckOut: widget.onCheckOutOne == null
                      ? null
                      : () => widget.onCheckOutOne!(reservation),
                  onReturn: widget.onReturnOne == null
                      ? null
                      : () => widget.onReturnOne!(reservation),
                  onCancel: widget.onCancelOne == null
                      ? null
                      : () => widget.onCancelOne!(reservation),
                ),
              for (final line in basket.supplyLines)
                _BasketSupplyRow(line: line),
            ],
            if (canCheckOutAll || canReturnAll || canCancelAll) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (canCancelAll)
                    TextButton(
                      onPressed: widget.onCancelAll,
                      child: const Text('Cancel basket'),
                    ),
                  if (canCancelAll) const SizedBox(width: 8),
                  if (canCheckOutAll)
                    FilledButton.icon(
                      onPressed: widget.onCheckOutAll,
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('Check out basket'),
                    ),
                  if (canReturnAll)
                    FilledButton.icon(
                      onPressed: widget.onReturnAll,
                      icon: const Icon(Icons.login, size: 18),
                      label: const Text('Return basket'),
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

class _BasketReservationRow extends StatelessWidget {
  const _BasketReservationRow({
    required this.reservation,
    this.onCheckOut,
    this.onReturn,
    this.onCancel,
  });

  final EquipmentReservation reservation;
  final VoidCallback? onCheckOut;
  final VoidCallback? onReturn;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final ({String label, Color color}) status;
    if (reservation.returnedAt != null) {
      status = (label: 'Returned', color: Colors.blueGrey);
    } else if (reservation.checkedOutAt != null) {
      status = (label: 'Checked out', color: Colors.green);
    } else {
      status = (label: 'Reserved', color: Colors.blue);
    }

    final showCheckOut = onCheckOut != null && reservation.checkedOutAt == null;
    final showReturn = onReturn != null &&
        reservation.checkedOutAt != null &&
        reservation.returnedAt == null;
    final showCancel = onCancel != null && reservation.checkedOutAt == null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            child: Text('#${reservation.unitNumber}',
                style: const TextStyle(fontSize: 11)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(reservation.equipmentName,
                style: const TextStyle(fontSize: 13)),
          ),
          _Pill(label: status.label, color: status.color),
          if (showCheckOut)
            IconButton(
              onPressed: onCheckOut,
              icon: const Icon(Icons.logout, size: 16),
              tooltip: 'Check out this item',
              visualDensity: VisualDensity.compact,
            ),
          if (showReturn)
            IconButton(
              onPressed: onReturn,
              icon: const Icon(Icons.login, size: 16),
              tooltip: 'Return this item',
              visualDensity: VisualDensity.compact,
            ),
          if (showCancel)
            IconButton(
              onPressed: onCancel,
              icon: const Icon(Icons.cancel_outlined, size: 16),
              tooltip: 'Cancel this item',
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

class _BasketSupplyRow extends StatelessWidget {
  const _BasketSupplyRow({required this.line});

  final EquipmentBasketSupplyLine line;

  @override
  Widget build(BuildContext context) {
    final quantityLabel = line.unitOfMeasure.isEmpty
        ? '${line.quantity}'
        : '${line.quantity} ${line.unitOfMeasure}';
    final consumed = line.consumedAt != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 14,
            child: Icon(Icons.inventory_outlined, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${line.name} · $quantityLabel',
                style: const TextStyle(fontSize: 13)),
          ),
          _Pill(
            label: consumed ? 'Taken' : 'Supply',
            color: consumed ? Colors.blueGrey : Colors.teal,
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final ({String label, Color color}) display;
    switch (status) {
      case EquipmentBasketStatus.cancelled:
        display = (label: 'Cancelled', color: Colors.grey);
        break;
      case EquipmentBasketStatus.returned:
        display = (label: 'Returned', color: Colors.blueGrey);
        break;
      case EquipmentBasketStatus.checkedOut:
        display = (label: 'Checked out', color: Colors.green);
        break;
      case EquipmentBasketStatus.partiallyReturned:
        display = (label: 'Partially returned', color: Colors.blue);
        break;
      case EquipmentBasketStatus.partiallyCheckedOut:
        display = (label: 'Partially checked out', color: Colors.orange);
        break;
      case EquipmentBasketStatus.reserved:
      default:
        display = (label: 'Reserved', color: Colors.amber.shade800);
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: display.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(display.label,
          style: TextStyle(
              fontSize: 12,
              color: display.color,
              fontWeight: FontWeight.w600)),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

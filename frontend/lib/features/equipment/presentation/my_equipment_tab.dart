import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/equipment_basket_service.dart';
import '../../../core/services/equipment_reservation_service.dart';
import '../../../core/state/employee_session.dart';
import '../../../models/equipment_basket.dart';
import '../../../models/equipment_reservation.dart';
import 'equipment_basket_card.dart';

/// employee-only view of their own reservations, split into "Current &
/// Upcoming" (active, ending in the future) and "Past" (active but already
/// ended, or cancelled). Current/upcoming rows expose Check out / Return
/// actions; past rows are read-only history.
class MyEquipmentTab extends StatelessWidget {
  const MyEquipmentTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: EmployeeSession.profile,
      builder: (context, profile, _) {
        final employeeId = profile?.employeeId ?? '';
        if (employeeId.isEmpty) {
          return const Center(child: Text('Sign in to see your equipment.'));
        }

        return StreamBuilder<List<EquipmentReservation>>(
          stream: EquipmentReservationService.watchForEmployee(employeeId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                  child: Text('Failed to load your equipment: '
                      '${snapshot.error}'));
            }

            final all = snapshot.data ?? const <EquipmentReservation>[];
            final now = DateTime.now();

            // basket-linked reservations show under "Baskets" instead, not
            // here — see below.
            final currentUpcoming = all
                .where((r) => r.isActive && r.endTime.isAfter(now) && !r.isInBasket)
                .toList()
              ..sort((a, b) => a.startTime.compareTo(b.startTime));

            // past: active-but-ended, plus anything cancelled
            final past = all
                .where((r) => (!r.isActive || !r.endTime.isAfter(now)) && !r.isInBasket)
                .toList()
              ..sort((a, b) => b.startTime.compareTo(a.startTime));

            return StreamBuilder<List<EquipmentBasket>>(
              stream: EquipmentBasketService.watchForEmployee(employeeId),
              builder: (context, basketSnapshot) {
                final baskets = basketSnapshot.data ?? const <EquipmentBasket>[];

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (baskets.isNotEmpty) ...[
                      Text('Baskets',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      for (final basket in baskets)
                        EquipmentBasketCard(
                          basket: basket,
                          reservations:
                              all.where((r) => r.basketId == basket.id).toList(),
                          onCheckOutAll: () => _checkOutBasket(context, basket),
                          onReturnAll: () => _returnBasket(context, basket),
                          onCancelAll: () => _cancelBasket(context, basket),
                          onCheckOutOne: (r) => _checkOutOne(context, r),
                          onReturnOne: (r) => _returnOne(context, r),
                          onCancelOne: (r) => _cancelOne(context, r),
                        ),
                      const SizedBox(height: 24),
                    ],
                    Text('Current & Upcoming',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (currentUpcoming.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No current or upcoming reservations.'),
                      )
                    else
                      for (final reservation in currentUpcoming)
                        _MyReservationRow(reservation: reservation, showActions: true),
                    const SizedBox(height: 24),
                    Text('Past',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (past.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No past reservations.'),
                      )
                    else
                      for (final reservation in past)
                        _MyReservationRow(reservation: reservation, showActions: false),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<void> _checkOutBasket(BuildContext context, EquipmentBasket basket) async {
  try {
    await EquipmentBasketService.checkOutBasket(basket.id);
    if (context.mounted) _snack(context, 'Basket checked out.');
  } catch (error) {
    if (context.mounted) {
      _snack(context, error.toString().replaceFirst('Exception: ', ''));
    }
  }
}

Future<void> _returnBasket(BuildContext context, EquipmentBasket basket) async {
  try {
    await EquipmentBasketService.returnBasket(basket.id);
    if (context.mounted) _snack(context, 'Basket returned.');
  } catch (error) {
    if (context.mounted) {
      _snack(context, error.toString().replaceFirst('Exception: ', ''));
    }
  }
}

Future<void> _cancelBasket(BuildContext context, EquipmentBasket basket) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Cancel basket'),
      content: const Text(
          'Cancel this basket? Any item already checked out is left as-is.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Back')),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Cancel basket')),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await EquipmentBasketService.cancelBasket(basket.id);
    if (context.mounted) _snack(context, 'Basket cancelled.');
  } catch (error) {
    if (context.mounted) {
      _snack(context, error.toString().replaceFirst('Exception: ', ''));
    }
  }
}

Future<void> _checkOutOne(BuildContext context, EquipmentReservation reservation) async {
  try {
    await EquipmentReservationService.markCheckedOut(reservation.id);
  } catch (error) {
    if (context.mounted) {
      _snack(context, error.toString().replaceFirst('Exception: ', ''));
    }
  }
}

Future<void> _returnOne(BuildContext context, EquipmentReservation reservation) async {
  try {
    await EquipmentReservationService.markReturned(reservation.id);
  } catch (error) {
    if (context.mounted) {
      _snack(context, error.toString().replaceFirst('Exception: ', ''));
    }
  }
}

Future<void> _cancelOne(BuildContext context, EquipmentReservation reservation) async {
  try {
    await EquipmentReservationService.cancelReservation(id: reservation.id);
  } catch (error) {
    if (context.mounted) {
      _snack(context, error.toString().replaceFirst('Exception: ', ''));
    }
  }
}

/// one row in "my equipment". When [showActions] is true (current/upcoming),
/// it shows a status chip plus Check out / Return buttons as appropriate;
/// otherwise it's read-only history.
class _MyReservationRow extends StatelessWidget {
  const _MyReservationRow({
    required this.reservation,
    required this.showActions,
  });

  final EquipmentReservation reservation;
  final bool showActions;

  Future<void> _checkOut(BuildContext context) async {
    try {
      await EquipmentReservationService.markCheckedOut(reservation.id);
      if (!context.mounted) return;
      _snack(context, 'Checked out unit #${reservation.unitNumber}.');
    } catch (error) {
      if (!context.mounted) return;
      _snack(context, error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _return(BuildContext context) async {
    try {
      await EquipmentReservationService.markReturned(reservation.id);
      if (!context.mounted) return;
      _snack(context, 'Returned unit #${reservation.unitNumber}.');
    } catch (error) {
      if (!context.mounted) return;
      _snack(context, error.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('h:mm a');
    final window =
        '${timeFmt.format(reservation.startTime)} – ${timeFmt.format(reservation.endTime)}';

    final canCheckOut =
        showActions && reservation.isActive && reservation.checkedOutAt == null;
    final canReturn = showActions &&
        reservation.isActive &&
        reservation.checkedOutAt != null &&
        reservation.returnedAt == null;

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
                      Text(
                        reservation.equipmentName.isEmpty
                            ? 'Equipment'
                            : reservation.equipmentName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text('${reservation.date} · $window',
                          style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
                _StatusChip(reservation: reservation),
              ],
            ),
            if (canCheckOut || canReturn) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (canCheckOut)
                    FilledButton.icon(
                      onPressed: () => _checkOut(context),
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('Check out'),
                    ),
                  if (canReturn)
                    FilledButton.icon(
                      onPressed: () => _return(context),
                      icon: const Icon(Icons.login, size: 18),
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

/// status chip for a "my equipment" row: Cancelled / Returned / Checked out /
/// Reserved, in priority order.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.reservation});

  final EquipmentReservation reservation;

  @override
  Widget build(BuildContext context) {
    String label;
    Color color;
    if (reservation.isCancelled) {
      label = 'Cancelled';
      color = Colors.grey;
    } else if (reservation.returnedAt != null) {
      label = 'Returned';
      color = Colors.blueGrey;
    } else if (reservation.checkedOutAt != null) {
      label = 'Checked out';
      color = Colors.green;
    } else {
      label = 'Reserved';
      color = Colors.blue;
    }
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

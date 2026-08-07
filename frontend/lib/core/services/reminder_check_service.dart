import 'dart:async';

import 'package:intl/intl.dart';

import '../../models/app_notification.dart';
import '../../models/client_profile.dart';
import '../../models/equipment.dart' show equipmentServiceDueLeadTime;
import '../../models/invoice.dart';
import 'client_profile_service.dart';
import 'comms_service.dart';
import 'equipment_service.dart';
import 'invoice_service.dart';
import 'local_notification_service.dart';
import 'notification_service.dart';
import 'scheduled_work_service.dart';

/// scans for jobs/invoices that need a reminder and creates the
/// corresponding in-app notifications. Not a real background job — it's
/// triggered client-side (see DashboardPage) whenever anyone loads the
/// dashboard, which is a pragmatic stand-in until real scheduled delivery
/// (email/SMS via a server) is built. The scan itself is isolated in this one
/// function so a real scheduled backend could call the same logic later.
class ReminderCheckService {
  ReminderCheckService._();

  static const _appointmentLookahead = Duration(hours: 48);
  static const invoiceOverdueAfter = Duration(days: 7);
  static const _serviceDueLeadTime = equipmentServiceDueLeadTime;

  /// an unpaid invoice counts as overdue once it's been sent and gone
  /// [invoiceOverdueAfter] without payment, measured from its last reminder
  /// (or its creation date if no reminder has gone out yet).
  static bool isInvoiceOverdue(Invoice invoice) {
    if (!invoice.isApproved) return false;
    final since = invoice.lastReminderSentAt ?? invoice.createdAt;
    return DateTime.now().difference(since) >= invoiceOverdueAfter;
  }

  /// re-entrancy guard: DashboardPage remounts (and re-triggers this scan)
  /// every time a user navigates back to the Dashboard tab, since AppScaffold
  /// uses pushReplacementNamed. Rapid tab-switching could otherwise overlap
  /// two scans that both read a notified-flag as unset before either write
  /// lands, double-firing a notification.
  static bool _isRunning = false;

  static ClientProfile? _findClient(List<ClientProfile> clients, String clientId) {
    for (final client in clients) {
      if (client.signupId == clientId) return client;
    }
    return null;
  }

  static Future<void> checkAndCreateReminders() async {
    if (_isRunning) return;
    _isRunning = true;
    try {
      await _checkAppointmentReminders();
      await _checkInvoiceReminders();
      await _checkServiceDueSoon();
      await _checkLowStock();
    } finally {
      _isRunning = false;
    }
  }

  static Future<void> _checkAppointmentReminders() async {
    final jobs = await ScheduledWorkService.watchScheduledWork(role: 'owner').first;
    final now = DateTime.now();
    final cutoff = now.add(_appointmentLookahead);

    for (final job in jobs) {
      if (job.reminderSentAt != null) continue;
      if (job.isArchived || !job.isScheduled) continue;
      if (job.scheduledDate.isBefore(now) || job.scheduledDate.isAfter(cutoff)) continue;

      final clients = await ClientProfileService.watchAllProfiles().first;
      final clientName = ClientProfileService.displayNameFor(clients, job.clientId);
      final client = _findClient(clients, job.clientId);

      await NotificationService.create(
        recipientRole: 'client',
        recipientId: job.clientId,
        type: NotificationType.appointmentReminder,
        title: 'Upcoming appointment',
        body: 'Your appointment for Est #${job.estimateNumber} is coming up soon.',
        relatedId: job.id,
      );
      await NotificationService.create(
        recipientRole: 'owner',
        recipientId: ownerNotificationRecipientId,
        type: NotificationType.appointmentReminder,
        title: 'Upcoming appointment',
        body: '$clientName has an appointment coming up (Est #${job.estimateNumber}).',
        relatedId: job.id,
      );
      await LocalNotificationService.showMessageNotification(
        id: job.id.hashCode,
        title: 'Upcoming appointment',
        body: '$clientName — Est #${job.estimateNumber}',
      );
      if (client != null && client.email.trim().isNotEmpty) {
        unawaited(CommsService.sendEmail(
          to: client.email.trim(),
          subject: 'Upcoming appointment reminder',
          htmlBody: '<p>Hi $clientName,</p>'
              '<p>This is a reminder that your appointment for Estimate #${job.estimateNumber} is coming up soon.</p>',
        ));
      }
      await ScheduledWorkService.markReminderSent(job.id);
    }
  }

  static Future<void> _checkInvoiceReminders() async {
    final invoices = await InvoiceService.watchInvoices(role: 'owner').first;
    final now = DateTime.now();

    for (final invoice in invoices) {
      if (invoice.isArchived || invoice.status != InvoiceStatus.sent) continue;
      final lastSent = invoice.lastReminderSentAt;
      final dueForReminder = lastSent == null
          ? now.difference(invoice.createdAt) >= invoiceOverdueAfter
          : now.difference(lastSent) >= invoiceOverdueAfter;
      if (!dueForReminder) continue;

      final clients = await ClientProfileService.watchAllProfiles().first;
      final clientName = ClientProfileService.displayNameFor(clients, invoice.clientId);
      final client = _findClient(clients, invoice.clientId);

      await NotificationService.create(
        recipientRole: 'client',
        recipientId: invoice.clientId,
        type: NotificationType.invoiceOverdue,
        title: 'Invoice reminder',
        body: 'Invoice ${invoice.invoiceNumber} for \$${invoice.total.toStringAsFixed(2)} is still outstanding.',
        relatedId: invoice.id,
      );
      await NotificationService.create(
        recipientRole: 'owner',
        recipientId: ownerNotificationRecipientId,
        type: NotificationType.invoiceOverdue,
        title: 'Invoice still unpaid',
        body: '$clientName has not paid ${invoice.invoiceNumber} (\$${invoice.total.toStringAsFixed(2)}).',
        relatedId: invoice.id,
      );
      if (client != null && client.email.trim().isNotEmpty) {
        unawaited(CommsService.sendEmail(
          to: client.email.trim(),
          subject: 'Invoice ${invoice.invoiceNumber} — payment reminder',
          htmlBody: '<p>Hi $clientName,</p>'
              '<p>This is a reminder that invoice ${invoice.invoiceNumber} for '
              '\$${invoice.total.toStringAsFixed(2)} is still outstanding.</p>',
        ));
      }
      if (client != null && client.phoneNumber.trim().isNotEmpty) {
        unawaited(CommsService.sendSms(
          to: client.phoneNumber.trim(),
          body: 'Reminder: invoice ${invoice.invoiceNumber} for '
              '\$${invoice.total.toStringAsFixed(2)} is still outstanding.',
        ));
      }
      await LocalNotificationService.showMessageNotification(
        id: invoice.id.hashCode,
        title: 'Invoice reminder',
        body: '$clientName — ${invoice.invoiceNumber}',
      );
      await InvoiceService.markReminderSent(invoice.id);
    }
  }

  /// scan Equipment units whose next-service date falls within the lead time
  /// (or is already past) and alert the owner once per due window. Dedupe uses
  /// the unit's serviceDueNotifiedAt stamp; snoozed units are skipped until the
  /// snooze passes.
  static Future<void> _checkServiceDueSoon() async {
    final items = await EquipmentService.watchAll().first;
    final now = DateTime.now();
    final cutoff = now.add(_serviceDueLeadTime);

    for (final item in items) {
      if (!item.isEquipment || item.isArchived) continue;
      for (final unit in item.units) {
        final due = unit.nextServiceDueDate;
        if (due == null) continue;
        final snoozedUntil = unit.serviceDueSnoozedUntil;
        if (snoozedUntil != null && snoozedUntil.isAfter(now)) continue;
        if (unit.serviceDueNotifiedAt != null) continue;
        if (due.isAfter(cutoff)) continue;

        await NotificationService.create(
          recipientRole: 'owner',
          recipientId: ownerNotificationRecipientId,
          type: NotificationType.serviceDue,
          title: 'Service due soon',
          body: '${item.name} (unit #${unit.unitNumber}) is due for service '
              'on ${DateFormat('MMM d').format(due)}.',
          relatedId: item.id,
        );
        await LocalNotificationService.showMessageNotification(
          id: '${item.id}_${unit.unitNumber}'.hashCode,
          title: 'Service due soon',
          body: '${item.name} — unit #${unit.unitNumber}',
        );
        await EquipmentService.stampUnitServiceDueNotified(
          equipmentId: item.id,
          unitNumber: unit.unitNumber,
        );
      }
    }
  }

  /// scan Supply items that are at/below their low-stock threshold (or manually
  /// flagged) and alert the owner once per low-stock episode. Dedupe uses the
  /// item's lowStockNotifiedAt stamp, which restock/flag changes clear again
  /// once the item is no longer low.
  static Future<void> _checkLowStock() async {
    final items = await EquipmentService.watchAll().first;

    for (final item in items) {
      if (!item.isSupply || item.isArchived) continue;
      if (!item.isLowStock) continue;
      if (item.lowStockNotifiedAt != null) continue;

      await NotificationService.create(
        recipientRole: 'owner',
        recipientId: ownerNotificationRecipientId,
        type: NotificationType.lowStock,
        title: 'Running low: ${item.name}',
        body: 'Only ${item.quantity} ${item.unitOfMeasure} left.'.trim(),
        relatedId: item.id,
      );
      await LocalNotificationService.showMessageNotification(
        id: 'lowstock_${item.id}'.hashCode,
        title: 'Running low: ${item.name}',
        body: 'Only ${item.quantity} ${item.unitOfMeasure} left.'.trim(),
      );
      await EquipmentService.stampLowStockNotified(item.id);
    }
  }
}

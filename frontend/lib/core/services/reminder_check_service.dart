import 'dart:async';

import '../../models/app_notification.dart';
import '../../models/client_profile.dart';
import '../../models/invoice.dart';
import 'client_profile_service.dart';
import 'comms_service.dart';
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
  static const _invoiceOverdueAfter = Duration(days: 7);

  static ClientProfile? _findClient(List<ClientProfile> clients, String clientId) {
    for (final client in clients) {
      if (client.signupId == clientId) return client;
    }
    return null;
  }

  static Future<void> checkAndCreateReminders() async {
    await _checkAppointmentReminders();
    await _checkInvoiceReminders();
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
          ? now.difference(invoice.createdAt) >= _invoiceOverdueAfter
          : now.difference(lastSent) >= _invoiceOverdueAfter;
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
}

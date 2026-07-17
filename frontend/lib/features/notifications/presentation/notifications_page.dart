import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/state/client_session.dart';
import '../../../core/state/employee_session.dart';
import '../../../models/app_notification.dart';
import '../../../shared/widgets/app_scaffold.dart';

/// resolve the current user's notification recipient id for [role]; null if
/// no session is available yet (e.g. still logging in)
String? recipientIdFor(String role) {
  if (role == 'owner') return ownerNotificationRecipientId;
  if (role == 'client') return ClientSession.profile.value?.signupId;
  if (role == 'employee') return EmployeeSession.profile.value?.employeeId;
  return null;
}

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  void _open(BuildContext context, AppNotification notification) {
    if (!notification.isRead) {
      NotificationService.markRead(notification.id);
    }
    final relatedId = notification.relatedId;
    if (relatedId == null || relatedId.isEmpty) return;

    final route = notification.type == NotificationType.invoiceOverdue ? AppRouter.invoices : AppRouter.appointments;
    Navigator.pushNamed(
      context,
      route,
      arguments: {'role': role, 'authToken': authToken, 'highlightId': relatedId},
    );
  }

  @override
  Widget build(BuildContext context) {
    final recipientId = recipientIdFor(role);

    return AppScaffold(
      title: 'Notifications',
      role: role,
      authToken: authToken,
      selectedRoute: AppRouter.notifications,
      body: recipientId == null
          ? const Center(child: Text('Log in to see your notifications.'))
          : StreamBuilder<List<AppNotification>>(
              stream: NotificationService.watchForRecipient(role, recipientId),
              builder: (context, snapshot) {
                final notifications = snapshot.data ?? const <AppNotification>[];
                if (notifications.isEmpty) {
                  return const Center(child: Text('No notifications yet.'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: notifications.length,
                  itemBuilder: (context, index) {
                    final notification = notifications[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: notification.isRead ? null : Theme.of(context).colorScheme.primaryContainer,
                      child: ListTile(
                        title: Text(notification.title),
                        subtitle: Text(
                          '${notification.body}\n${DateFormat('MMM d, h:mm a').format(notification.createdAt)}',
                        ),
                        isThreeLine: true,
                        onTap: () => _open(context, notification),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

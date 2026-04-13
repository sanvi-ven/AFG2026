import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/local_notification_service.dart';
import '../../../core/services/message_service.dart';
import '../../../core/state/client_session.dart';
import '../../../models/message.dart';
import '../../../shared/widgets/app_scaffold.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({required this.role, super.key});

  final String role;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _clientIdsController = TextEditingController();

  bool _isSending = false;
  bool _notificationBootstrapDone = false;
  String? _activeClientId;
  Set<String> _knownMessageIds = <String>{};
  StreamSubscription<List<MessageLog>>? _notificationSub;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _clientIdsController.dispose();
    _notificationSub?.cancel();
    super.dispose();
  }

  List<String> _parseClientIds(String input) {
    return input
        .split(RegExp(r'[,;\n\s]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<void> _sendBroadcast() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    final clientIds = _parseClientIds(_clientIdsController.text);

    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title and message body are required.')),
      );
      return;
    }
    if (clientIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Provide at least one client ID.')),
      );
      return;
    }

    setState(() => _isSending = true);
    try {
      final sentCount = await MessageService.sendBroadcast(
        title: title,
        body: body,
        clientIds: clientIds,
      );

      if (!mounted) {
        return;
      }

      _titleController.clear();
      _bodyController.clear();
      _clientIdsController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Broadcast sent to $sentCount client(s).')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send broadcast: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _markMessageRead(String messageId) async {
    try {
      await MessageService.markAsRead(messageId: messageId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to mark message as read: $error')),
      );
    }
  }

  Future<void> _markAllRead(String clientId) async {
    try {
      await MessageService.markAllAsRead(clientId: clientId);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All messages marked as read.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to mark all read: $error')),
      );
    }
  }

  void _ensureClientNotificationListener(String? clientId) {
    if (widget.role != 'client' || clientId == null || clientId.trim().isEmpty) {
      return;
    }
    if (_activeClientId == clientId && _notificationSub != null) {
      return;
    }

    _activeClientId = clientId;
    _notificationBootstrapDone = false;
    _knownMessageIds = <String>{};
    _notificationSub?.cancel();

    _notificationSub = MessageService.watchClientMessages(clientId: clientId).listen((messages) async {
      if (!_notificationBootstrapDone) {
        _knownMessageIds = messages.map((item) => item.id).toSet();
        _notificationBootstrapDone = true;
        return;
      }

      for (final message in messages) {
        if (_knownMessageIds.contains(message.id)) {
          continue;
        }
        _knownMessageIds.add(message.id);
        if (!message.read) {
          await LocalNotificationService.showMessageNotification(
            id: message.id.hashCode,
            title: message.title,
            body: message.body,
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = ClientSession.profile.value;
    final clientId = profile?.signupId;
    _ensureClientNotificationListener(clientId);

    return AppScaffold(
      title: widget.role == 'owner' ? 'Broadcast Center' : 'Inbox',
      role: widget.role,
      selectedRoute: '/messages',
      body: widget.role == 'owner'
          ? _buildOwnerView(context)
          : _buildClientView(context, clientId),
    );
  }

  Widget _buildOwnerView(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        _OwnerComposerCard(
          titleController: _titleController,
          bodyController: _bodyController,
          clientIdsController: _clientIdsController,
          isSending: _isSending,
          onSend: _sendBroadcast,
        ),
        const SizedBox(height: 14),
        StreamBuilder<List<OwnerBroadcastSummary>>(
          stream: MessageService.watchOwnerBroadcasts(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Failed to load broadcast log: ${snapshot.error}'),
                ),
              );
            }

            final broadcasts = snapshot.data ?? const <OwnerBroadcastSummary>[];
            if (broadcasts.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No broadcasts yet. Send your first message above.'),
                ),
              );
            }

            return Column(
              children: [
                for (final item in broadcasts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _OwnerBroadcastLogCard(summary: item),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildClientView(BuildContext context, String? clientId) {
    if (clientId == null || clientId.trim().isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Client ID not found. Please log in from the client email flow first.'),
          ),
        ),
      );
    }

    return StreamBuilder<List<MessageLog>>(
      stream: MessageService.watchClientMessages(clientId: clientId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Failed to load inbox: ${snapshot.error}'),
              ),
            ),
          );
        }

        final messages = snapshot.data ?? const <MessageLog>[];
        final unreadCount = messages.where((item) => item.isUnread).length;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            _ClientInboxBanner(unreadCount: unreadCount),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: unreadCount > 0 ? () => _markAllRead(clientId) : null,
                icon: const Icon(Icons.done_all),
                label: const Text('Mark All Read'),
              ),
            ),
            const SizedBox(height: 8),
            if (messages.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No messages yet.'),
                ),
              )
            else
              ...messages.map(
                (message) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ClientMessageCard(
                    message: message,
                    onMarkRead: message.isUnread ? () => _markMessageRead(message.id) : null,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _OwnerComposerCard extends StatelessWidget {
  const _OwnerComposerCard({
    required this.titleController,
    required this.bodyController,
    required this.clientIdsController,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController titleController;
  final TextEditingController bodyController;
  final TextEditingController clientIdsController;
  final bool isSending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Owner Broadcast',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: titleController,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: bodyController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Message',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: clientIdsController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Client IDs (comma, space, or new-line separated)',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
              hintText: 'abc123, def456',
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: isSending ? null : onSend,
              icon: isSending
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: const Text('Send Broadcast'),
            ),
          ),
        ],
      ),
    );
  }
}

class _OwnerBroadcastLogCard extends StatelessWidget {
  const _OwnerBroadcastLogCard({required this.summary});

  final OwnerBroadcastSummary summary;

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat.yMMMd().add_jm().format(summary.createdAt);
    final deliveryPercent = summary.recipientCount == 0
        ? 0
        : ((summary.readCount / summary.recipientCount) * 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(summary.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(summary.body),
            const SizedBox(height: 10),
            Text('$dateLabel · ${summary.recipientCount} recipient(s)'),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: summary.recipientCount == 0 ? 0 : summary.readCount / summary.recipientCount),
            const SizedBox(height: 6),
            Text('Read by ${summary.readCount}/${summary.recipientCount} ($deliveryPercent%)'),
          ],
        ),
      ),
    );
  }
}

class _ClientInboxBanner extends StatelessWidget {
  const _ClientInboxBanner({required this.unreadCount});

  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_active_outlined, color: colorScheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              unreadCount == 0
                  ? 'No unread announcements.'
                  : 'You have $unreadCount unread announcement(s).',
              style: TextStyle(color: colorScheme.onSecondaryContainer, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientMessageCard extends StatelessWidget {
  const _ClientMessageCard({required this.message, this.onMarkRead});

  final MessageLog message;
  final VoidCallback? onMarkRead;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = message.read ? colorScheme.primary : colorScheme.error;
    final dateLabel = DateFormat.yMMMd().add_jm().format(message.createdAt);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    message.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    message.read ? 'Read' : 'Unread',
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(message.body),
            const SizedBox(height: 10),
            Text(dateLabel, style: Theme.of(context).textTheme.bodySmall),
            if (onMarkRead != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: onMarkRead,
                  icon: const Icon(Icons.mark_email_read_outlined),
                  label: const Text('Mark Read'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

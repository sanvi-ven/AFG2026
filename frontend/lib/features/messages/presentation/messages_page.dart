// made with chatgpt: build a flutter messaging page for a service business app. owners should be able to send broadcast messages to multiple client IDs
// snapshot--https://firebase.google.com/docs/reference/js/firestore_.documentsnapshot


import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/client_profile_service.dart';
import '../../../core/services/message_service.dart';
import '../../../core/state/client_session.dart';
import '../../../models/client_profile.dart';
import '../../../models/message.dart';
import '../../../shared/widgets/app_scaffold.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _clientIdsController = TextEditingController();

  bool _isSending = false;
  bool _isLoadingClientSuggestions = true;
  StreamSubscription<List<ClientProfile>>? _clientDirectorySub;
  Timer? _clientSuggestionDebounce;
  List<ClientProfile> _knownClients = const [];
  List<ClientProfile> _clientSuggestions = const [];
  final List<ClientProfile> _selectedRecipients = <ClientProfile>[];

  @override
  void initState() {
    super.initState();
    _clientDirectorySub =
        ClientProfileService.watchAllProfiles().listen((profiles) {
      if (!mounted) {
        return;
      }

      final profileIds = profiles.map((item) => item.signupId).toSet();

      setState(() {
        _knownClients = profiles;
        _isLoadingClientSuggestions = false;
        _selectedRecipients
            .removeWhere((item) => !profileIds.contains(item.signupId));
        _clientSuggestions = ClientProfileService.searchProfiles(
          profiles: profiles,
          query: _clientIdsController.text,
          limit: 8,
          excludeSignupIds:
              _selectedRecipients.map((item) => item.signupId).toSet(),
        );
      });
    });
  }

  @override
  void dispose() {
    _clientSuggestionDebounce?.cancel();
    _clientDirectorySub?.cancel();
    _titleController.dispose();
    _bodyController.dispose();
    _clientIdsController.dispose();
    super.dispose();
  }

  List<ClientProfile> _findClientSuggestions(String query) {
    return ClientProfileService.searchProfiles(
      profiles: _knownClients,
      query: query,
      limit: 8,
      excludeSignupIds: _selectedRecipients.map((item) => item.signupId).toSet(),
    );
  }

  void _onClientSearchChanged(String value) {
    _clientSuggestionDebounce?.cancel();

    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _clientSuggestions = const [];
      });
      return;
    }

    _clientSuggestionDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _clientSuggestions = _findClientSuggestions(query);
      });
    });
  }

  void _addRecipient(ClientProfile profile) {
    final alreadyAdded =
        _selectedRecipients.any((item) => item.signupId == profile.signupId);
    if (alreadyAdded) {
      _clientIdsController.clear();
      setState(() {
        _clientSuggestions = const [];
      });
      return;
    }

    _clientIdsController.clear();
    setState(() {
      _selectedRecipients.add(profile);
      _clientSuggestions = const [];
    });
  }

  void _removeRecipient(String signupId) {
    setState(() {
      _selectedRecipients.removeWhere((item) => item.signupId == signupId);
      _clientSuggestions = _findClientSuggestions(_clientIdsController.text);
    });
  }

  bool _tryResolveTypedClientId() {
    final query = _clientIdsController.text.trim();
    if (query.isEmpty) {
      return true;
    }

    ClientProfile? exactIdMatch;
    for (final profile in _knownClients) {
      if (profile.signupId.toLowerCase() == query.toLowerCase()) {
        exactIdMatch = profile;
        break;
      }
    }

    if (exactIdMatch == null) {
      return false;
    }

    _addRecipient(exactIdMatch);
    return true;
  }

  Future<void> _sendBroadcast() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title and message body are required.')),
      );
      return;
    }

    if (!_tryResolveTypedClientId()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a valid client from suggestions.')),
      );
      return;
    }

    final clientIds = _selectedRecipients.map((item) => item.signupId).toSet().toList();
    if (clientIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one valid client.')),
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
      setState(() {
        _selectedRecipients.clear();
        _clientSuggestions = const [];
      });
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

  @override
  Widget build(BuildContext context) {
    final profile = ClientSession.profile.value;
    final clientId = profile?.signupId;

    return AppScaffold(
      title: widget.role == 'owner' ? 'Broadcast Center' : 'Inbox',
      role: widget.role,
      authToken: widget.authToken,
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
          selectedRecipients: _selectedRecipients,
          isLoadingClientSuggestions: _isLoadingClientSuggestions,
          clientSuggestions: _clientSuggestions,
          onClientSearchChanged: _onClientSearchChanged,
          onClientSuggestionSelected: _addRecipient,
          onRecipientRemoved: _removeRecipient,
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
                  child:
                      Text('Failed to load broadcast log: ${snapshot.error}'),
                ),
              );
            }

            final broadcasts = snapshot.data ?? const <OwnerBroadcastSummary>[];
            if (broadcasts.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child:
                      Text('No broadcasts yet. Send your first message above.'),
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
            child: Text(
                'Client ID not found. Please log in from the client email flow first.'),
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
                onPressed:
                    unreadCount > 0 ? () => _markAllRead(clientId) : null,
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
                    onMarkRead: message.isUnread
                        ? () => _markMessageRead(message.id)
                        : null,
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
    required this.selectedRecipients,
    required this.isLoadingClientSuggestions,
    required this.clientSuggestions,
    required this.onClientSearchChanged,
    required this.onClientSuggestionSelected,
    required this.onRecipientRemoved,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController titleController;
  final TextEditingController bodyController;
  final TextEditingController clientIdsController;
  final List<ClientProfile> selectedRecipients;
  final bool isLoadingClientSuggestions;
  final List<ClientProfile> clientSuggestions;
  final ValueChanged<String> onClientSearchChanged;
  final ValueChanged<ClientProfile> onClientSuggestionSelected;
  final ValueChanged<String> onRecipientRemoved;
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
            onChanged: onClientSearchChanged,
            decoration: InputDecoration(
              labelText: 'Search Clients (ID, name, or address)',
              border: const OutlineInputBorder(),
              hintText: 'Type ID, name, or address',
              suffixIcon: isLoadingClientSuggestions
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          ),
          if (selectedRecipients.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final recipient in selectedRecipients)
                  InputChip(
                    label: Text('${recipient.signupId} · ${recipient.fullName}'),
                    onDeleted: () => onRecipientRemoved(recipient.signupId),
                  ),
              ],
            ),
          ],
          if (clientSuggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: clientSuggestions.length,
                  itemBuilder: (context, index) {
                    final suggestion = clientSuggestions[index];
                    return ListTile(
                      dense: true,
                      title: Text('${suggestion.signupId} · ${suggestion.fullName}'),
                      subtitle: Text(
                        suggestion.address.isEmpty
                            ? 'Address unavailable'
                            : suggestion.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => onClientSuggestionSelected(suggestion),
                    );
                  },
                ),
              ),
            ),
          ],
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
            Text(summary.title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(summary.body),
            const SizedBox(height: 10),
            Text('$dateLabel · ${summary.recipientCount} recipient(s)'),
            const SizedBox(height: 8),
            LinearProgressIndicator(
                value: summary.recipientCount == 0
                    ? 0
                    : summary.readCount / summary.recipientCount),
            const SizedBox(height: 6),
            Text(
                'Read by ${summary.readCount}/${summary.recipientCount} ($deliveryPercent%)'),
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
          Icon(Icons.notifications_active_outlined,
              color: colorScheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              unreadCount == 0
                  ? 'No unread announcements.'
                  : 'You have $unreadCount unread announcement(s).',
              style: TextStyle(
                  color: colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600),
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
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    message.read ? 'Read' : 'Unread',
                    style: TextStyle(
                        color: statusColor, fontWeight: FontWeight.w700),
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

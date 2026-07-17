import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/request_service.dart';
import '../../../models/request.dart';
import '../../../shared/widgets/app_scaffold.dart';

/// owner-only inbox for triaging incoming work requests before they become estimates
class RequestsPage extends StatelessWidget {
  const RequestsPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  void _convertToEstimate(BuildContext context, Request request) {
    final notes = request.clientId != null
        ? request.description
        : '${request.description}\n\nContact: ${request.name}, ${request.email}, ${request.phone}, ${request.address}';

    Navigator.pushNamed(
      context,
      AppRouter.estimates,
      arguments: {
        'role': role,
        'authToken': authToken,
        'initialClientId': request.clientId,
        'initialNotes': notes,
        'convertRequestId': request.id,
      },
    );
  }

  Future<void> _decline(BuildContext context, Request request) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Decline Request'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Reason (optional)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Decline')),
        ],
      ),
    );
    if (confirmed != true) return;

    await RequestService.markDeclined(requestId: request.id, reason: controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Requests',
      role: role,
      authToken: authToken,
      selectedRoute: AppRouter.requests,
      body: StreamBuilder<List<Request>>(
        stream: RequestService.watchAllRequests(),
        builder: (context, snapshot) {
          final requests = snapshot.data ?? const <Request>[];
          final pending = requests.where((r) => r.isNew).toList();
          final resolved = requests.where((r) => !r.isNew).toList();

          if (requests.isEmpty) {
            return const Center(child: Text('No requests yet.'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final request in pending) _RequestCard(request: request, onConvert: _convertToEstimate, onDecline: _decline),
              if (resolved.isNotEmpty) ...[
                const SizedBox(height: 4),
                ExpansionTile(
                  title: Text('Resolved (${resolved.length})'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  children: [
                    for (final request in resolved)
                      _RequestCard(request: request, onConvert: _convertToEstimate, onDecline: _decline),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, required this.onConvert, required this.onDecline});

  final Request request;
  final void Function(BuildContext, Request) onConvert;
  final Future<void> Function(BuildContext, Request) onDecline;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(request.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Text(DateFormat('MMM d, yyyy').format(request.createdAt)),
              ],
            ),
            const SizedBox(height: 4),
            Text('${request.email} · ${request.phone}'),
            if (request.address.isNotEmpty) Text(request.address),
            const SizedBox(height: 8),
            Text(request.description),
            if (request.photoUrls.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final url in request.photoUrls)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(url, width: 56, height: 56, fit: BoxFit.cover),
                    ),
                ],
              ),
            ],
            if (request.isConverted) ...[
              const SizedBox(height: 8),
              Text('Converted to estimate', style: Theme.of(context).textTheme.bodySmall),
            ] else if (request.isDeclined) ...[
              const SizedBox(height: 8),
              Text(
                request.declineReason.isEmpty ? 'Declined' : 'Declined: ${request.declineReason}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => onConvert(context, request),
                    icon: const Icon(Icons.request_quote_outlined, size: 16),
                    label: const Text('Convert to Estimate'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => onDecline(context, request),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Decline'),
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

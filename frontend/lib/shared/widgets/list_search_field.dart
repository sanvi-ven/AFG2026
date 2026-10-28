import 'package:flutter/material.dart';

import '../../models/client_profile.dart';

/// search box shown above the estimates / invoices / appointments lists
class ListSearchField extends StatelessWidget {
  const ListSearchField({
    required this.controller,
    required this.onChanged,
    this.hintText = 'Search by client, address, number, or service',
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: hintText,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                tooltip: 'Clear search',
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
      ),
      onChanged: onChanged,
    );
  }
}

/// true when every whitespace-separated word of [query] appears in at least
/// one of [fields] (case-insensitive), so "smith maple" finds the Smith job
/// on Maple St. an empty query matches everything.
bool matchesListSearch(String query, Iterable<String?> fields) {
  final terms = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty);
  if (terms.isEmpty) return true;
  final haystack =
      fields.whereType<String>().map((f) => f.toLowerCase()).join('\n');
  return terms.every(haystack.contains);
}

/// the client fields every list search should cover
List<String?> clientSearchFields(ClientProfile? client, String clientId) => [
      clientId,
      client?.fullName,
      client?.address,
      client?.email,
      client?.phoneNumber,
    ];

/// client name + address line shown on list cards in place of the raw client id
class ClientInfoLine extends StatelessWidget {
  const ClientInfoLine(
      {required this.client, required this.clientId, this.address, super.key});

  final ClientProfile? client;
  final String clientId;

  /// overrides the client's profile address (e.g. a job's own site address)
  final String? address;

  @override
  Widget build(BuildContext context) {
    final name = client?.fullName.trim() ?? '';
    final resolvedAddress = (address?.trim().isNotEmpty ?? false)
        ? address!.trim()
        : (client?.address.trim() ?? '');
    final muted = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.outline);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.person_outline, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name.isNotEmpty ? name : 'Client ID: $clientId',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        if (resolvedAddress.isNotEmpty)
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 14),
              const SizedBox(width: 6),
              Expanded(child: Text(resolvedAddress, style: muted)),
            ],
          ),
      ],
    );
  }
}

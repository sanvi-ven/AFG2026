import 'package:flutter/material.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/client_profile_service.dart';
import '../../../models/client_profile.dart';
import '../../../shared/widgets/app_scaffold.dart';
import 'quick_add_client_dialog.dart';

/// owner-only page listing every client, including "dummy" (no-login) clients
class ClientsPage extends StatefulWidget {
  const ClientsPage({required this.role, this.authToken, super.key});

  final String role;
  final String? authToken;

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openQuickAdd() async {
    await showQuickAddClientDialog(context);
  }

  Future<void> _openEditDialog(ClientProfile profile) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _EditClientDialog(profile: profile),
    );
  }

  Future<void> _confirmArchive(ClientProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Archive Client'),
        content: Text(
          'Archive ${profile.fullName}? They\'ll be hidden from the active list and from new-estimate lookups.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Archive')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ClientProfileService.archiveClient(profile.signupId);
  }

  Future<void> _confirmDelete(ClientProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Client Permanently'),
        content: Text("Permanently delete ${profile.fullName}? This can't be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ClientProfileService.deleteClientPermanently(profile.signupId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Widget _clientTile(ClientProfile profile, {required bool isArchived}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(profile.fullName),
        subtitle: Text(
          [
            if (profile.phoneNumber.isNotEmpty) profile.phoneNumber,
            if (profile.address.isNotEmpty) profile.address,
          ].join(' · '),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!profile.hasPassword)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('No login', style: TextStyle(fontSize: 12)),
                ),
              ),
            if (isArchived)
              IconButton(
                icon: const Icon(Icons.delete_forever_outlined),
                tooltip: 'Delete permanently',
                onPressed: () => _confirmDelete(profile),
              )
            else
              IconButton(
                icon: const Icon(Icons.archive_outlined),
                tooltip: 'Archive',
                onPressed: () => _confirmArchive(profile),
              ),
          ],
        ),
        onTap: () => _openEditDialog(profile),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.role != 'owner') {
      return const SizedBox.shrink();
    }
    return AppScaffold(
      title: 'Clients',
      role: widget.role,
      authToken: widget.authToken,
      selectedRoute: AppRouter.clients,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Search by name or address',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _openQuickAdd,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('New Client'),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<ClientProfile>>(
              stream: ClientProfileService.watchAllProfiles(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Failed to load clients: ${snapshot.error}'));
                }
                final allProfiles = snapshot.data ?? const <ClientProfile>[];
                final query = _query.trim();
                final matched = query.isEmpty
                    ? allProfiles
                    : ClientProfileService.searchProfiles(profiles: allProfiles, query: query, limit: 200);

                final active = matched.where((p) => !p.archived).toList();
                final archived = matched.where((p) => p.archived).toList();

                if (active.isEmpty && archived.isEmpty) {
                  return const Center(child: Text('No clients found.'));
                }

                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final profile in active) _clientTile(profile, isArchived: false),
                    if (archived.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      ExpansionTile(
                        title: Text(
                          'Archived (${archived.length})',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(color: Theme.of(context).colorScheme.outline),
                        ),
                        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                        childrenPadding: EdgeInsets.zero,
                        children: [
                          for (final profile in archived) _clientTile(profile, isArchived: true),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EditClientDialog extends StatefulWidget {
  const _EditClientDialog({required this.profile});

  final ClientProfile profile;

  @override
  State<_EditClientDialog> createState() => _EditClientDialogState();
}

class _EditClientDialogState extends State<_EditClientDialog> {
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _emailController;
  bool _isSaving = false;
  bool _isGeneratingCode = false;
  String? _error;
  String? _claimCode;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(text: widget.profile.firstName);
    _lastNameController = TextEditingController(text: widget.profile.lastName);
    _phoneController = TextEditingController(text: widget.profile.phoneNumber);
    _addressController = TextEditingController(text: widget.profile.address);
    _emailController = TextEditingController(text: widget.profile.hasPassword ? widget.profile.email : '');
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _generateClaimCode() async {
    setState(() {
      _isGeneratingCode = true;
      _error = null;
    });
    try {
      final code = await ClientProfileService.generateClaimCode(widget.profile.signupId);
      if (!mounted) return;
      setState(() => _claimCode = code);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isGeneratingCode = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final updated = widget.profile.copyWith(
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
        phoneNumber: _phoneController.text,
        address: _addressController.text,
      );
      await ClientProfileService.save(updated);

      final newEmail = _emailController.text.trim();
      if (newEmail.isNotEmpty && newEmail.toLowerCase() != widget.profile.email.toLowerCase()) {
        await ClientProfileService.updateEmail(widget.profile.signupId, newEmail);
      }

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.profile.fullName),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstNameController,
                      decoration: const InputDecoration(labelText: 'First name'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _lastNameController,
                      decoration: const InputDecoration(labelText: 'Last name'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              if (!widget.profile.hasPassword) ...[
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 8),
                const Text('This client has no login yet.', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (_claimCode != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Claim code: $_claimCode', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 4),
                        const Text(
                          'Share this with the client. They\'ll enter it on the "Claim Your Account" page to set their own email and password.',
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _isGeneratingCode ? null : _generateClaimCode,
                  icon: _isGeneratingCode
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.vpn_key_outlined),
                  label: Text(_claimCode == null ? 'Generate Claim Code' : 'Regenerate Claim Code'),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

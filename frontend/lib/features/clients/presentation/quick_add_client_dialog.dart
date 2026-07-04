import 'package:flutter/material.dart';

import '../../../core/services/address_autocomplete_service.dart';
import '../../../core/services/client_profile_service.dart';
import '../../../models/client_profile.dart';

/// dialog for the owner to add a client who won't use the app themselves —
/// just name/phone/address, no email or password required up front
class QuickAddClientDialog extends StatefulWidget {
  const QuickAddClientDialog({super.key});

  @override
  State<QuickAddClientDialog> createState() => _QuickAddClientDialogState();
}

class _QuickAddClientDialogState extends State<QuickAddClientDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  bool _isSaving = false;
  String? _error;
  List<String> _addressSuggestions = const [];

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _onAddressChanged(String value) async {
    final query = value.trim();
    if (query.length < 3) {
      setState(() => _addressSuggestions = const []);
      return;
    }
    final suggestions = await AddressAutocompleteService.search(query);
    if (!mounted) return;
    setState(() => _addressSuggestions = suggestions);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final profile = await ClientProfileService.createDummyClient(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        address: _addressController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(profile);
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
      title: const Text('New Client'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('No email needed — this client can claim a real login later.'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _firstNameController,
                        decoration: const InputDecoration(labelText: 'First name'),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty) ? 'Required' : null,
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
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Phone is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                  onChanged: _onAddressChanged,
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Address is required' : null,
                ),
                if (_addressSuggestions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 140),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final suggestion in _addressSuggestions)
                          ListTile(
                            dense: true,
                            title: Text(suggestion),
                            onTap: () {
                              _addressController.text = suggestion;
                              setState(() => _addressSuggestions = const []);
                            },
                          ),
                      ],
                    ),
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
              : const Text('Add Client'),
        ),
      ],
    );
  }
}

/// convenience wrapper: shows the dialog, returns the created profile (or null if cancelled)
Future<ClientProfile?> showQuickAddClientDialog(BuildContext context) {
  return showDialog<ClientProfile>(context: context, builder: (_) => const QuickAddClientDialog());
}

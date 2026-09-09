import 'package:flutter/material.dart';

import '../../../core/services/address_autocomplete_service.dart';
import '../../../core/services/client_profile_service.dart';
import '../../../models/client_profile.dart';

/// dialog for the owner to add a client who won't use the app themselves —
/// just name/phone/address, no email or password required up front
class QuickAddClientDialog extends StatefulWidget {
  const QuickAddClientDialog({
    this.initialFirstName = '',
    this.initialLastName = '',
    this.initialPhone = '',
    this.initialAddress = '',
    this.initialSmsOptIn = false,
    super.key,
  });

  /// prefill values — used when this dialog is opened while converting a
  /// work Request into a client, so the requester's own name/phone and,
  /// importantly, their SMS consent (captured pre-auth on the request form)
  /// carry forward instead of silently resetting to false on the new
  /// ClientProfile.
  final String initialFirstName;
  final String initialLastName;
  final String initialPhone;
  final String initialAddress;
  final bool initialSmsOptIn;

  @override
  State<QuickAddClientDialog> createState() => _QuickAddClientDialogState();
}

class _QuickAddClientDialogState extends State<QuickAddClientDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _firstNameController = TextEditingController(text: widget.initialFirstName);
  late final _lastNameController = TextEditingController(text: widget.initialLastName);
  late final _phoneController = TextEditingController(text: widget.initialPhone);
  late final _addressController = TextEditingController(text: widget.initialAddress);
  late bool _smsOptIn = widget.initialSmsOptIn;
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
        smsOptIn: _smsOptIn,
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
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _smsOptIn,
                  onChanged: (value) => setState(() => _smsOptIn = value ?? false),
                  title: const Text('Text message reminders'),
                  subtitle: const Text(
                      'This client has agreed to receive appointment and invoice reminders by text.'),
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
Future<ClientProfile?> showQuickAddClientDialog(
  BuildContext context, {
  String initialFirstName = '',
  String initialLastName = '',
  String initialPhone = '',
  String initialAddress = '',
  bool initialSmsOptIn = false,
}) {
  return showDialog<ClientProfile>(
    context: context,
    builder: (_) => QuickAddClientDialog(
      initialFirstName: initialFirstName,
      initialLastName: initialLastName,
      initialPhone: initialPhone,
      initialAddress: initialAddress,
      initialSmsOptIn: initialSmsOptIn,
    ),
  );
}

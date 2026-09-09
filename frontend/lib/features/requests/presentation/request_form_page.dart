import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/address_autocomplete_service.dart';
import '../../../core/services/comms_service.dart';
import '../../../core/services/job_photo_upload_service.dart';
import '../../../core/services/owner_settings_service.dart';
import '../../../core/services/request_service.dart';
import '../../../models/legal_document.dart';
import '../../../models/request.dart';
import '../../../shared/widgets/legal_link.dart';

/// standalone "request work" form — reachable both by a public, not-yet-a-client
/// lead (no [clientId]) and by a logged-in client (pre-filled with their profile)
class RequestFormPage extends StatefulWidget {
  const RequestFormPage({
    this.clientId,
    this.initialName = '',
    this.initialEmail = '',
    this.initialPhone = '',
    this.initialAddress = '',
    super.key,
  });

  final String? clientId;
  final String initialName;
  final String initialEmail;
  final String initialPhone;
  final String initialAddress;

  @override
  State<RequestFormPage> createState() => _RequestFormPageState();
}

class _RequestFormPageState extends State<RequestFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final String _requestId = RequestService.newRequestId();
  late final _nameController = TextEditingController(text: widget.initialName);
  late final _emailController = TextEditingController(text: widget.initialEmail);
  late final _phoneController = TextEditingController(text: widget.initialPhone);
  late final _addressController = TextEditingController(text: widget.initialAddress);
  final _descriptionController = TextEditingController();
  List<String> _photoUrls = const [];
  bool _isUploadingPhoto = false;
  bool _isSaving = false;
  bool _submitted = false;
  bool _smsOptIn = false;
  // form default — the SMS opt-in checkbox below stays unchecked by default
  // regardless (this field is just a stated preference for how the owner
  // should follow up, and never itself triggers or implies SMS consent)
  String _preferredContact = PreferredContactMethod.text;
  Timer? _addressDebounce;
  List<String> _addressSuggestions = const [];
  bool _isLoadingAddressSuggestions = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    _addressDebounce?.cancel();
    super.dispose();
  }

  void _onAddressChanged(String value) {
    _addressDebounce?.cancel();

    final query = value.trim();
    if (query.length < 3) {
      setState(() {
        _addressSuggestions = const [];
        _isLoadingAddressSuggestions = false;
      });
      return;
    }

    setState(() => _isLoadingAddressSuggestions = true);
    _addressDebounce = Timer(const Duration(milliseconds: 300), () async {
      final suggestions = await AddressAutocompleteService.search(query);
      if (!mounted) return;
      setState(() {
        _addressSuggestions = suggestions;
        _isLoadingAddressSuggestions = false;
      });
    });
  }

  void _pickAddressSuggestion(String value) {
    _addressController.text = value;
    setState(() {
      _addressSuggestions = const [];
      _isLoadingAddressSuggestions = false;
    });
  }

  Future<void> _addPhoto() async {
    setState(() => _isUploadingPhoto = true);
    try {
      final url = await JobPhotoUploadService.pickAndUploadRequestPhoto(requestId: _requestId);
      if (url != null && mounted) {
        setState(() => _photoUrls = [..._photoUrls, url]);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload photo: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      await RequestService.createRequest(
        id: _requestId,
        clientId: widget.clientId,
        name: _nameController.text,
        email: _emailController.text,
        phone: _phoneController.text,
        address: _addressController.text,
        description: _descriptionController.text,
        photoUrls: _photoUrls,
        smsOptIn: _smsOptIn,
        preferredContact: _preferredContact,
      );
      unawaited(_sendIntakeEmails());
      unawaited(_sendIntakeSms());
      unawaited(_sendOwnerLeadSms());
      if (mounted) setState(() => _submitted = true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit request: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _sendIntakeEmails() async {
    final name = _nameController.text.trim();
    final clientEmail = _emailController.text.trim();
    final description = _descriptionController.text.trim();

    if (clientEmail.isNotEmpty) {
      unawaited(CommsService.sendEmail(
        to: clientEmail,
        template: 'request-confirmation',
        params: {'name': name},
      ));
    }

    try {
      final ownerSettings = await OwnerSettingsService.fetch();
      final ownerEmail = ownerSettings.email.trim();
      if (ownerEmail.isNotEmpty) {
        unawaited(CommsService.sendEmail(
          to: ownerEmail,
          template: 'owner-new-lead',
          params: {'name': name, 'client_email': clientEmail, 'description': description},
        ));
      }
    } catch (_) {
      // owner settings unavailable — skip the owner notification, in-app request inbox still has it
    }
  }

  /// "request received" text to whoever just submitted — pre-auth, so this
  /// goes through CommsService.sendSmsTemplate (fixed, server-owned content,
  /// no owner token) rather than sendSms, using the phone/opt-in captured on
  /// the request form itself since a ClientProfile usually doesn't exist yet
  /// for a brand-new lead.
  Future<void> _sendIntakeSms() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || !_smsOptIn) return;

    try {
      final ownerSettings = await OwnerSettingsService.fetch();
      final businessName =
          ownerSettings.companyName.trim().isEmpty ? 'Your service provider' : ownerSettings.companyName.trim();
      unawaited(CommsService.sendSmsTemplate(
        to: phone,
        template: 'request-received',
        params: {'business_name': businessName},
      ));
    } catch (_) {
      // best-effort, same reasoning as _sendIntakeEmails above
    }
  }

  /// texts the owner's own number (OwnerSettingsService.phone, resolved
  /// here rather than trusting any caller-supplied value) that a new
  /// request came in, mirroring the existing owner-new-lead EMAIL but with
  /// the details an owner actually wants from a phone: who, their
  /// preferred way to be reached, and a link back into the app to see any
  /// attached photos. Always attempted regardless of _smsOptIn — that
  /// checkbox is the *requester's* own consent to be texted, not a gate on
  /// the owner's own lead-alert preference.
  Future<void> _sendOwnerLeadSms() async {
    try {
      final ownerSettings = await OwnerSettingsService.fetch();
      final ownerPhone = ownerSettings.phone.trim();
      if (ownerPhone.isEmpty) return;

      final description = _descriptionController.text.trim();
      final truncatedDescription =
          description.length > 160 ? '${description.substring(0, 160)}...' : description;

      unawaited(CommsService.sendSmsTemplate(
        to: ownerPhone,
        template: 'owner-new-lead',
        params: {
          'name': _nameController.text.trim(),
          'preferred_contact': PreferredContactMethod.label(_preferredContact),
          'phone': _phoneController.text.trim(),
          'email': _emailController.text.trim(),
          'address': _addressController.text.trim(),
          'description': truncatedDescription,
          // root link, not a deep link to this specific request — no
          // externally-reachable per-request route exists yet (see
          // app.dart's _resolveInitialHome for the app's only two cold-link
          // carve-outs, neither of which is this). The owner is expected to
          // already be signed in and just needs to open Requests.
          'link': Uri.base.origin,
        },
      ));
    } catch (_) {
      // best-effort, same reasoning as _sendIntakeEmails above
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request Work')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _submitted ? _buildConfirmation(context) : _buildForm(context),
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmation(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
        const SizedBox(height: 12),
        Text('Request sent!', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          "We'll review your request and follow up soon.",
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    return SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tell us what you need done and we\'ll get back to you with a quote.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
              keyboardType: TextInputType.emailAddress,
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Email is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder()),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _smsOptIn,
                  onChanged: (value) => setState(() => _smsOptIn = value ?? false),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      "I'd like to receive text message updates about this request (optional). "
                      'Message and data rates may apply. Reply STOP at any time to opt out.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _preferredContact,
              decoration: const InputDecoration(
                labelText: 'Preferred way to be contacted',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final method in PreferredContactMethod.all)
                  DropdownMenuItem(value: method, child: Text(PreferredContactMethod.label(method))),
              ],
              onChanged: (value) => setState(() => _preferredContact = value ?? PreferredContactMethod.text),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressController,
              decoration: InputDecoration(
                labelText: 'Address',
                border: const OutlineInputBorder(),
                suffixIcon: _isLoadingAddressSuggestions
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
              onChanged: _onAddressChanged,
            ),
            if (_addressSuggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _addressSuggestions.length,
                    itemBuilder: (context, index) {
                      final suggestion = _addressSuggestions[index];
                      return ListTile(
                        dense: true,
                        title: Text(suggestion),
                        onTap: () => _pickAddressSuggestion(suggestion),
                      );
                    },
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'What do you need done?',
                border: OutlineInputBorder(),
              ),
              minLines: 3,
              maxLines: 6,
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Please describe the work' : null,
            ),
            const SizedBox(height: 12),
            if (_photoUrls.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final url in _photoUrls)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(url, width: 64, height: 64, fit: BoxFit.cover),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _isUploadingPhoto ? null : _addPhoto,
              icon: _isUploadingPhoto
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_a_photo_outlined),
              label: const Text('Add Photo'),
            ),
            const SizedBox(height: 12),
            Wrap(
              children: [
                Text('By submitting, you agree to our ', style: Theme.of(context).textTheme.bodySmall),
                const LegalLink(label: 'Privacy Policy', documentId: LegalDocumentIds.privacyPolicy),
                Text('.', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _isSaving ? null : _submit,
              child: _isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Submit Request'),
            ),
          ],
        ),
      ),
    );
  }
}

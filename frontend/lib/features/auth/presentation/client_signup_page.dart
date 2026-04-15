// made with help of chatgpt: create a flutter client signup page outline with a form. include fields for first name, last name, email, phone, address (street, country, zip)

import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/client_profile_service.dart';
import '../../../core/state/client_session.dart';

class ClientSignupPage extends StatefulWidget {
  const ClientSignupPage({super.key});

  @override
  State<ClientSignupPage> createState() => _ClientSignupPageState();
}

class _ClientSignupPageState extends State<ClientSignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _streetController = TextEditingController();
  final _countryController = TextEditingController();
  final _zipController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  bool _looksLikeEmail(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.contains(' ')) {
      return false;
    }
    final parts = trimmed.split('@');
    if (parts.length != 2) {
      return false;
    }
    if (parts.first.isEmpty || parts.last.isEmpty) {
      return false;
    }
    if (!parts.last.contains('.')) {
      return false;
    }
    if (trimmed.contains(',')) {
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _streetController.dispose();
    _countryController.dispose();
    _zipController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final apiClient = ApiClient(baseUrl: AppConfig.apiBaseUrl);
      final firstName = _firstNameController.text.trim();
      final lastName = _lastNameController.text.trim();
      final fullName = '$firstName $lastName'.trim();
      final createdClient = await apiClient.postJson('/api/v1/public/client-signups', {
        'name': fullName,
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'address': {
          'street': _streetController.text.trim(),
          'country': _countryController.text.trim(),
          'zip_code': _zipController.text.trim(),
        },
      });

      final savedProfile = await ClientProfileService.getOrCreateForSignup(
        signupId: (createdClient['id'] as String? ?? '').trim(),
        email: (createdClient['email'] as String? ?? _emailController.text.trim()),
        firstName: firstName,
        lastName: lastName,
        phone: _phoneController.text.trim(),
        street: _streetController.text.trim(),
        country: _countryController.text.trim(),
        zipCode: _zipController.text.trim(),
      );
      ClientSession.setProfile(savedProfile);

      if (!mounted) {
        return;
      }

      Navigator.pushReplacementNamed(
        context,
        AppRouter.dashboard,
        arguments: {'role': 'client', 'authToken': 'dev-client'},
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Client Sign Up')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Enter your details to continue.'),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _firstNameController,
                          decoration: const InputDecoration(labelText: 'First name', border: OutlineInputBorder()),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty) ? 'First name is required' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _lastNameController,
                          decoration: const InputDecoration(labelText: 'Last name', border: OutlineInputBorder()),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty) ? 'Last name is required' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      final input = value?.trim() ?? '';
                      if (input.isEmpty) {
                        return 'Email is required';
                      }
                      if (!_looksLikeEmail(input)) {
                        return 'Enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder()),
                    keyboardType: TextInputType.phone,
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Phone is required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _streetController,
                    decoration: const InputDecoration(labelText: 'Street', border: OutlineInputBorder()),
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Street is required' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _countryController,
                          decoration: const InputDecoration(labelText: 'Country', border: OutlineInputBorder()),
                          validator: (value) => (value == null || value.trim().isEmpty) ? 'Country is required' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _zipController,
                          decoration: const InputDecoration(labelText: 'ZIP', border: OutlineInputBorder()),
                          validator: (value) => (value == null || value.trim().isEmpty) ? 'ZIP is required' : null,
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Continue'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
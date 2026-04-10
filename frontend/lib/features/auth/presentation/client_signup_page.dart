import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/client_profile_service.dart';
import '../../../core/state/client_session.dart';
import '../../../models/client_profile.dart';

class ClientSignupPage extends StatefulWidget {
  const ClientSignupPage({super.key});

  @override
  State<ClientSignupPage> createState() => _ClientSignupPageState();
}

class _ClientSignupPageState extends State<ClientSignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _streetController = TextEditingController();
  final _countryController = TextEditingController();
  final _zipController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
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
      await apiClient.postJson('/api/v1/public/client-signups', {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'address': {
          'street': _streetController.text.trim(),
          'country': _countryController.text.trim(),
          'zip_code': _zipController.text.trim(),
        },
      });

      final nameParts = _nameController.text.trim().split(RegExp(r'\s+'));
      final firstName = nameParts.isNotEmpty ? nameParts.first : '';
      final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

      final savedProfile = await ClientProfileService.save(
        ClientProfile(
          email: _emailController.text.trim(),
          firstName: firstName,
          lastName: lastName,
          phone: _phoneController.text.trim(),
          street: _streetController.text.trim(),
          country: _countryController.text.trim(),
          zipCode: _zipController.text.trim(),
        ),
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
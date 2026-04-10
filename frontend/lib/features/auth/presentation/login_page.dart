import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/api_client.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isClientLoginMode = false;
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _enterAsOwner() {
    Navigator.pushReplacementNamed(
      context,
      AppRouter.dashboard,
      arguments: {'role': 'owner', 'authToken': 'dev-owner'},
    );
  }

  void _enterAsClient() {
    setState(() {
      _isClientLoginMode = !_isClientLoginMode;
      _error = null;
    });
  }

  void _goToSignup() {
    Navigator.pushNamed(context, AppRouter.clientSignup);
  }

  Future<void> _loginExistingClient() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final apiClient = ApiClient(baseUrl: AppConfig.apiBaseUrl);
      final client = await apiClient.postJson('/api/v1/public/client-login', {
        'email': _emailController.text.trim(),
      });

      if (!mounted) {
        return;
      }

      Navigator.pushReplacementNamed(
        context,
        AppRouter.dashboard,
        arguments: {
          'role': 'client',
          'authToken': 'dev-client',
          'clientName': client['name'],
          'clientEmail': client['email'],
        },
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Anchor', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Choose how you want to continue.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _enterAsOwner,
                    icon: const Icon(Icons.storefront_outlined),
                    label: const Text('Continue as Business Owner'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _enterAsClient,
                    icon: const Icon(Icons.person_outline),
                    label: Text(_isClientLoginMode ? 'Back to Client Options' : 'Continue as Client'),
                  ),
                  if (_isClientLoginMode) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Client access',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'If you already signed up, enter your email to continue. Otherwise, create a new client profile.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    Form(
                      key: _formKey,
                      child: TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Client email',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Email is required';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _isSubmitting ? null : _loginExistingClient,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Log in as Existing Client'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _goToSignup,
                      child: const Text('Create a New Client Profile'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

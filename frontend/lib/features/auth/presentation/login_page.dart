import 'package:flutter/material.dart';

import '../../../core/services/client_profile_service.dart';
import '../../../core/state/client_session.dart';
import '../../../core/router/app_router.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _goToSignup() {
    Navigator.pushNamed(context, AppRouter.clientSignup);
  }

  Future<void> _loginClient() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final profile = await ClientProfileService.getOrCreate(_emailController.text);
      ClientSession.setProfile(profile);

      if (!mounted) {
        return;
      }

      Navigator.pushReplacementNamed(
        context,
        AppRouter.dashboard,
        arguments: {
          'role': 'client',
          'authToken': 'dev-client',
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
                    'Enter your email to continue.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  Form(
                    key: _formKey,
                    child: TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        final input = value?.trim() ?? '';
                        if (input.isEmpty) {
                          return 'Email is required';
                        }
                        if (!input.contains('@')) {
                          return 'Enter a valid email';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _isSubmitting ? null : _loginClient,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Log in'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _goToSignup,
                    child: const Text('Create Client Profile'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
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

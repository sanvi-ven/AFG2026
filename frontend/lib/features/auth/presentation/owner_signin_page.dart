//made with help of chatgpt: create a simple flutter owner login page with a password field

import 'package:flutter/material.dart';

import '../../../core/router/app_router.dart';
import '../../../shared/widgets/app_logo.dart';

class OwnerSigninPage extends StatefulWidget {
  const OwnerSigninPage({super.key});

  @override
  State<OwnerSigninPage> createState() => _OwnerSigninPageState();
}

class _OwnerSigninPageState extends State<OwnerSigninPage> {
  static const _ownerPassword = '12345';

  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInOwner() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final input = _passwordController.text.trim();
    if (input != _ownerPassword) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _error = 'Incorrect password';
      });
      return;
    }

    if (!mounted) {
      return;
    }

    Navigator.pushReplacementNamed(
      context,
      AppRouter.dashboard,
      arguments: {
        'role': 'owner',
        'authToken': 'dev-owner',
      },
    );
  }

  void _backToClientLogin() {
    Navigator.pop(context);
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
                  const Center(child: AppLogo(size: 72)),
                  const SizedBox(height: 12),
                  Text('Business Owner Sign In', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Enter owner password to continue.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  Form(
                    key: _formKey,
                    child: TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final input = value?.trim() ?? '';
                        if (input.isEmpty) {
                          return 'Password is required';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _isSubmitting ? null : _signInOwner(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _isSubmitting ? null : _signInOwner,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign In'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _backToClientLogin,
                    child: const Text('Back To Client Login'),
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

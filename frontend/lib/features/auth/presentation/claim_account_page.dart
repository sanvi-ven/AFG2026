import 'package:flutter/material.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/client_auth_service.dart';
import '../../../core/services/session_persistence_service.dart';
import '../../../core/state/client_session.dart';
import '../../../shared/widgets/app_logo.dart';

/// lets a client with a code from the business owner turn their dummy
/// (no-login) account into a real one with an email and password
class ClaimAccountPage extends StatefulWidget {
  const ClaimAccountPage({super.key});

  @override
  State<ClaimAccountPage> createState() => _ClaimAccountPageState();
}

class _ClaimAccountPageState extends State<ClaimAccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final profile = await ClientAuthService.claimAccount(
        code: _codeController.text,
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      ClientSession.setProfile(profile);
      await SessionPersistenceService.saveClientSession(profile);

      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        AppRouter.dashboard,
        arguments: {'role': 'client', 'authToken': 'dev-client'},
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            AppLogo(size: 22),
            SizedBox(width: 10),
            Text('Claim Your Account'),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: AppLogo(size: 56)),
                  const SizedBox(height: 12),
                  const Text('Enter the code your business owner gave you, then set your email and password.'),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Claim code', border: OutlineInputBorder()),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'Claim code is required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      final input = value?.trim() ?? '';
                      if (input.isEmpty) return 'Email is required';
                      if (!input.contains('@')) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                    obscureText: true,
                    validator: (value) {
                      final input = value ?? '';
                      if (input.isEmpty) return 'Password is required';
                      if (input.length < 8) return 'Password must be at least 8 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmPasswordController,
                    decoration: const InputDecoration(labelText: 'Confirm password', border: OutlineInputBorder()),
                    obscureText: true,
                    validator: (value) {
                      if ((value ?? '').isEmpty) return 'Confirm your password';
                      if (value != _passwordController.text) return 'Passwords do not match';
                      return null;
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Claim Account'),
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

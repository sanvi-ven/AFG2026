import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/auth_api_service.dart';
import '../../../core/state/client_session.dart';
import '../../../models/client_profile.dart';
import '../../../models/legal_document.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../shared/widgets/legal_link.dart';

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
  bool _agreedToTerms = false;
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
    if (!_agreedToTerms) {
      setState(() => _error = 'Please agree to the Privacy Policy and Terms of Service to continue.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final response = await AuthApiService.claimAccount(
        code: _codeController.text,
        email: email,
        password: password,
      );

      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final idToken = await credential.user!.getIdToken();

      final profile = ClientProfile.fromMap(response);
      ClientSession.setProfile(profile);

      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        AppRouter.dashboard,
        arguments: {'role': 'client', 'authToken': idToken},
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message ?? 'Could not sign in.');
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
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _agreedToTerms,
                        onChanged: (value) => setState(() => _agreedToTerms = value ?? false),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Wrap(
                            children: [
                              const Text('I agree to the '),
                              const LegalLink(
                                  label: 'Privacy Policy', documentId: LegalDocumentIds.privacyPolicy),
                              const Text(' and '),
                              const LegalLink(
                                  label: 'Terms of Service', documentId: LegalDocumentIds.termsOfService),
                              const Text('.'),
                            ],
                          ),
                        ),
                      ),
                    ],
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

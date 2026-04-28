//made with help of chatgpt: to create a login page scaffold & how to call backedend api to login client

import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/client_profile_service.dart';
import '../../../core/state/client_session.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/app_logo.dart';

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

  void _goToOwnerSignin() {
    Navigator.pushNamed(context, AppRouter.ownerSignin);
  }

  Future<Map<String, dynamic>> _loginViaApi(String email) async {
    final primaryBaseUrl = AppConfig.apiBaseUrl.trim();
    final candidateBaseUrls = <String>[primaryBaseUrl];
    if (primaryBaseUrl.contains('127.0.0.1')) {
      candidateBaseUrls.add(primaryBaseUrl.replaceAll('127.0.0.1', 'localhost'));
    } else if (primaryBaseUrl.contains('localhost')) {
      candidateBaseUrls.add(primaryBaseUrl.replaceAll('localhost', '127.0.0.1'));
    }

    Object? lastError;
    for (final baseUrl in candidateBaseUrls.toSet()) {
      try {
        final apiClient = ApiClient(baseUrl: baseUrl);
        return await apiClient.postJson('/api/v1/public/client-login', {
          'email': email,
        });
      } catch (error) {
        lastError = error;
      }
    }

    throw Exception(lastError?.toString() ?? 'Login API unavailable.');
  }

  Future<void> _loginWithFirestoreFallback({
    required String email,
    required Object apiError,
  }) async {
    final fallbackProfile = await ClientProfileService.fetchByEmail(email);
    if (fallbackProfile == null) {
      throw Exception(apiError.toString().replaceFirst('Exception: ', ''));
    }
    ClientSession.setProfile(fallbackProfile);
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
      final email = _emailController.text.trim();
      try {
        final client = await _loginViaApi(email);

        final rawName = (client['name'] as String? ?? '').trim();
        final nameParts = rawName.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
        final firstName =
            (client['first_name'] as String? ?? (nameParts.isNotEmpty ? nameParts.first : '')).trim();
        final lastName =
            (client['last_name'] as String? ??
                    (nameParts.length > 1 ? nameParts.sublist(1).join(' ') : ''))
                .trim();
        final rawAddress = client['address'];
        final fallbackAddressMap = rawAddress is Map
          ? rawAddress.map((key, value) => MapEntry(key.toString(), value))
          : const <String, dynamic>{};
        final parsedAddress = (client['address'] as String? ?? '').trim().isNotEmpty
            ? (client['address'] as String).trim()
            : [
                (fallbackAddressMap['street'] as String? ?? '').trim(),
                (fallbackAddressMap['country'] as String? ?? '').trim(),
                (fallbackAddressMap['zip_code'] as String? ?? '').trim(),
              ].where((part) => part.isNotEmpty).join(', ');

        final profile = await ClientProfileService.getOrCreateForSignup(
          signupId: (client['id'] as String? ?? '').trim(),
          email: (client['email'] as String? ?? email),
          firstName: firstName,
          lastName: lastName,
          phoneNumber: (client['phone_number'] as String? ?? client['phone'] as String? ?? '').trim(),
          address: parsedAddress,
        );
        ClientSession.setProfile(profile);
      } catch (apiError) {
        await _loginWithFirestoreFallback(email: email, apiError: apiError);
      }

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
                  const Center(child: AppLogo(size: 72)),
                  const SizedBox(height: 12),
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
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _goToOwnerSignin,
                    child: const Text('Business Owner Sign In'),
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

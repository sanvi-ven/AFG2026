import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/router/app_router.dart';
import '../data/auth_repository.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final AuthRepository _authRepository;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _authRepository = AuthRepository(ApiClient(baseUrl: AppConfig.apiBaseUrl));

    final demoToken = AppConfig.demoAuthToken.trim();
    if (demoToken.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _signInWithToken(demoToken);
      });
    }
  }

  Future<void> _signInWithToken(String token) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final appUser = await _authRepository.authenticateGoogleToken(token);
      if (!mounted) {
        return;
      }
      Navigator.pushReplacementNamed(
        context,
        AppRouter.dashboard,
        arguments: {'role': appUser.role, 'authToken': token},
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = (error as dynamic).toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signInDemoOwner() => _signInWithToken('dev-owner');

  Future<void> _signInDemoClient() => _signInWithToken('dev-client');

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userCredential = await FirebaseService.signInWithGoogle();
      final idToken = await userCredential.user!.getIdToken();
      if (idToken == null) {
        throw Exception('Failed to get ID token');
      }
      final appUser = await _authRepository.authenticateGoogleToken(idToken);
      if (!mounted) {
        return;
      }
      Navigator.pushReplacementNamed(
        context,
        AppRouter.dashboard,
        arguments: {'role': appUser.role, 'authToken': idToken},
      );
    } catch (error) {
      setState(() {
        _error = (error as dynamic).toString().replaceFirst('Exception: ', '');
        if (_error!.contains('sign-in')) {
          _error = 'Google sign-in was canceled or failed. Please try again.';
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
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
                  Text('Small Biz Manager', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in with your Google account to get started.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _signInWithGoogle,
                    icon: const Icon(Icons.login),
                    label: const Text('Sign In with Google'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          'Demo',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _signInDemoOwner,
                    icon: const Icon(Icons.storefront_outlined),
                    label: const Text('Demo Sign In as Business Owner'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _signInDemoClient,
                    icon: const Icon(Icons.person_outline),
                    label: const Text('Demo Sign In as Client'),
                  ),
                  if (_isLoading) ...[
                    const SizedBox(height: 16),
                    const Center(child: CircularProgressIndicator()),
                  ],
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

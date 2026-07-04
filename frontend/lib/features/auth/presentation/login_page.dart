//made with help of chatgpt 4.0: to create a login page scaffold & how to call backedend api to login client

import 'package:flutter/material.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/client_auth_service.dart';
import '../../../core/services/employee_auth_service.dart';
import '../../../core/services/session_persistence_service.dart';
import '../../../core/state/client_session.dart';
import '../../../core/state/employee_session.dart';
import '../../../shared/widgets/app_logo.dart';

/// login page for client email/password authentication
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;
  String? _error;
  String _selectedRole = 'client';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _goToSignup() {
    Navigator.pushNamed(
      context,
      _selectedRole == 'employee' ? AppRouter.employeeSignup : AppRouter.clientSignup,
    );
  }

  void _goToOwnerSignin() {
    Navigator.pushNamed(context, AppRouter.ownerSignin);
  }

  void _goToClaimAccount() {
    Navigator.pushNamed(context, AppRouter.claimAccount);
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      if (_selectedRole == 'employee') {
        final profile = await EmployeeAuthService.login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        EmployeeSession.setProfile(profile);
        await SessionPersistenceService.saveEmployeeSession(profile);

        if (!mounted) return;
        Navigator.pushReplacementNamed(
          context,
          AppRouter.dashboard,
          arguments: {'role': 'employee', 'authToken': 'dev-employee'},
        );
        return;
      }

      final profile = await ClientAuthService.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      ClientSession.setProfile(profile);
      await SessionPersistenceService.saveClientSession(profile);

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
                    'Enter your email and password to continue.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'client', label: Text('Client')),
                      ButtonSegment(value: 'employee', label: Text('Employee')),
                    ],
                    selected: {_selectedRole},
                    onSelectionChanged: (selection) {
                      setState(() => _selectedRole = selection.first);
                    },
                  ),
                  const SizedBox(height: 16),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
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
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if ((value ?? '').isEmpty) {
                              return 'Password is required';
                            }
                            return null;
                          },
                          onFieldSubmitted: (_) => _isSubmitting ? null : _login(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _isSubmitting ? null : _login,
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
                    child: Text(_selectedRole == 'employee' ? 'Create Employee Profile' : 'Create Client Profile'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _goToOwnerSignin,
                    child: const Text('Business Owner Sign In'),
                  ),
                  if (_selectedRole == 'client') ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _goToClaimAccount,
                      child: const Text('Have work done already? Claim your account'),
                    ),
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

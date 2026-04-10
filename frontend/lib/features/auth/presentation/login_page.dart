import 'package:flutter/material.dart';

import '../../../core/router/app_router.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  void _enterAsOwner() {
    Navigator.pushReplacementNamed(
      context,
      AppRouter.dashboard,
      arguments: {'role': 'owner', 'authToken': 'dev-owner'},
    );
  }

  void _enterAsClient() {
    Navigator.pushNamed(context, AppRouter.clientSignup);
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
                    label: const Text('Continue as Client (Sign Up)'),
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

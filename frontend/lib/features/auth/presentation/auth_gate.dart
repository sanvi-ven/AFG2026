import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/api_client.dart';
import '../../../models/app_user.dart';
import '../../dashboard/presentation/dashboard_page.dart';
import 'login_page.dart';
import '../data/auth_repository.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const LoginPage();
        }

        return FutureBuilder<_AuthGateResult>(
          future: _loadUser(user),
          builder: (context, authSnapshot) {
            if (authSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (authSnapshot.hasError || !authSnapshot.hasData) {
              return const LoginPage();
            }

            final result = authSnapshot.data!;
            return DashboardPage(
              role: result.appUser.role,
              authToken: result.idToken,
            );
          },
        );
      },
    );
  }
// with https://firebase.google.com/docs/auth/admin/verify-id-tokens
  Future<_AuthGateResult> _loadUser(User user) async {
    final idToken = await user.getIdToken(true);
    if (idToken == null || idToken.isEmpty) {
      throw Exception('No Firebase token available');
    }

    final repository = AuthRepository(ApiClient(baseUrl: AppConfig.apiBaseUrl));
    final appUser = await repository.authenticateGoogleToken(idToken);
    return _AuthGateResult(appUser: appUser, idToken: idToken);
  }
}

class _AuthGateResult {
  _AuthGateResult({required this.appUser, required this.idToken});

  final AppUser appUser;
  final String idToken;
}
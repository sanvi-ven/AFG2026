import '../config/app_config.dart';
import 'api_client.dart';

/// backend calls that assign a role to a Firebase Auth user — custom claims
/// can only be set server-side — and create/link the matching Firestore
/// profile record. See backend/app/api/v1/routes/auth.py; the response
/// shape matches ClientProfile.fromMap/EmployeeProfile.fromMap directly.
class AuthApiService {
  AuthApiService._();

  /// finishes onboarding a Firebase Auth user that was just created or
  /// signed in client-side: grants [role] (validated server-side against
  /// the owner allowlist / a real invite code) and creates their profile.
  /// [idToken] must be a fresh token for the user being onboarded.
  static Future<Map<String, dynamic>> completeSignup({
    required String idToken,
    required String role,
    required String firstName,
    required String lastName,
    String phoneNumber = '',
    String address = '',
    String? inviteCode,
  }) {
    final client = ApiClient(baseUrl: AppConfig.apiBaseUrl, authToken: idToken);
    return client.postJson('/api/v1/auth/complete-signup', {
      'role': role,
      'first_name': firstName,
      'last_name': lastName,
      'phone_number': phoneNumber,
      'address': address,
      if (inviteCode != null) 'invite_code': inviteCode,
    });
  }

  /// turns an owner-created dummy client into a real login: validates the
  /// one-time claim code server-side, then creates the Firebase Auth
  /// account for it. Caller should sign in with the same email/password
  /// immediately after this succeeds.
  static Future<Map<String, dynamic>> claimAccount({
    required String code,
    required String email,
    required String password,
  }) {
    final client = ApiClient(baseUrl: AppConfig.apiBaseUrl);
    return client.postJson('/api/v1/auth/claim-account', {
      'code': code,
      'email': email,
      'password': password,
    });
  }
}

import '../../models/client_profile.dart';
import '../config/app_config.dart';
import 'api_client.dart';

class ClientAuthService {
  ClientAuthService._();

  static Future<ClientProfile> signUp({
    required String email,
    required String firstName,
    required String lastName,
    required String phoneNumber,
    required String address,
    required String password,
  }) async {
    final response = await _postWithFallback('/api/v1/public/client-signups', {
      'email': email.trim(),
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
      'phone_number': phoneNumber.trim(),
      'address': address.trim(),
      'password': password,
    });
    return ClientProfile.fromMap(response).copyWith(
      signupId: (response['id'] as String? ?? '').trim(),
    );
  }

  static Future<ClientProfile> login({
    required String email,
    required String password,
  }) async {
    final response = await _postWithFallback('/api/v1/public/client-login', {
      'email': email.trim(),
      'password': password,
    });
    return ClientProfile.fromMap(response).copyWith(
      signupId: (response['id'] as String? ?? '').trim(),
    );
  }

  static Future<void> changePassword({
    required String email,
    required String oldPassword,
    required String newPassword,
  }) async {
    await _postWithFallback('/api/v1/public/client-password', {
      'email': email.trim(),
      'old_password': oldPassword,
      'new_password': newPassword,
    });
  }

  static List<String> _candidateBaseUrls() {
    final primaryBaseUrl = AppConfig.apiBaseUrl.trim();
    final candidateBaseUrls = <String>[primaryBaseUrl];
    if (primaryBaseUrl.contains('127.0.0.1')) {
      candidateBaseUrls.add(primaryBaseUrl.replaceAll('127.0.0.1', 'localhost'));
    } else if (primaryBaseUrl.contains('localhost')) {
      candidateBaseUrls.add(primaryBaseUrl.replaceAll('localhost', '127.0.0.1'));
    }
    return candidateBaseUrls.toSet().where((value) => value.trim().isNotEmpty).toList();
  }

  static Future<Map<String, dynamic>> _postWithFallback(
    String path,
    Map<String, dynamic> body,
  ) async {
    Object? lastError;
    for (final baseUrl in _candidateBaseUrls()) {
      try {
        final apiClient = ApiClient(baseUrl: baseUrl);
        return await apiClient.postJson(path, body);
      } catch (error) {
        lastError = error;
      }
    }
    throw Exception(lastError?.toString() ?? 'Client auth API unavailable.');
  }
}

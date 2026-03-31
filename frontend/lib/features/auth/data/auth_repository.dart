import '../../../core/services/api_client.dart';
import '../../../models/app_user.dart';

class AuthRepository {
  AuthRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<AppUser> authenticateGoogleToken(String idToken) async {
    final payload = await _apiClient.postJson('/api/v1/auth/google', {'id_token': idToken});
    return AppUser.fromJson(payload);
  }
}

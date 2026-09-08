import '../config/app_config.dart';
import 'api_client.dart';

/// backend calls for the guardian employment-contract co-sign flow. See
/// backend/app/api/v1/routes/contracts.py. sendGuardianLink is an
/// authenticated call (owner or the contract's own employee); guardianView/
/// guardianSign are pre-auth, gated by the mailed one-time token instead.
class ContractApiService {
  ContractApiService._();

  /// owner or the contract's own employee: (re)send the guardian co-sign
  /// link by email. [recordId] is an employment_contracts doc id (==
  /// employeeId) or a contract_amendments doc id — the same endpoint
  /// handles both, see the backend route's own doc comment.
  static Future<bool> sendGuardianLink({
    required String recordId,
    required String authToken,
  }) async {
    final client = ApiClient(baseUrl: AppConfig.apiBaseUrl, authToken: authToken);
    final response =
        await client.postJson('/api/v1/contracts/${Uri.encodeComponent(recordId)}/send-guardian-link', {});
    return response['sent'] as bool? ?? false;
  }

  /// pre-auth: what a guardian sees before signing, resolved by token.
  static Future<Map<String, dynamic>> guardianView({required String token}) async {
    final client = ApiClient(baseUrl: AppConfig.apiBaseUrl);
    return client.getJson('/api/v1/contracts/guardian-view?token=${Uri.encodeQueryComponent(token)}');
  }

  /// pre-auth: submit the guardian's signature/initials.
  static Future<bool> guardianSign({
    required String token,
    required String method,
    String typedName = '',
    String drawingBase64 = '',
    required bool consentChecked,
    required String consentText,
  }) async {
    final client = ApiClient(baseUrl: AppConfig.apiBaseUrl);
    final response = await client.postJson('/api/v1/contracts/guardian-sign', {
      'token': token,
      'method': method,
      'typed_name': typedName,
      'drawing_base64': drawingBase64,
      'consent_checked': consentChecked,
      'consent_text': consentText,
    });
    return response['sent'] as bool? ?? false;
  }
}

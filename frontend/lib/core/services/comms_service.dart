import '../config/app_config.dart';
import 'api_client.dart';

/// sends real email/sms through the backend (comms router), which holds the
/// Resend/Twilio API keys server-side. Fire-and-forget by design, mirroring
/// the in-app notification calls this is meant to sit alongside — a failed
/// send (e.g. backend not yet deployed, provider not configured) shouldn't
/// block the in-app notification or the action that triggered it.
class CommsService {
  CommsService._();

  static final _client = ApiClient(baseUrl: AppConfig.apiBaseUrl);

  static Future<bool> sendEmail({
    required String to,
    required String subject,
    required String htmlBody,
  }) async {
    try {
      await _client.postJson('/api/v1/comms/email', {
        'to': to,
        'subject': subject,
        'html_body': htmlBody,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> sendSms({required String to, required String body}) async {
    try {
      await _client.postJson('/api/v1/comms/sms', {'to': to, 'body': body});
      return true;
    } catch (_) {
      return false;
    }
  }
}

import 'package:firebase_auth/firebase_auth.dart';

import '../config/app_config.dart';
import 'api_client.dart';

/// sends real email/sms through the backend (comms router), which holds the
/// Resend/Twilio API keys server-side. Fire-and-forget by design, mirroring
/// the in-app notification calls this is meant to sit alongside — a failed
/// send (e.g. backend not yet deployed, provider not configured) shouldn't
/// block the in-app notification or the action that triggered it.
///
/// Email is template-only (no raw subject/HTML) — the backend owns the
/// actual content, see backend/app/services/email_service.py for the fixed
/// set of template names. `appointment-reminder`/`invoice-reminder` require
/// an owner session; `request-confirmation`/`owner-new-lead` are reachable
/// pre-auth (the public "Request a Quote" form). SMS always requires an
/// owner session — there's no pre-auth caller for it.
class CommsService {
  CommsService._();

  static const Set<String> _ownerOnlyEmailTemplates = {
    'appointment-reminder',
    'invoice-reminder',
  };

  static Future<String?> _ownerAuthToken() async {
    return FirebaseAuth.instance.currentUser?.getIdToken();
  }

  static Future<bool> sendEmail({
    required String to,
    required String template,
    Map<String, String> params = const {},
  }) async {
    try {
      final token = _ownerOnlyEmailTemplates.contains(template) ? await _ownerAuthToken() : null;
      final client = ApiClient(baseUrl: AppConfig.apiBaseUrl, authToken: token);
      await client.postJson('/api/v1/comms/email', {
        'to': to,
        'template': template,
        'params': params,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> sendSms({required String to, required String body}) async {
    try {
      final token = await _ownerAuthToken();
      final client = ApiClient(baseUrl: AppConfig.apiBaseUrl, authToken: token);
      await client.postJson('/api/v1/comms/sms', {'to': to, 'body': body});
      return true;
    } catch (_) {
      return false;
    }
  }
}

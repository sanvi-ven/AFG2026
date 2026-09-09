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
/// pre-auth (the public "Request a Quote" form). SMS with a caller-composed
/// `body` (sendSms) always requires an owner session; the one exception is
/// `sendSmsTemplate`, which — like the two pre-auth email templates — sends
/// server-owned, fixed-content SMS (see sms_service.py) with no owner token
/// attached, for the public request form's "request received" confirmation.
class CommsService {
  CommsService._();

  static const Set<String> _ownerOnlyEmailTemplates = {
    'appointment-reminder',
    'invoice-reminder',
  };

  static Future<String?> _ownerAuthToken() async {
    return FirebaseAuth.instance.currentUser?.getIdToken();
  }

  /// normalizes a US phone number to E.164 (+1XXXXXXXXXX) — the format
  /// SmsSendRequest.to strictly requires server-side (a `^\+[1-9]\d{1,14}$`
  /// pattern). Every phone number stored in this app (ClientProfile.
  /// phoneNumber, EmployeeProfile.phoneNumber, OwnerSettings.phone,
  /// Request.phone) is a free-text field with no format enforcement at
  /// entry time — e.g. OwnerSettings.phone is stored as "774-559-9448", not
  /// "+17745599448" — so every SMS send has to normalize just before
  /// hitting the API rather than trusting the stored value's shape.
  /// Confirmed live 2026-09-09: the request-form's owner-new-lead and
  /// request-received sends were both 422ing silently (CommsService
  /// swallows the error) specifically because of this — every phone number
  /// passed straight through unnormalized. Returns null if the input can't
  /// be confidently normalized (not a plausible 10 or 11-digit US number,
  /// and not already E.164), so the caller can skip the send rather than
  /// burn a guaranteed-to-fail API call.
  static String? _toE164(String rawPhone) {
    final trimmed = rawPhone.trim();
    if (trimmed.startsWith('+')) {
      final candidate = trimmed.replaceAll(RegExp(r'[^\d+]'), '');
      return RegExp(r'^\+[1-9]\d{1,14}$').hasMatch(candidate) ? candidate : null;
    }
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) {
      return '+1$digits';
    }
    if (digits.length == 11 && digits.startsWith('1')) {
      return '+$digits';
    }
    return null;
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
    final normalizedTo = _toE164(to);
    if (normalizedTo == null) return false;
    try {
      final token = await _ownerAuthToken();
      final client = ApiClient(baseUrl: AppConfig.apiBaseUrl, authToken: token);
      await client.postJson('/api/v1/comms/sms', {'to': normalizedTo, 'body': body});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// pre-auth SMS send — `template` must be one of the fixed names
  /// SmsService recognizes server-side (currently just 'request-received');
  /// no owner token is attached, since this is meant to be callable from
  /// the public "Request a Quote" form before anyone has signed in.
  static Future<bool> sendSmsTemplate({
    required String to,
    required String template,
    Map<String, String> params = const {},
  }) async {
    final normalizedTo = _toE164(to);
    if (normalizedTo == null) return false;
    try {
      final client = ApiClient(baseUrl: AppConfig.apiBaseUrl);
      await client.postJson('/api/v1/comms/sms', {
        'to': normalizedTo,
        'template': template,
        'params': params,
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}

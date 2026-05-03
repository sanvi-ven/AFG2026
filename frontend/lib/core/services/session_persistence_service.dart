import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/client_profile.dart';

class RestoredSession {
  const RestoredSession({required this.role, this.profile});

  final String role;
  final ClientProfile? profile;
}

class SessionPersistenceService {
  SessionPersistenceService._();

  static const _keyRole = 'session_role';
  static const _keyLoggedInAt = 'session_logged_in_at';
  static const _keyClientProfile = 'session_client_profile';
  // 3 days in milliseconds
  static const _webExpiryMs = 3 * 24 * 60 * 60 * 1000;

  static Future<void> saveClientSession(ClientProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRole, 'client');
    await prefs.setInt(_keyLoggedInAt, DateTime.now().millisecondsSinceEpoch);
    await prefs.setString(_keyClientProfile, jsonEncode(profile.toMap()));
  }

  static Future<void> saveOwnerSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRole, 'owner');
    await prefs.setInt(_keyLoggedInAt, DateTime.now().millisecondsSinceEpoch);
    await prefs.remove(_keyClientProfile);
  }

  /// Returns the stored session, or null if none exists or it has expired (web only).
  static Future<RestoredSession?> loadSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString(_keyRole);
      if (role == null || role.isEmpty) return null;

      // On web, expire after 3 days. On native, the session never expires.
      if (kIsWeb) {
        final loggedInAt = prefs.getInt(_keyLoggedInAt) ?? 0;
        final ageMs = DateTime.now().millisecondsSinceEpoch - loggedInAt;
        if (ageMs > _webExpiryMs) {
          await clearSession();
          return null;
        }
      }

      if (role == 'client') {
        final profileJson = prefs.getString(_keyClientProfile);
        if (profileJson == null || profileJson.isEmpty) return null;
        final profileMap = jsonDecode(profileJson) as Map<String, dynamic>;
        final profile = ClientProfile.fromMap(profileMap);
        if (profile.signupId.isEmpty) return null;
        return RestoredSession(role: 'client', profile: profile);
      }

      if (role == 'owner') {
        return const RestoredSession(role: 'owner');
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_keyRole),
      prefs.remove(_keyLoggedInAt),
      prefs.remove(_keyClientProfile),
    ]);
  }
}

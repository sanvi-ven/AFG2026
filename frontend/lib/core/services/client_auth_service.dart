import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/client_profile.dart';
import 'client_profile_service.dart';

class ClientAuthService {
  ClientAuthService._();

  static String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  static Future<ClientProfile> signUp({
    required String email,
    required String firstName,
    required String lastName,
    required String phoneNumber,
    required String address,
    required String password,
  }) async {
    final normalizedEmail = ClientProfileService.normalizeEmail(email);
    final passwordHash = _hashPassword(password);

    return await ClientProfileService.createSignup(
      email: normalizedEmail,
      firstName: firstName,
      lastName: lastName,
      phoneNumber: phoneNumber,
      address: address,
      passwordHash: passwordHash,
    );
  }

  static Future<ClientProfile> login({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = ClientProfileService.normalizeEmail(email);

    final profile = await ClientProfileService.fetchByEmail(normalizedEmail);
    if (profile == null) {
      throw Exception('No client account found for that email.');
    }

    final storedHash = await ClientProfileService.fetchPasswordHash(normalizedEmail);
    if (storedHash == null || storedHash.isEmpty) {
      throw Exception('Account has no password set. Please contact support.');
    }

    if (_hashPassword(password) != storedHash) {
      throw Exception('Incorrect email or password.');
    }

    return profile;
  }

  static Future<void> changePassword({
    required String email,
    required String oldPassword,
    required String newPassword,
  }) async {
    final normalizedEmail = ClientProfileService.normalizeEmail(email);

    final storedHash = await ClientProfileService.fetchPasswordHash(normalizedEmail);
    if (storedHash == null || storedHash.isEmpty) {
      throw Exception('Account has no password set.');
    }

    if (_hashPassword(oldPassword) != storedHash) {
      throw Exception('Current password is incorrect.');
    }

    await ClientProfileService.updatePasswordHash(
      email: normalizedEmail,
      passwordHash: _hashPassword(newPassword),
    );
  }
}

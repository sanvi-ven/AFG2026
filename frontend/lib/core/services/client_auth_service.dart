import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/client_profile.dart';
import 'client_profile_service.dart';

/// handles client autentication with local password hashing
/// supports signup, login, and password changing functionality
class ClientAuthService {
  ClientAuthService._();

  static String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  /// registers a new client account with email and password
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
/// authenticate client with email and password. throws exception if credentails dont match.
  
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
  /// turn an owner-created dummy client into a real login: validates the
  /// one-time claim code, then sets the real email and password on that
  /// same client record so existing estimates/invoices stay linked.
  static Future<ClientProfile> claimAccount({
    required String code,
    required String email,
    required String password,
  }) async {
    final profile = await ClientProfileService.fetchByClaimCode(code);
    if (profile == null) {
      throw Exception('That claim code is invalid or has already been used.');
    }

    final normalizedEmail = ClientProfileService.normalizeEmail(email);
    final existingByEmail = await ClientProfileService.fetchByEmail(normalizedEmail);
    if (existingByEmail != null && existingByEmail.signupId != profile.signupId) {
      throw Exception('An account with that email address already exists.');
    }

    await ClientProfileService.updateEmail(profile.signupId, normalizedEmail);
    await ClientProfileService.updatePasswordHash(
      email: normalizedEmail,
      passwordHash: _hashPassword(password),
    );
    await ClientProfileService.clearClaimCode(profile.signupId);

    final updated = await ClientProfileService.fetchBySignupId(profile.signupId);
    return updated ?? profile.copyWith(email: normalizedEmail, hasPassword: true);
  }

/// update client password after verifying the old password.

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

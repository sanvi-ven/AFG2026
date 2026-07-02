import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/employee_profile.dart';
import 'employee_profile_service.dart';
import 'invite_code_service.dart';

/// handles employee authentication with local password hashing
/// supports invite-code-gated signup, login, and password changing
class EmployeeAuthService {
  EmployeeAuthService._();

  static String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  /// registers a new employee account, gated by a valid owner-issued invite code
  static Future<EmployeeProfile> signUp({
    required String email,
    required String firstName,
    required String lastName,
    required String phoneNumber,
    required String password,
    required String inviteCode,
  }) async {
    final isValidCode = await InviteCodeService.validate(inviteCode);
    if (!isValidCode) {
      throw Exception('That invite code is invalid or no longer active.');
    }

    final normalizedEmail = EmployeeProfileService.normalizeEmail(email);
    final passwordHash = _hashPassword(password);

    return await EmployeeProfileService.createSignup(
      email: normalizedEmail,
      firstName: firstName,
      lastName: lastName,
      phoneNumber: phoneNumber,
      passwordHash: passwordHash,
    );
  }

  /// authenticate employee with email and password
  static Future<EmployeeProfile> login({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = EmployeeProfileService.normalizeEmail(email);

    final profile = await EmployeeProfileService.fetchByEmail(normalizedEmail);
    if (profile == null) {
      throw Exception('No employee account found for that email.');
    }
    if (!profile.active) {
      throw Exception('This account has been deactivated. Contact your employer.');
    }

    final storedHash = await EmployeeProfileService.fetchPasswordHash(normalizedEmail);
    if (storedHash == null || storedHash.isEmpty) {
      throw Exception('Account has no password set. Please contact your employer.');
    }

    if (_hashPassword(password) != storedHash) {
      throw Exception('Incorrect email or password.');
    }

    return profile;
  }

  /// update employee password after verifying the old password
  static Future<void> changePassword({
    required String email,
    required String oldPassword,
    required String newPassword,
  }) async {
    final normalizedEmail = EmployeeProfileService.normalizeEmail(email);

    final storedHash = await EmployeeProfileService.fetchPasswordHash(normalizedEmail);
    if (storedHash == null || storedHash.isEmpty) {
      throw Exception('Account has no password set.');
    }

    if (_hashPassword(oldPassword) != storedHash) {
      throw Exception('Current password is incorrect.');
    }

    await EmployeeProfileService.updatePasswordHash(
      email: normalizedEmail,
      passwordHash: _hashPassword(newPassword),
    );
  }
}

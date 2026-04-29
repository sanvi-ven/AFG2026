import 'package:firebase_auth/firebase_auth.dart';

import '../../models/client_profile.dart';
import 'client_profile_service.dart';

class ClientAuthService {
  ClientAuthService._();

  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Future<ClientProfile> signUp({
    required String email,
    required String firstName,
    required String lastName,
    required String phoneNumber,
    required String address,
    required String password,
  }) async {
    final normalizedEmail = ClientProfileService.normalizeEmail(email);

    try {
      await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );

      final existing = await ClientProfileService.fetchByEmail(normalizedEmail);
      if (existing != null) {
        return existing;
      }

      return await ClientProfileService.createSignup(
        email: normalizedEmail,
        firstName: firstName,
        lastName: lastName,
        phoneNumber: phoneNumber,
        address: address,
      );
    } on FirebaseAuthException catch (error) {
      throw Exception(_friendlyAuthMessage(error));
    } catch (error) {
      final currentUser = _auth.currentUser;
      if (currentUser != null && currentUser.email?.trim().toLowerCase() == normalizedEmail) {
        try {
          await currentUser.delete();
        } catch (_) {
          // Keep original error context.
        }
      }
      throw Exception(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  static Future<ClientProfile> login({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = ClientProfileService.normalizeEmail(email);

    try {
      await _auth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      final profile = await ClientProfileService.fetchByEmail(normalizedEmail);
      if (profile == null) {
        throw Exception('Client profile not found for this account.');
      }
      return profile;
    } on FirebaseAuthException catch (error) {
      throw Exception(_friendlyAuthMessage(error));
    }
  }

  static Future<void> changePassword({
    required String email,
    required String oldPassword,
    required String newPassword,
  }) async {
    final normalizedEmail = ClientProfileService.normalizeEmail(email);
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in to change password.');
    }
    if ((currentUser.email ?? '').trim().toLowerCase() != normalizedEmail) {
      throw Exception('Signed-in account does not match this profile.');
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: normalizedEmail,
        password: oldPassword,
      );
      await currentUser.reauthenticateWithCredential(credential);
      await currentUser.updatePassword(newPassword);
    } on FirebaseAuthException catch (error) {
      throw Exception(_friendlyAuthMessage(error));
    }
  }

  static String _friendlyAuthMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-email':
        return 'Email address is invalid.';
      case 'email-already-in-use':
        return 'An account with that email already exists.';
      case 'weak-password':
        return 'Password is too weak. Use at least 8 characters.';
      case 'user-not-found':
        return 'No client account found for that email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'requires-recent-login':
        return 'Please log in again, then retry changing your password.';
      case 'network-request-failed':
        return 'Network error. Check your internet connection and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      default:
        return error.message?.trim().isNotEmpty == true
            ? error.message!
            : 'Authentication failed (${error.code}).';
    }
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// manages firebase authentication and google sign-in with oauth token access
class FirebaseService {
  FirebaseService._();

  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static GoogleSignInAccount? _currentGoogleUser;
  static String? _currentAccessToken;

  /// initialize firebase with the default config and settings
  static Future<void> initialize() async {
    await Firebase.initializeApp();
  }

  /// sign in user with google account and calendar scopes, returns firebase credentials
  static Future<UserCredential> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..addScope('email')
        ..addScope('https://www.googleapis.com/auth/calendar');
      
      final userCredential = await _auth.signInWithPopup(provider);
      _currentGoogleUser = null;
      final oauthCredential = userCredential.credential as OAuthCredential?;
      _currentAccessToken = oauthCredential?.accessToken;
      return userCredential;
    }

    final googleSignIn = GoogleSignIn(
      scopes: [
        'email',
        'https://www.googleapis.com/auth/calendar',
      ],
    );
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception('Google sign-in canceled by user');
    }
    _currentGoogleUser = googleUser;
    final googleAuth = await googleUser.authentication;
    _currentAccessToken = googleAuth.accessToken;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return _auth.signInWithCredential(credential);
  }

  /// get the current google oauth access token for api calls
  static String? getAccessToken() => _currentAccessToken;

  /// get the currently authenticated firebase user
  static User? getCurrentUser() => _auth.currentUser;

  /// get a fresh id token for authenticated requests to the backend
  static Future<String?> getFreshIdToken() async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }
    return user.getIdToken(true);
  }

  /// get the current google account info including profile details
  static GoogleSignInAccount? getCurrentGoogleUser() => _currentGoogleUser;

  /// sign out the current user and clear all cached tokens and account info
  static Future<void> signOut() {
    _currentGoogleUser = null;
    _currentAccessToken = null;
    return _auth.signOut();
  }
}

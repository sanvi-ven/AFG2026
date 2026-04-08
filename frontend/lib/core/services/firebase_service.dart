import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class FirebaseService {
  FirebaseService._();

  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static GoogleSignInAccount? _currentGoogleUser;
  static String? _currentAccessToken;

  static Future<void> initialize() async {
    await Firebase.initializeApp();
  }

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

  static String? getAccessToken() => _currentAccessToken;

  static GoogleSignInAccount? getCurrentGoogleUser() => _currentGoogleUser;

  static Future<void> signOut() {
    _currentGoogleUser = null;
    _currentAccessToken = null;
    return _auth.signOut();
  }
}

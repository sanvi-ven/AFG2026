import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
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
    final googleSignIn = GoogleSignIn(
      clientId: '634538037073-dovfpggf7rrq402ifi86lbov2061nnrb.apps.googleusercontent.com',
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

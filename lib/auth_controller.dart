import 'package:firebase_auth/firebase_auth.dart' as firebase;  // Add prefix
import 'package:get/get.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';  // Import the UUID package

class AuthController extends GetxController {
  // Firebase authentication instance
  final firebase.FirebaseAuth _auth = firebase.FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  // Update the User type with the firebase prefix
  final Rx<firebase.User?> user = Rx<firebase.User?>(null);

  // Supabase client instance
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  void onInit() {
    super.onInit();
    user.bindStream(_auth.authStateChanges());
    ever(user, _initialScreen);
  }

  // Update parameter type with firebase prefix
  _initialScreen(firebase.User? user) {
    if (user == null) {
      Get.offAllNamed('/auth');
    } else {
      Get.offAllNamed('/home');
    }
  }

  Future<void> _createSupabaseProfile({
    required String userId,
    required String email,
    String? fullName,
    String? avatarUrl,
  }) async {
    // Create a UUID instance
    final uuid = Uuid();

    // Generate a new UUID v4 (random UUID)
    final profileId = uuid.v4();
    try {
      await _supabase.from('profiles').insert({
        'id':profileId,
        'email': email,
        'full_name': fullName,
        'avatar_url': avatarUrl,
        'created_at': DateTime.now().toIso8601String(),
        'firebase_uid': userId,
      });
    } catch (e) {
      print('Error creating Supabase profile: $e');
      await _auth.currentUser?.delete();
      throw 'Failed to complete signup process. Please try again.';
    }
  }

  Future<void> signUp(String email, String password, {String? fullName}) async {
    try {
      // Update the UserCredential type with firebase prefix
      final firebase.UserCredential userCredential =
      await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user != null) {
        await _createSupabaseProfile(
          userId: userCredential.user!.uid,
          email: email,
          fullName: fullName,
        );
      }
    } on firebase.FirebaseAuthException catch (e) {  // Update exception type
      String message;
      switch (e.code) {
        case 'weak-password':
          message = 'The password provided is too weak.';
          break;
        case 'email-already-in-use':
          message = 'An account already exists for that email.';
          break;
        case 'invalid-email':
          message = 'The email address is not valid.';
          break;
        default:
          message = e.message ?? 'An unknown error occurred.';
      }
      throw message;
    } catch (e) {
      throw 'Failed to complete signup: ${e.toString()}';
    }
  }

  Future<void> login(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on firebase.FirebaseAuthException catch (e) {  // Update exception type
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'No user found for that email.';
          break;
        case 'wrong-password':
          message = 'Wrong password provided.';
          break;
        case 'invalid-email':
          message = 'The email address is not valid.';
          break;
        case 'user-disabled':
          message = 'This user has been disabled.';
          break;
        default:
          message = e.message ?? 'An unknown error occurred.';
      }
      throw message;
    }
  }

  Future<firebase.UserCredential?> signInWithGoogle() async {  // Update return type
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
      await googleUser.authentication;
      final firebase.OAuthCredential credential =   // Update credential type
      firebase.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final firebase.UserCredential userCredential =   // Update type
      await _auth.signInWithCredential(credential);

      if (userCredential.additionalUserInfo?.isNewUser ?? false) {
        await _createSupabaseProfile(
          userId: userCredential.user!.uid,
          email: userCredential.user!.email!,
          fullName: userCredential.user!.displayName,
          avatarUrl: userCredential.user!.photoURL,
        );
      }

      return userCredential;
    } catch (e) {
      throw 'Failed to sign in with Google: ${e.toString()}';
    }
  }

  Future<void> logout() async {
    try {
      await _auth.signOut();
    } catch (e) {
      throw 'Error signing out. Try again.';
    }
  }
}
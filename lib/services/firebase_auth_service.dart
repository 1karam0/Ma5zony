import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

/// Wraps Firebase Auth and Firestore user-profile operations.
/// All auth state flows through [FirebaseAuth.authStateChanges].
class FirebaseAuthService {
  final fb.FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  FirebaseAuthService({
    fb.FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? fb.FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  // ── Streams ──────────────────────────────────────────────────────────────

  /// Emits the current Firebase user whenever auth state changes.
  Stream<fb.User?> get authStateChanges => _auth.authStateChanges();

  /// The currently signed-in Firebase user (null if signed out).
  fb.User? get currentUser => _auth.currentUser;

  // ── Sign In ──────────────────────────────────────────────────────────────

  Future<fb.User?> login(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return credential.user;
  }

  // ── Register ─────────────────────────────────────────────────────────────

  Future<fb.User?> register({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;

    if (user != null) {
      await user.updateDisplayName(name);

      // Write the user profile document to Firestore.
      await _firestore.collection('users').doc(user.uid).set({
        'name': name,
        'email': email.trim(),
        'role': role,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    return user;
  }

  // ── Password Reset ───────────────────────────────────────────────────────

  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  // ── Sign Out ─────────────────────────────────────────────────────────────

  Future<void> logout() async {
    await _auth.signOut();
  }

  // ── Firestore Profile Helpers ────────────────────────────────────────────

  /// Fetches the user profile document from `users/{uid}`.
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.data();
  }
}

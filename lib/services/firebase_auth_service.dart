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

  // ── Team Management (Owner features) ─────────────────────────────────────

  /// Fetch all Inventory Managers whose `ownerId` matches [ownerUid].
  Future<List<Map<String, dynamic>>> getTeamMembers(String ownerUid) async {
    final snap = await _firestore
        .collection('users')
        .where('ownerId', isEqualTo: ownerUid)
        .get();
    return snap.docs
        .map((doc) => {'uid': doc.id, ...doc.data()})
        .toList();
  }

  /// Invite an existing user (by email) to the owner's team.
  /// Returns a descriptive result string.
  Future<String> inviteTeamMember(String ownerUid, String email) async {
    // Find user by email
    final snap = await _firestore
        .collection('users')
        .where('email', isEqualTo: email.trim())
        .limit(1)
        .get();

    if (snap.docs.isEmpty) {
      return 'No account found with that email.';
    }

    final doc = snap.docs.first;
    final data = doc.data();

    if (data['role'] != 'Inventory Manager') {
      return 'Only Inventory Managers can be added to a team.';
    }
    if (data['ownerId'] != null && data['ownerId'] != ownerUid) {
      return 'This user already belongs to another team.';
    }
    if (data['ownerId'] == ownerUid) {
      return 'This user is already on your team.';
    }

    await _firestore.collection('users').doc(doc.id).update({
      'ownerId': ownerUid,
    });
    return 'success';
  }

  /// Remove a team member from the owner's team.
  Future<void> removeTeamMember(String memberUid) async {
    await _firestore.collection('users').doc(memberUid).update({
      'ownerId': FieldValue.delete(),
    });
  }
}

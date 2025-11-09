import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Simple authentication + user profile persistence in Firestore.
/// Creates a user document under `users/{uid}` upon registration, with:
/// { uid, name, first_name, last_name, email, role, createdAt }
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Registers a new user and creates the Firestore profile document.
  Future<UserCredential> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user!;

    final name = [
      firstName,
      lastName,
    ].where((e) => e.trim().isNotEmpty).join(' ').trim();
    await _db.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'name': name,
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
      'email': email.trim(),
      'role': 'users',
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return credential;
  }

  /// Signs in an existing user. Ensures a user document exists (backfill if missing).
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user!;
    final docRef = _db.collection('users').doc(user.uid);
    final snap = await docRef.get();
    if (!snap.exists) {
      await docRef.set({
        'uid': user.uid,
        'name': email.split('@').first,
        'email': email.trim(),
        'role': 'users',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    return credential;
  }

  Future<void> signOut() => _auth.signOut();

  User? get currentUser => _auth.currentUser;

  /// Fetches the Firestore user document as a Map or null.
  Future<Map<String, dynamic>?> fetchProfile() async {
    final uid = currentUser?.uid;
    if (uid == null) return null;
    final snap = await _db.collection('users').doc(uid).get();
    return snap.data();
  }
}

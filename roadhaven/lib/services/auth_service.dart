import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  Future<UserCredential> signUpWithEmailAndPhone({
    required String email,
    required String password,
    required String phone,
  }) async {
    final userCredential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = userCredential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'User could not be created.',
      );
    }

    final normalizedPhone = _normalizePhone(phone);
    await _db.collection('users').doc(user.uid).set({
      'email': email.trim(),
      'phone': normalizedPhone,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _db.collection('phoneIndex').doc(normalizedPhone).set({
      'uid': user.uid,
      'email': email.trim(),
    }, SetOptions(merge: true));

    return userCredential;
  }

  Future<UserCredential> signInWithEmailOrPhone({
    required String identifier,
    required String password,
  }) async {
    final trimmed = identifier.trim();
    if (trimmed.contains('@')) {
      return _auth.signInWithEmailAndPassword(
        email: trimmed,
        password: password,
      );
    }

    final normalizedPhone = _normalizePhone(trimmed);
    final phoneDoc = await _db.collection('phoneIndex').doc(normalizedPhone).get();
    if (!phoneDoc.exists) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No account found for this phone number.',
      );
    }

    final data = phoneDoc.data();
    final email = data?['email'] as String?;
    if (email == null || email.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'Email not found for this phone number.',
      );
    }

    return _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() => _auth.signOut();

  Future<UserCredential> signInWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) {
      throw FirebaseAuthException(
        code: 'aborted-by-user',
        message: 'Sign-in aborted.',
      );
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCred = await _auth.signInWithCredential(credential);

    // Upsert a basic profile entry for new users.
    final user = userCred.user;
    if (user != null) {
      await _db.collection('users').doc(user.uid).set(
        {
          'email': user.email,
          'displayName': user.displayName,
          'photoURL': user.photoURL,
          'provider': 'google',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    return userCred;
  }

  String _normalizePhone(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[\s\-()]+'), '');
    return cleaned;
  }
}

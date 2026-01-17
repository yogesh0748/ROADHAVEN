import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  String _normalizePhone(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[\s\-()]+'), '');
    return cleaned;
  }
}

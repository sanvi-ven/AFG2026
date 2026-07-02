import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/invite_code.dart';

/// manages owner-generated invite codes used for employee self-signup
class InviteCodeService {
  InviteCodeService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _collection =
      _firestore.collection('invite_codes');

  static Stream<List<InviteCode>> watchAll() {
    return _collection.snapshots().map((snapshot) {
      final codes = snapshot.docs
          .map((doc) => InviteCode.fromMap({...doc.data(), 'code': doc.id}))
          .toList();
      codes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return codes;
    });
  }

  /// owner action: generate a new reusable invite code
  static Future<void> generate(String code, {String label = ''}) async {
    final normalizedCode = code.trim().toUpperCase();
    if (normalizedCode.isEmpty) {
      throw Exception('Invite code cannot be empty.');
    }

    final doc = _collection.doc(normalizedCode);
    final existing = await doc.get();
    if (existing.exists) {
      throw Exception('That invite code already exists.');
    }

    await doc.set(
      InviteCode(code: normalizedCode, active: true, label: label.trim(), createdAt: DateTime.now()).toMap(),
    );
  }

  /// owner action: deactivate a code without deleting its history
  static Future<void> deactivate(String code) async {
    await _collection.doc(code.trim().toUpperCase()).set({'active': false}, SetOptions(merge: true));
  }

  /// employee signup-time check that a code exists and is active
  static Future<bool> validate(String code) async {
    final normalizedCode = code.trim().toUpperCase();
    if (normalizedCode.isEmpty) return false;

    final snapshot = await _collection.doc(normalizedCode).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return false;

    return data['active'] as bool? ?? false;
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/team.dart';

/// manages named crews ("teams") that employees and jobs are assigned to
class TeamService {
  TeamService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _collection =
      _firestore.collection('teams');

  static Stream<List<Team>> watchAllTeams() {
    return _collection.snapshots().map((snapshot) {
      final teams = snapshot.docs.map((doc) => Team.fromMap({...doc.data(), 'id': doc.id})).toList();
      teams.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return teams;
    });
  }

  static Future<String> createTeam(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Team name is required.');
    }

    final doc = _collection.doc();
    await doc.set(Team(id: doc.id, name: trimmedName, createdAt: DateTime.now()).toMap());
    return doc.id;
  }

  static Future<void> renameTeam(String teamId, String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Team name is required.');
    }
    await _collection.doc(teamId.trim()).set({'name': trimmedName}, SetOptions(merge: true));
  }
}

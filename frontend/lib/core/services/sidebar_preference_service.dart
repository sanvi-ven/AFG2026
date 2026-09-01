library;

import 'package:shared_preferences/shared_preferences.dart';

/// persists small owner-sidebar UI preferences (e.g. whether a given nav
/// group is expanded) — unrelated to auth, which is Firebase Auth's own concern.
class SidebarPreferenceService {
  SidebarPreferenceService._();

  static String _keyForGroup(String groupKey) =>
      'owner_sidebar_group_expanded_$groupKey';

  /// returns the stored preference for [groupKey], or null if never set
  /// (caller should fall back to a sensible default, e.g. based on the
  /// current route)
  static Future<bool?> getGroupExpanded(String groupKey) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyForGroup(groupKey);
    return prefs.containsKey(key) ? prefs.getBool(key) : null;
  }

  static Future<void> setGroupExpanded(String groupKey, bool expanded) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyForGroup(groupKey), expanded);
  }
}

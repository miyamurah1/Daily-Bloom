import 'package:shared_preferences/shared_preferences.dart';

/// Display-name memory shared by onboarding, the home greeting, and any
/// future personalization. Local-first: the name lives on the device —
/// the account's Firebase profile stays the sync business.
class ProfileName {
  static const key = 'bloom_profile_name_v1';

  /// Saved display name (empty when the user skipped personalization).
  static Future<String> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> write(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, name.trim());
    } catch (_) {}
  }

  /// Time-aware greeting for the app bar. An empty [name] yields just the
  /// part of day, so the caller can decide whether to personalize at all.
  static String greeting(String name, [DateTime? now]) {
    final n = now ?? DateTime.now();
    final part = n.hour < 12
        ? 'Good morning'
        : n.hour < 18
            ? 'Good afternoon'
            : 'Good evening';
    final who = name.trim();
    return who.isEmpty ? part : '$part, $who';
  }
}

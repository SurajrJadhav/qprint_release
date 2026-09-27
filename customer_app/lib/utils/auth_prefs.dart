import 'package:shared_preferences/shared_preferences.dart';

/// Cached greeting shown on dashboard (from login [display_name] or profile [full_name]).
const String kDisplayNameKey = 'display_name';
const String _legacyUsernameKey = 'username';

/// Reads [display_name], migrating a legacy [username] value once.
Future<String> readCachedDisplayName({String fallback = 'Customer'}) async {
  final prefs = await SharedPreferences.getInstance();
  var name = prefs.getString(kDisplayNameKey);
  if (name == null || name.trim().isEmpty) {
    final legacy = prefs.getString(_legacyUsernameKey);
    if (legacy != null && legacy.trim().isNotEmpty) {
      name = legacy.trim();
      await prefs.setString(kDisplayNameKey, name);
    }
    await prefs.remove(_legacyUsernameKey);
  }
  final trimmed = name?.trim();
  return (trimmed != null && trimmed.isNotEmpty) ? trimmed : fallback;
}

Future<void> writeCachedDisplayName(String name) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kDisplayNameKey, name.trim());
  await prefs.remove(_legacyUsernameKey);
}

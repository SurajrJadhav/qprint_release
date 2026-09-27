import 'package:shared_preferences/shared_preferences.dart';

/// Shop label shown in dashboard header (from [shop_name] / login [display_name]).
const String kShopNameKey = 'shop_name';
const String kDisplayNameKey = 'display_name';
const String _legacyUsernameKey = 'username';

Future<String> readCachedShopName({String fallback = 'My Shop'}) async {
  final prefs = await SharedPreferences.getInstance();
  var name = prefs.getString(kShopNameKey);
  if (name == null || name.trim().isEmpty) {
    name = prefs.getString(kDisplayNameKey);
  }
  if (name == null || name.trim().isEmpty) {
    final legacy = prefs.getString(_legacyUsernameKey);
    if (legacy != null && legacy.trim().isNotEmpty) {
      name = legacy.trim();
      await prefs.setString(kShopNameKey, name);
      await prefs.setString(kDisplayNameKey, name);
    }
    await prefs.remove(_legacyUsernameKey);
  }
  final trimmed = name?.trim();
  return (trimmed != null && trimmed.isNotEmpty) ? trimmed : fallback;
}

Future<void> writeCachedShopName(String name) async {
  final trimmed = name.trim();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kShopNameKey, trimmed);
  await prefs.setString(kDisplayNameKey, trimmed);
  await prefs.remove(_legacyUsernameKey);
}

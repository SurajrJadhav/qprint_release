/// Security checks: jailbreak/root detection.
///
/// Stub implementation (no native plugin) so the app passes Google Play's 16 KB
/// page-size requirement. flutter_jailbreak_detection ships libtoolChecker.so
/// which is not 16 KB aligned. Re-enable the plugin when it ships 16 KB–aligned
/// native libs and restore FlutterJailbreakDetection calls below.
class SecurityService {
  /// True if device appears rooted (Android) or jailbroken (iOS).
  /// Stub: always false until we use a 16 KB–compliant plugin.
  static Future<bool> get isJailbroken async => false;

  /// True if Android developer mode is on (easier to tamper).
  /// Stub: always false until we use a 16 KB–compliant plugin.
  static Future<bool> get isDeveloperMode async => false;

  /// True if device has elevated risk (jailbroken or developer mode).
  static Future<bool> get hasElevatedRisk async => false;
}

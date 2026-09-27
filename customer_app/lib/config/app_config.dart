import 'package:flutter/foundation.dart';

/// Build-time configuration from --dart-define or defaults.
/// Usage: flutter run --dart-define=BASE_URL=https://... --dart-define=MAPS_API_KEY=...
/// Or: flutter build apk --dart-define=BASE_URL=... --dart-define=MAPS_API_KEY=...
class AppConfig {
  /// Production backend URL (Render). Used for release builds when BASE_URL is not set or is localhost.
  static const String productionBaseUrl = 'https://qprint-72wr.onrender.com';

  static String? _baseUrl;
  static String? _mapsApiKey;
  static List<String>? _certPins;

  /// API base URL. In release: always uses [productionBaseUrl] (Render). In debug: from BASE_URL dart-define, or [productionBaseUrl].
  static String get baseUrl {
    _baseUrl ??= () {
      final v = _readDartDefine('BASE_URL');
      // Release builds must use Render; ignore localhost if passed by mistake
      if (kReleaseMode) {
        if (v.isEmpty || _isLocalhost(v)) return productionBaseUrl;
        return v;
      }
      return v.isNotEmpty ? v : productionBaseUrl;
    }();
    return _baseUrl!;
  }

  static bool _isLocalhost(String url) {
    final u = url.toLowerCase();
    return u.contains('localhost') || u.contains('127.0.0.1');
  }

  /// Google Maps API key. From MAPS_API_KEY dart-define, or null (uses Android manifest / iOS plist).
  static String? get mapsApiKey {
    final v = _readDartDefine('MAPS_API_KEY');
    _mapsApiKey ??= v.isEmpty ? null : v;
    return _mapsApiKey;
  }

  /// SHA-256 certificate fingerprints for leaf pinning (colon-separated).
  /// From CERT_PINS dart-define (comma-separated list), or empty.
  static List<String> get certificatePins {
    if (_certPins != null) return _certPins!;
    final define = _readDartDefine('CERT_PINS');
    if (define == null || define.isEmpty) {
      _certPins = [];
      return _certPins!;
    }
    _certPins = define.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    return _certPins!;
  }

  /// Google Sign-In Web/OAuth client ID (used as serverClientId so Android returns an idToken).
  /// From GOOGLE_SERVER_CLIENT_ID dart-define. Empty = Google button hidden.
  static String? get googleServerClientId {
    final v = _readDartDefine('GOOGLE_SERVER_CLIENT_ID');
    return v.isEmpty ? null : v;
  }

  /// Whether certificate pinning is enabled. Disabled in debug and in release by default so
  /// HTTPS to Render (Let's Encrypt / varying chains) works without pin mismatch. Re-enable
  /// with CERT_PINS or updated intermediates when you have a stable chain to pin.
  static bool get certificatePinningEnabled {
    if (kDebugMode) return false;
    // Disabled in release so Play Store build works with Render (cert chain may not match pinned intermediates)
    return certificatePins.isNotEmpty; // Only enable if CERT_PINS dart-define is set
  }

  /// Use intermediate CA pinning (Let's Encrypt E7, R12, YE1, YE2, YR1, YR2) instead of leaf fingerprints.
  /// True when CERT_PINS is not set; survives 90-day cert renewals.
  static bool get useIntermediatePinning {
    return certificatePins.isEmpty;
  }

}

/// Dart defines are read at compile time. For BASE_URL we need a different approach
/// because String.fromEnvironment requires the key to be passed at build time.
/// We use a workaround: check multiple keys.
String _readDartDefine(String key) {
  // String.fromEnvironment must have the key in the build invocation.
  // We use a switch on known keys to allow unused keys to be omitted.
  switch (key) {
    case 'BASE_URL':
      return const String.fromEnvironment('BASE_URL', defaultValue: '');
    case 'MAPS_API_KEY':
      return const String.fromEnvironment('MAPS_API_KEY', defaultValue: '');
    case 'CERT_PINS':
      return const String.fromEnvironment('CERT_PINS', defaultValue: '');
    case 'GOOGLE_SERVER_CLIENT_ID':
      return const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID', defaultValue: '');
    default:
      return '';
  }
}

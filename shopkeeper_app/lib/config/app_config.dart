import 'package:flutter/foundation.dart';

/// Build-time configuration from --dart-define or defaults.
/// Usage: flutter run --dart-define=BASE_URL=https://...
/// Or: flutter build windows --dart-define=BASE_URL=...
class AppConfig {
  /// Production backend URL (Render). Used when BASE_URL is not set or is localhost.
  static const String productionBaseUrl = 'https://qprint-72wr.onrender.com';

  static String? _baseUrl;

  /// API base URL. In release: defaults to [productionBaseUrl] (Render). In debug: from BASE_URL or production.
  static String get baseUrl {
    _baseUrl ??= () {
      final v = const String.fromEnvironment('BASE_URL', defaultValue: '');
      if (kReleaseMode && (v.isEmpty || _isLocalhost(v))) return productionBaseUrl;
      return v.isNotEmpty ? v : productionBaseUrl;
    }();
    return _baseUrl!;
  }

  static bool _isLocalhost(String url) {
    final u = url.toLowerCase();
    return u.contains('localhost') || u.contains('127.0.0.1');
  }

  /// Desktop/Installed Google OAuth client ID for browser loopback PKCE.
  /// From GOOGLE_DESKTOP_CLIENT_ID dart-define. Empty = Google button hidden.
  static String? get googleDesktopClientId {
    final v = const String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID', defaultValue: '');
    return v.isEmpty ? null : v;
  }

  /// Certificate pinning disabled by default so HTTPS to Render (Let's Encrypt) works without chain mismatch.
  /// Re-enable only if you pin a stable certificate chain.
  static bool get certificatePinningEnabled {
    if (kDebugMode) return false;
    return false;
  }
}

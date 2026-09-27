import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../config/app_config.dart';
import '../config/letsencrypt_certs.dart';

/// Creates an HTTP client. In release, uses certificate pinning.
/// - Intermediate CA pinning (default): trusts Let's Encrypt E7, R12, YE1, YE2, YR1, YR2, survives 90-day renewals.
/// - Leaf fingerprint pinning: when CERT_PINS is set.
http.Client createHttpClient() {
  if (!AppConfig.certificatePinningEnabled) {
    return http.Client();
  }

  if (AppConfig.useIntermediatePinning) {
    return _createIntermediatePinnedClient();
  }

  return _createFingerprintPinnedClient();
}

/// Uses Let's Encrypt intermediate certs (E7, R12, YE1, YE2, YR1, YR2) as trusted roots.
/// Survives leaf cert renewal every 90 days. Valid to 2027-2028.
http.Client _createIntermediatePinnedClient() {
  final context = SecurityContext(withTrustedRoots: false);
  final combinedPem = letsEncryptAllPems.map((p) => p.trim()).join('\n');

  try {
    context.setTrustedCertificatesBytes(combinedPem.codeUnits);
  } catch (e) {
    if (kDebugMode) debugPrint('Failed to add LetsEncrypt certs: $e');
  }

  final httpClient = HttpClient(context: context);
  return IOClient(httpClient);
}

/// Uses SHA-256 fingerprint pinning for leaf cert (legacy, requires updates on renewal).
http.Client _createFingerprintPinnedClient() {
  final pins = AppConfig.certificatePins;
  final context = SecurityContext(withTrustedRoots: false);

  final httpClient = HttpClient(context: context)
    ..badCertificateCallback = (X509Certificate cert, String host, int port) {
      final digest = sha256.convert(cert.der);
      final certFingerprint = _bytesToColonHex(digest.bytes);
      for (final pin in pins) {
        final normalizedPin = _formatFingerprint(pin);
        if (certFingerprint == normalizedPin) {
          if (kDebugMode) debugPrint('Cert pin OK for $host');
          return true;
        }
      }
      if (kDebugMode) debugPrint('Cert pin FAIL for $host: $certFingerprint');
      return false;
    };

  return IOClient(httpClient);
}

String _bytesToColonHex(List<int> bytes) {
  final buf = StringBuffer();
  for (var i = 0; i < bytes.length; i++) {
    if (i > 0) buf.write(':');
    buf.write(bytes[i].toRadixString(16).padLeft(2, '0').toLowerCase());
  }
  return buf.toString();
}

String _formatFingerprint(String s) {
  final clean = s.replaceAll(RegExp(r'[^a-fA-F0-9]'), '').toLowerCase();
  if (clean.length < 64) return clean;
  final buf = StringBuffer();
  for (var i = 0; i < 64 && i < clean.length; i += 2) {
    if (i > 0) buf.write(':');
    buf.write(clean.substring(i, i + 2));
  }
  return buf.toString();
}

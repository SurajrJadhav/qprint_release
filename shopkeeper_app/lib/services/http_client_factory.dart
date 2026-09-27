import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../config/app_config.dart';
import '../config/letsencrypt_certs.dart';

/// Creates an HTTP client. In release, uses certificate pinning (Let's Encrypt intermediates).
http.Client createHttpClient() {
  if (!AppConfig.certificatePinningEnabled) {
    return http.Client();
  }

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

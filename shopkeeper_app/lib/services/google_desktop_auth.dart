import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Browser-based Google Sign-In for Windows via OAuth loopback + PKCE.
/// Uses a Desktop/Installed OAuth client ID (no client secret).
class GoogleDesktopAuth {
  GoogleDesktopAuth({required this.clientId});

  final String clientId;

  static const _authEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const _scopes = 'openid email profile';

  /// Opens the system browser, completes OAuth, returns a Google ID token.
  Future<String> signIn({Duration timeout = const Duration(minutes: 3)}) async {
    if (clientId.isEmpty) {
      throw Exception('Google Sign-In is not configured for this build.');
    }

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    final redirectUri = 'http://127.0.0.1:$port';
    final state = _randomUrlSafe(32);
    final verifier = _randomUrlSafe(64);
    final challenge = _codeChallenge(verifier);

    final authUrl = Uri.parse(_authEndpoint).replace(queryParameters: {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': _scopes,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'state': state,
      'prompt': 'select_account',
    });

    final completer = Completer<String>();
    late StreamSubscription<HttpRequest> sub;

    Timer? timer;
    timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Google Sign-In timed out. Please try again.'));
      }
    });

    sub = server.listen((request) async {
      try {
        final uri = request.uri;
        if (uri.path != '/' && uri.path.isNotEmpty && uri.path != '/callback') {
          request.response
            ..statusCode = HttpStatus.notFound
            ..write('Not found')
            ..close();
          return;
        }

        final error = uri.queryParameters['error'];
        if (error != null) {
          await _writeHtml(
            request.response,
            title: 'Sign-in cancelled',
            body: 'You can close this window and return to Qprint Shop.',
          );
          if (!completer.isCompleted) {
            completer.completeError(Exception(
              error == 'access_denied'
                  ? 'Google Sign-In was cancelled.'
                  : 'Google Sign-In failed ($error).',
            ));
          }
          return;
        }

        final returnedState = uri.queryParameters['state'];
        final code = uri.queryParameters['code'];
        if (returnedState != state || code == null || code.isEmpty) {
          await _writeHtml(
            request.response,
            title: 'Invalid response',
            body: 'Please close this window and try again in the app.',
          );
          if (!completer.isCompleted) {
            completer.completeError(Exception('Invalid Google Sign-In response.'));
          }
          return;
        }

        await _writeHtml(
          request.response,
          title: 'Signed in',
          body: 'You can close this window and return to Qprint Shop.',
        );

        if (!completer.isCompleted) {
          completer.complete(code);
        }
      } catch (e) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      }
    });

    try {
      final launched = await launchUrl(authUrl, mode: LaunchMode.externalApplication);
      if (!launched) {
        throw Exception('Could not open the browser for Google Sign-In.');
      }

      final code = await completer.future;
      return await _exchangeCodeForIdToken(
        code: code,
        redirectUri: redirectUri,
        codeVerifier: verifier,
      );
    } finally {
      timer.cancel();
      await sub.cancel();
      await server.close(force: true);
    }
  }

  Future<String> _exchangeCodeForIdToken({
    required String code,
    required String redirectUri,
    required String codeVerifier,
  }) async {
    final response = await http.post(
      Uri.parse(_tokenEndpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': clientId,
        'code': code,
        'code_verifier': codeVerifier,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri,
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Google token exchange failed. Please try again.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final idToken = data['id_token'] as String?;
    if (idToken == null || idToken.isEmpty) {
      throw Exception('Google did not return an ID token.');
    }
    return idToken;
  }

  static String _randomUrlSafe(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  static String _codeChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  static Future<void> _writeHtml(
    HttpResponse response, {
    required String title,
    required String body,
  }) async {
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.html;
    response.write('''
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>$title</title>
<style>
  body{font-family:Segoe UI,sans-serif;background:#1e1b4b;color:#fff;display:flex;
  align-items:center;justify-content:center;min-height:100vh;margin:0}
  .card{background:rgba(255,255,255,.1);padding:2rem 2.5rem;border-radius:16px;text-align:center;
  border:1px solid rgba(255,255,255,.2);max-width:420px}
  h1{margin:0 0 .5rem;font-size:1.4rem} p{margin:0;opacity:.85}
</style></head>
<body><div class="card"><h1>$title</h1><p>$body</p></div></body></html>
''');
    await response.close();
  }
}

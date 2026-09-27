import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../utils/auth_prefs.dart';
import '../utils/file_integrity.dart';
import 'http_client_factory.dart';

class ApiService {
  static String get baseUrl => AppConfig.baseUrl;

  static final http.Client _httpClient = createHttpClient();

  static const String _secureTokenKey = 'qprint_auth_token';
  static const Duration _requestTimeout = Duration(seconds: 30);
  static const Duration _downloadTimeout = Duration(seconds: 120);

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // In-memory cache for current session only (never persisted to disk)
  static String? _cachedToken;

  Future<String?> login(String login, String password) async {
    try {
      final response = await _httpClient
          .post(
            Uri.parse('$baseUrl/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'login': login, 'password': password}),
          )
          .timeout(_requestTimeout, onTimeout: () {
            throw Exception('Connection timeout. Please check your network.');
          });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['token'];
        final role = data['role'];

        if (role != 'shopkeeper') {
          throw Exception('This app is for shopkeepers only. Please use the customer app.');
        }

        _cachedToken = token;

        // Prefer secure storage; fall back to SharedPreferences only in debug
        try {
          await _secureStorage.write(key: _secureTokenKey, value: token);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Secure storage write failed, using SharedPreferences: $e');
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('token', token);
            } catch (_) {}
          } else {
            throw Exception('Secure storage unavailable. Please try again or reinstall the app.');
          }
        }

        try {
          final prefs = await SharedPreferences.getInstance();
          await writeCachedShopName((data['display_name'] ?? login).toString());
          await prefs.setString('role', role);
        } catch (e) {
          if (kDebugMode) debugPrint('Warning: Failed to save shop name/role: $e');
        }

        return token;
      } else {
        throw Exception('Login failed. Please check your login and password.');
      }
    } catch (e) {
      if (e.toString().contains('shopkeepers only')) rethrow;
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection') ||
          e.toString().contains('TimeoutException')) {
        throw Exception('Connection problem. Please check your network and try again.');
      }
      rethrow;
    }
  }

  Future<void> registerSendOtp({required String email}) async {
    final body = <String, String>{'email': email.trim().toLowerCase()};
    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/register/send-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your network.');
        });
    if (response.statusCode != 200) {
      final bodyStr = response.body.trim();
      if (response.statusCode == 400 && bodyStr.isNotEmpty && bodyStr.length < 200) {
        throw Exception(bodyStr);
      }
      throw Exception('Could not send code. Please try again.');
    }
  }

  Future<Map<String, dynamic>> registerVerifyOtp({
    required String email,
    required String code,
  }) async {
    final body = <String, String>{
      'email': email.trim().toLowerCase(),
      'code': code.trim(),
    };
    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/register/verify-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your network.');
        });
    if (response.statusCode != 200) {
      final bodyStr = response.body.trim();
      if (response.statusCode == 400 && bodyStr.isNotEmpty && bodyStr.length < 200) {
        throw Exception(bodyStr);
      }
      throw Exception('Invalid or expired code. Please try again.');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> loginRequestOtp(String login) async {
    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/login/request-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'login': login.trim()}),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your network.');
        });
    if (response.statusCode != 200) {
      throw Exception(response.body.trim().isNotEmpty && response.body.length < 200
          ? response.body.trim()
          : 'Could not send code. Please try again.');
    }
  }

  /// Returns login result (token etc.) or needs_signup + signup_token + email.
  Future<Map<String, dynamic>> loginVerifyOtp(String login, String code) async {
    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/login/verify-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'login': login.trim(), 'code': code.trim()}),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your network.');
        });
    if (response.statusCode != 200) {
      throw Exception('Invalid or expired code. Please try again.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['needs_signup'] == true) {
      return data;
    }
    if (data['role'] != 'shopkeeper') {
      throw Exception('This app is for shopkeepers only.');
    }
    final token = data['token'];
    if (token != null) {
      _cachedToken = token;
      try {
        await _secureStorage.write(key: _secureTokenKey, value: token);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Secure storage write failed: $e');
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('token', token);
          } catch (_) {}
        } else {
          throw Exception('Secure storage unavailable. Please try again.');
        }
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        await writeCachedShopName((data['display_name'] ?? login).toString());
        await prefs.setString('role', data['role']);
      } catch (e) {
        if (kDebugMode) debugPrint('Warning: Failed to save shop name/role: $e');
      }
    }
    return data;
  }

  /// Sign in with Google ID token (browser OAuth on Windows). Shopkeeper only.
  Future<Map<String, dynamic>> loginWithGoogle(String idToken) async {
    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/login/google'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'id_token': idToken,
            'intent': 'shopkeeper',
          }),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your network.');
        });
    if (response.statusCode != 200) {
      final bodyStr = response.body.trim();
      if (bodyStr.isNotEmpty && bodyStr.length < 200) {
        throw Exception(bodyStr);
      }
      throw Exception('Google Sign-In failed. Please try again.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['needs_signup'] == true) {
      return data;
    }
    if (data['role'] != 'shopkeeper') {
      throw Exception('This app is for shopkeepers only. Please use the customer app.');
    }
    final token = data['token'];
    if (token == null) {
      throw Exception('Google Sign-In failed. Please try again.');
    }
    _cachedToken = token;
    try {
      await _secureStorage.write(key: _secureTokenKey, value: token);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Secure storage write failed: $e');
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', token);
        } catch (_) {}
      } else {
        throw Exception('Secure storage unavailable. Please try again.');
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await writeCachedShopName((data['display_name'] ?? 'Shop').toString());
      await prefs.setString('role', data['role']);
    } catch (e) {
      if (kDebugMode) debugPrint('Warning: Failed to save shop name/role: $e');
    }
    return data;
  }

  /// Register and return response. If backend returns token/role/display_name, they are persisted for auto-login.
  Future<Map<String, dynamic>?> register({
    required String fullName,
    required String email,
    required String phone,
    required String password,
    required String shopName,
    required String address,
    required double lat,
    required double long,
    required String signupToken,
  }) async {
    try {
      final response = await _httpClient
          .post(
            Uri.parse('$baseUrl/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'full_name': fullName,
              'email': email,
              'phone': phone,
              'password': password,
              'role': 'shopkeeper',
              'shop_name': shopName,
              'address': address,
              'lat': lat,
              'long': long,
              'signup_token': signupToken,
            }),
          )
          .timeout(_requestTimeout, onTimeout: () {
            throw Exception('Connection timeout. Please check your network.');
          });

      if (response.statusCode != 200 && response.statusCode != 201) {
        final body = response.body.trim();
        if ((response.statusCode == 400 || response.statusCode == 409) &&
            body.isNotEmpty &&
            (body.toLowerCase().contains('already in use') || body.toLowerCase().contains('verification'))) {
          throw Exception(body.length > 300 ? 'Registration failed.' : body);
        }
        throw Exception('Registration failed. Please check your details and try again.');
      }
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>?;
        final token = data?['token'];
        if (token != null) {
          _cachedToken = token;
          try {
            await _secureStorage.write(key: _secureTokenKey, value: token);
          } catch (e) {
            if (kDebugMode) {
              debugPrint('Secure storage write failed: $e');
              try {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('token', token);
              } catch (_) {}
            }
          }
          try {
            final prefs = await SharedPreferences.getInstance();
            await writeCachedShopName((data!['display_name'] ?? shopName).toString());
            await prefs.setString('role', data['role'] ?? 'shopkeeper');
          } catch (e) {
            if (kDebugMode) debugPrint('Warning: Failed to save shop name/role: $e');
          }
        }
        return data;
      } catch (_) {
        return null;
      }
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection') ||
          e.toString().contains('TimeoutException')) {
        throw Exception('Connection problem. Please check your network and try again.');
      }
      rethrow;
    }
  }

  Future<List<dynamic>> getQueue() async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await _httpClient
        .get(
          Uri.parse('$baseUrl/queue'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your network.');
        });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['queue'] ?? [];
    } else {
      throw Exception('Failed to fetch queue');
    }
  }

  Future<List<int>> downloadFile(int fileId) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await _httpClient
        .get(
          Uri.parse('$baseUrl/queue/download/$fileId'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(_downloadTimeout, onTimeout: () {
          throw Exception('Download timeout. Please try again.');
        });

    if (response.statusCode == 200) {
      final bytes = response.bodyBytes;
      final expectedHash = response.headers['x-content-sha256'] ?? response.headers['content-sha256'];
      if (!verifyFileIntegrity(bytes, expectedHash)) {
        throw Exception('File integrity check failed. Download may be corrupted.');
      }
      return bytes;
    } else {
      throw Exception('Failed to download file');
    }
  }

  Future<Map<String, dynamic>> getFileStatus(String code) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await _httpClient
        .get(
          Uri.parse('$baseUrl/file/$code/status'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your network.');
        });

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('File not found or invalid code');
    }
  }

  Future<List<int>> downloadPrivateFile(String code) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await _httpClient
        .get(
          Uri.parse('$baseUrl/file/$code'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(_downloadTimeout, onTimeout: () {
          throw Exception('Download timeout. Please try again.');
        });

    if (response.statusCode == 200) {
      final bytes = response.bodyBytes;
      final expectedHash = response.headers['x-content-sha256'] ?? response.headers['content-sha256'];
      if (!verifyFileIntegrity(bytes, expectedHash)) {
        throw Exception('File integrity check failed. Download may be corrupted.');
      }
      return bytes;
    } else {
      throw Exception('Failed to download file');
    }
  }

  Future<void> confirmPrivatePrint(String code) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/file/$code/confirm'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your network.');
        });

    if (response.statusCode != 200) {
      throw Exception('Failed to confirm print');
    }
  }

  /// Cancel a queue order (only when not yet printing). Customer is refunded and notified with reason.
  Future<void> cancelQueueOrder(int fileId, String reason) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/queue/$fileId/cancel'),
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: jsonEncode({'reason': reason}),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please try again.');
        });

    if (response.statusCode != 200) {
      final body = response.body;
      if (response.statusCode == 400 && body.isNotEmpty) {
        try {
          final m = jsonDecode(body) as Map<String, dynamic>;
          if (m['message'] != null) throw Exception(m['message'].toString());
        } catch (_) {}
      }
      throw Exception('Failed to cancel order');
    }
  }

  /// Call when shopkeeper taps Print for a queue file (disables customer withdraw).
  Future<void> printStartedQueue(int fileId) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');
    final response = await _httpClient.post(
      Uri.parse('$baseUrl/queue/$fileId/print-started'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(_requestTimeout, onTimeout: () {
      throw Exception('Connection timeout. Please check your network.');
    });
    if (response.statusCode != 200) {
      throw Exception('Failed to mark print started');
    }
  }

  /// Call when queue print fails or times out (re-enables customer withdraw).
  Future<void> printFailedQueue(int fileId) async {
    final token = await _getToken();
    if (token == null) return;
    try {
      await _httpClient.post(
        Uri.parse('$baseUrl/queue/$fileId/print-failed'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  /// Call when shopkeeper taps Print for a private/code print (disables customer withdraw).
  Future<void> printStartedPrivate(String code) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');
    final response = await _httpClient.post(
      Uri.parse('$baseUrl/file/$code/print-started'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(_requestTimeout, onTimeout: () {
      throw Exception('Connection timeout. Please check your network.');
    });
    if (response.statusCode != 200) {
      throw Exception('Failed to mark print started');
    }
  }

  /// Call when private print fails or times out (re-enables customer withdraw).
  Future<void> printFailedPrivate(String code) async {
    final token = await _getToken();
    if (token == null) return;
    try {
      await _httpClient.post(
        Uri.parse('$baseUrl/file/$code/print-failed'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  Future<void> confirmPrint(int fileId) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/queue/$fileId/confirm'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your network.');
        });

    if (response.statusCode != 200) {
      if (kDebugMode) {
        final body = response.body.length > 200 ? '${response.body.substring(0, 200)}...' : response.body;
        debugPrint('Confirm print failed: status=${response.statusCode} body=$body');
      }
      throw Exception('Failed to confirm print');
    }
  }

  Future<List<dynamic>> getOrderFiles(dynamic orderGroupId) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await _httpClient
        .get(
          Uri.parse('$baseUrl/queue/$orderGroupId/files'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your network.');
        });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['files'] ?? [];
    } else {
      throw Exception('Failed to fetch order files');
    }
  }

  Future<List<dynamic>> getHistory() async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await _httpClient
        .get(
          Uri.parse('$baseUrl/shop/history'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your network.');
        });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['history'] ?? [];
    } else {
      throw Exception('Failed to fetch history');
    }
  }

  /// Fetches payout list for the logged-in shopkeeper (settled and pending).
  Future<List<dynamic>> getPayouts() async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await _httpClient
        .get(
          Uri.parse('$baseUrl/shopkeeper/payouts'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your network.');
        });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['payouts'] ?? [];
    } else {
      throw Exception('Failed to fetch payouts');
    }
  }

  Future<Map<String, dynamic>> getProfile() async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await _httpClient
        .get(
          Uri.parse('$baseUrl/profile'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your network.');
        });

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch profile');
    }
  }

  Future<void> updateProfile({
    required String address,
    String? password,
    String? currentPassword,
    String? fullName,
    String? email,
    String? phone,
    String? shopName,
  }) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final body = <String, dynamic>{
      'address': address,
      if (fullName != null && fullName.isNotEmpty) 'full_name': fullName,
      if (email != null && email.isNotEmpty) 'email': email,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (shopName != null && shopName.isNotEmpty) 'shop_name': shopName,
      if (password != null && password.isNotEmpty) 'password': password,
      if (currentPassword != null && currentPassword.isNotEmpty) 'current_password': currentPassword,
    };

    final response = await _httpClient
        .put(
          Uri.parse('$baseUrl/profile'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your network.');
        });

    if (response.statusCode != 200) {
      final bodyStr = response.body;
      if (bodyStr.isNotEmpty && bodyStr.length < 500) {
        throw Exception(bodyStr);
      }
      throw Exception('Failed to update profile');
    }
    if (shopName != null && shopName.trim().isNotEmpty) {
      await writeCachedShopName(shopName.trim());
    }
  }

  /// Update shop pricing (B&W and color per page; optional double-sided factor). Send -1 to clear a value to platform default.
  Future<void> updateShopPricing({
    double? pricePerPageBw,
    double? pricePerPageColor,
    double? doubleSidedFactor,
  }) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final body = <String, dynamic>{};
    if (pricePerPageBw != null) body['price_per_page_bw'] = pricePerPageBw;
    if (pricePerPageColor != null) body['price_per_page_color'] = pricePerPageColor;
    if (doubleSidedFactor != null) body['double_sided_factor'] = doubleSidedFactor;

    if (body.isEmpty) throw Exception('Provide at least one pricing field');

    final response = await _httpClient
        .patch(
          Uri.parse('$baseUrl/shopkeeper/pricing'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your network.');
        });

    if (response.statusCode != 200) {
      final bodyStr = response.body;
      if (bodyStr.isNotEmpty && bodyStr.length < 500) {
        throw Exception(bodyStr);
      }
      throw Exception('Failed to update pricing');
    }
  }

  Future<void> toggleShopStatus(bool isOpen) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/shop/status'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'is_open': isOpen}),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your network.');
        });

    if (response.statusCode != 200) {
      throw Exception('Failed to update shop status');
    }
  }

  // Heartbeat: called periodically while the shopkeeper app is running.
  // Backend uses this to keep the shop marked OPEN and to auto-close on inactivity.
  Future<void> shopHeartbeat() async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/shop/heartbeat'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'X-Platform': 'windows',
          },
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your network.');
        });

    if (response.statusCode != 200) {
      throw Exception('Failed to send heartbeat');
    }
  }

  /// Returns the current auth token (for SSE stream, etc.). Null if not logged in.
  Future<String?> getToken() => _getToken();

  Future<String?> _getToken() async {
    if (_cachedToken != null) return _cachedToken;

    try {
      final token = await _secureStorage.read(key: _secureTokenKey);
      if (token != null) {
        _cachedToken = token;
        return token;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Secure storage read failed: $e');
    }

    // Fallback: token in SharedPreferences only in debug (avoid plaintext in production)
    if (kDebugMode) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('token');
        if (token != null) {
          _cachedToken = token;
          debugPrint('Using token from SharedPreferences fallback');
          return token;
        }
      } catch (_) {}
    }

    return null;
  }

  Future<void> logout() async {
    String? token;
    try {
      token = await _getToken();
      if (token != null) {
        await _httpClient
            .post(
              Uri.parse('$baseUrl/logout'),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(_requestTimeout, onTimeout: () => throw Exception('Timeout'));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Logout API call failed (clearing local anyway): $e');
    }

    _cachedToken = null;
    try {
      await _secureStorage.delete(key: _secureTokenKey);
    } catch (e) {
      if (kDebugMode) debugPrint('Secure storage delete failed: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      await prefs.remove(kShopNameKey);
      await prefs.remove(kDisplayNameKey);
      await prefs.remove('username');
      await prefs.remove('role');
    } catch (e) {
      if (kDebugMode) debugPrint('Preferences clear failed: $e');
    }
  }

  Future<void> forgotPassword(String email) async {
    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/forgot-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email}),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your network.');
        });

    if (response.statusCode != 200) {
      throw Exception('Could not send reset email. Please check the email address and try again.');
    }
  }

  Future<void> resetPassword(String token, String password) async {
    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/reset-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'token': token,
            'password': password,
          }),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your network.');
        });

    if (response.statusCode != 200) {
      throw Exception('Could not reset password. Please check the link and try again.');
    }
  }

  // Delete account: requires password confirmation
  Future<void> deleteAccount(String password) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await _httpClient
        .delete(
          Uri.parse('$baseUrl/profile'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'password': password}),
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      final body = response.body;
      if (body.contains('Invalid password')) {
        throw Exception('Invalid password');
      }
      throw Exception(body.isNotEmpty ? body : 'Failed to delete account');
    }

    // Clear local data after successful deletion
    _cachedToken = null;
    try {
      await _secureStorage.delete(key: _secureTokenKey);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}
  }
}

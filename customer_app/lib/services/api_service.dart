import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../utils/auth_prefs.dart';
import '../utils/referral_sanitizer.dart';
import 'http_client_factory.dart';

class ApiService {
  static String get baseUrl => AppConfig.baseUrl;

  static final http.Client _httpClient = createHttpClient();

  static const String _secureTokenKey = 'qprint_auth_token';
  static const Duration _requestTimeout = Duration(seconds: 30);
  static const Duration _uploadTimeout = Duration(seconds: 120);

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // In-memory cache for current session only (never persisted to disk)
  static String? _cachedToken;

  /// Call after reading token from storage (e.g. in AuthWrapper) so validateToken and
  /// subsequent API calls use it without a second secure-storage read. Reduces failures
  /// on Play Store builds where secure storage can be flaky.
  static void setCachedToken(String? token) {
    _cachedToken = token;
  }

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

    // Fallback: token in SharedPreferences (migration from old installs)
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token != null) {
        _cachedToken = token;
        // Migrate to secure storage
        try {
          await _secureStorage.write(key: _secureTokenKey, value: token);
          await prefs.remove('token');
        } catch (_) {}
        return token;
      }
    } catch (_) {}

    return null;
  }

  Future<Map<String, String>> _getHeaders({bool includeAuth = true}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (includeAuth) {
      final token = await _getToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  // Authentication — login accepts email or mobile (phone)
  Future<Map<String, dynamic>> login(String login, String password) async {
    try {
      final response = await _httpClient
          .post(
            Uri.parse('$baseUrl/login'),
            headers: await _getHeaders(includeAuth: false),
            body: jsonEncode({
              'login': login,
              'password': password,
            }),
          )
          .timeout(_requestTimeout, onTimeout: () {
            throw Exception('Connection timeout. Please check your internet connection.');
          });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['token'];
        final role = data['role'];

        if (role != 'customer') {
          throw Exception('This app is for customers only. Please use the web or shopkeeper app.');
        }

        _cachedToken = token;

        // Token only in secure storage (never in SharedPreferences)
        try {
          await _secureStorage.write(key: _secureTokenKey, value: token);
        } catch (e) {
          if (kDebugMode) debugPrint('Secure storage write failed: $e');
          // Session remains valid in memory; user may need to log in again after app restart
        }

        try {
          final prefs = await SharedPreferences.getInstance();
          await writeCachedDisplayName((data['display_name'] ?? login).toString());
          await prefs.setString('role', role);
        } catch (e) {
          if (kDebugMode) debugPrint('Warning: Failed to save display_name/role: $e');
        }

        return data;
      } else {
        if (response.statusCode == 401) {
          throw Exception('Invalid login or password');
        } else if (response.statusCode == 404) {
          throw Exception('Server not found. Please check your connection');
        } else {
          throw Exception('Login failed. Please try again.');
        }
      }
    } on Exception catch (e) {
      if (e.toString().contains('customers only')) rethrow;
      if (e.toString().contains('Connection timeout')) rethrow;
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection') ||
          e.toString().contains('TimeoutException')) {
        throw Exception('Connection problem. Please check your network and try again.');
      }
      rethrow;
    }
  }

  /// Sends a 6-digit OTP to email for sign-up (email only).
  Future<void> registerSendOtp({required String email}) async {
    final body = <String, String>{'email': email.trim().toLowerCase()};
    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/register/send-otp'),
          headers: await _getHeaders(includeAuth: false),
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your internet connection.');
        });
    if (response.statusCode != 200) {
      final bodyStr = response.body.trim();
      if (response.statusCode == 400 && bodyStr.isNotEmpty) {
        throw Exception(bodyStr.length > 200 ? 'Invalid request.' : bodyStr);
      }
      throw Exception('Could not send code. Please try again.');
    }
  }

  /// Verifies OTP and returns signup token and verified email (email only).
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
          headers: await _getHeaders(includeAuth: false),
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your internet connection.');
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

  /// Request OTP for login (email only).
  Future<void> loginRequestOtp(String login) async {
    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/login/request-otp'),
          headers: await _getHeaders(includeAuth: false),
          body: jsonEncode({'login': login.trim()}),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your internet connection.');
        });
    if (response.statusCode != 200) {
      throw Exception(response.body.trim().isNotEmpty && response.body.length < 200
          ? response.body.trim()
          : 'Could not send code. Please try again.');
    }
  }

  /// Verify OTP and return token/role/display_name (login) or needs_signup + signup_token + email (create account).
  Future<Map<String, dynamic>> loginVerifyOtp(String login, String code) async {
    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/login/verify-otp'),
          headers: await _getHeaders(includeAuth: false),
          body: jsonEncode({'login': login.trim(), 'code': code.trim()}),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your internet connection.');
        });
    if (response.statusCode != 200) {
      throw Exception('Invalid or expired code. Please try again.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['needs_signup'] == true) {
      return data;
    }
    if (data['role'] != 'customer') {
      throw Exception('This app is for customers only.');
    }
    final token = data['token'];
    if (token != null) {
      _cachedToken = token;
      try {
        await _secureStorage.write(key: _secureTokenKey, value: token);
      } catch (e) {
        if (kDebugMode) debugPrint('Secure storage write failed: $e');
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        await writeCachedDisplayName((data['display_name'] ?? login).toString());
        await prefs.setString('role', data['role']);
      } catch (e) {
        if (kDebugMode) debugPrint('Warning: Failed to save display_name/role: $e');
      }
    }
    return data;
  }

  /// Sign in with Google ID token. Creates a customer account if none exists.
  Future<Map<String, dynamic>> loginWithGoogle(String idToken) async {
    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/login/google'),
          headers: await _getHeaders(includeAuth: false),
          body: jsonEncode({
            'id_token': idToken,
            'intent': 'customer',
          }),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your internet connection.');
        });
    if (response.statusCode != 200) {
      final bodyStr = response.body.trim();
      if (bodyStr.isNotEmpty && bodyStr.length < 200) {
        throw Exception(bodyStr);
      }
      throw Exception('Google Sign-In failed. Please try again.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['role'] != 'customer') {
      throw Exception('This app is for customers only.');
    }
    final token = data['token'];
    if (token == null) {
      throw Exception('Google Sign-In failed. Please try again.');
    }
    _cachedToken = token;
    try {
      await _secureStorage.write(key: _secureTokenKey, value: token);
    } catch (e) {
      if (kDebugMode) debugPrint('Secure storage write failed: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await writeCachedDisplayName((data['display_name'] ?? 'User').toString());
      await prefs.setString('role', data['role']);
    } catch (e) {
      if (kDebugMode) debugPrint('Warning: Failed to save display_name/role: $e');
    }
    return data;
  }

  /// Register and return response. If backend returns token/role/display_name, they are persisted and returned for auto-login.
  Future<Map<String, dynamic>?> register({
    required String fullName,
    required String email,
    required String phone,
    required String password,
    String? referralCode,
    required String signupToken,
  }) async {
    final body = <String, dynamic>{
      'full_name': fullName,
      'email': email,
      'phone': phone,
      'password': password,
      'role': 'customer',
      'signup_token': signupToken,
    };
    final safeRef = sanitizeReferralCode(referralCode);
    if (safeRef != null) {
      body['referral_code'] = safeRef;
    }
    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/register'),
          headers: await _getHeaders(includeAuth: false),
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your internet connection.');
        });

    if (response.statusCode != 200 && response.statusCode != 201) {
      final respBody = response.body.trim();
      if ((response.statusCode == 400 || response.statusCode == 409) &&
          respBody.isNotEmpty &&
          (respBody.toLowerCase().contains('already exists') ||
              respBody.toLowerCase().contains('already in use') ||
              respBody.toLowerCase().contains('verification'))) {
        throw Exception(respBody.length > 300 ? 'Registration failed.' : respBody);
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
          if (kDebugMode) debugPrint('Secure storage write failed: $e');
        }
        try {
          final prefs = await SharedPreferences.getInstance();
          await writeCachedDisplayName((data!['display_name'] ?? fullName).toString());
          await prefs.setString('role', data['role'] ?? 'customer');
        } catch (e) {
          if (kDebugMode) debugPrint('Warning: Failed to save display_name/role: $e');
        }
      }
      return data;
    } catch (_) {
      return null;
    }
  }

  // Get nearest shops
  Future<List<dynamic>> getShops(double lat, double long) async {
    final response = await _httpClient
        .get(
          Uri.parse('$baseUrl/shops?lat=$lat&long=$long'),
          headers: await _getHeaders(),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your internet connection.');
        });

    if (response.statusCode == 200) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is List) return decoded;
        return [];
      } catch (_) {
        if (kDebugMode) debugPrint('getShops: invalid JSON');
        return [];
      }
    }
    if (response.statusCode == 401) {
      await _clearLocalAuth();
      throw Exception('Session expired. Please log in again.');
    }
    throw Exception('Failed to load shops');
  }

  /// Fetches a single shop by id (e.g. after scanning shop QR). Returns shop map or throws.
  Future<Map<String, dynamic>> getShopById(int shopId) async {
    final response = await _httpClient
        .get(
          Uri.parse('$baseUrl/shops/$shopId'),
          headers: await _getHeaders(),
        )
        .timeout(_requestTimeout, onTimeout: () {
      throw Exception('Connection timeout. Please check your internet connection.');
    });
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw Exception('Invalid response from server');
    }
    if (response.statusCode == 401) {
      await _clearLocalAuth();
      throw Exception('Session expired. Please log in again.');
    }
    if (response.statusCode == 404) {
      throw Exception('Shop not found');
    }
    throw Exception('Failed to load shop');
  }

  // Calculate cost before payment (supports multiple files). Pass shopId for queue to use shop pricing.
  Future<Map<String, dynamic>> calculateCost({
    required List<String> filePaths,
    required int copies,
    required String printMode,
    required String colorMode,
    required String paperSize,
    int? shopId,
  }) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/calculate-cost'),
    );

    request.headers['Authorization'] = 'Bearer $token';

    for (final filePath in filePaths) {
      request.files.add(await http.MultipartFile.fromPath('files[]', filePath));
    }

    request.fields['copies'] = copies.toString();
    request.fields['print_mode'] = printMode;
    request.fields['color_mode'] = colorMode;
    request.fields['paper_size'] = paperSize;
    if (shopId != null && shopId > 0) {
      request.fields['shop_id'] = shopId.toString();
    }

    final streamedResponse = await request.send().timeout(_uploadTimeout, onTimeout: () {
      throw Exception('Request timeout. Please try again.');
    });
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    // Pass through 400 body so client can show which file failed (e.g. page count not available)
    final body = response.body.trim();
    if (response.statusCode == 400 && body.isNotEmpty && body.length < 400) {
      throw Exception(body);
    }
    throw Exception('Failed to calculate cost. Please try again.');
  }

  /// Cost only from total page count (no file upload). Use when shop or print type
  /// changes and client already has page counts from a previous calculateCost.
  Future<Map<String, dynamic>> calculateCostFromPages({
    required int totalPages,
    required int copies,
    required String printMode,
    required String colorMode,
    int? shopId,
  }) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final body = <String, dynamic>{
      'total_pages': totalPages,
      'copies': copies,
      'print_mode': printMode,
      'color_mode': colorMode,
      if (shopId != null && shopId > 0) 'shop_id': shopId,
    };

    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/calculate-cost-from-pages'),
          headers: await _getHeaders(),
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to calculate cost. Please try again.');
    }
  }

  // Create payment order (supports use_wallet and wallet_amount for wallet/hybrid)
  Future<Map<String, dynamic>> createPaymentOrder({
    required double amount,
    required int copies,
    required String printMode,
    required String colorMode,
    required String paperSize,
    required String printType,
    int? shopkeeperId,
    String? comment,
    bool useWallet = false,
    double? walletAmount,
  }) async {
    final body = <String, dynamic>{
      'amount': amount,
      'copies': copies,
      'print_mode': printMode,
      'color_mode': colorMode,
      'paper_size': paperSize,
      'print_type': printType,
      if (shopkeeperId != null) 'shopkeeper_id': shopkeeperId,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
      'use_wallet': useWallet,
      if (walletAmount != null && walletAmount > 0) 'wallet_amount': walletAmount,
    };
    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/create-payment-order'),
          headers: await _getHeaders(),
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your internet connection.');
        });

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      final data = jsonDecode(response.body);
      final msg = data is Map && data['error'] != null ? data['error'].toString() : null;
      throw Exception(msg ?? 'Failed to create payment order. Please try again.');
    }
  }

  // Wallet balance
  Future<double> getWalletBalance() async {
    final response = await _httpClient
        .get(Uri.parse('$baseUrl/wallet/balance'), headers: await _getHeaders())
        .timeout(_requestTimeout, onTimeout: () {
      throw Exception('Connection timeout.');
    });
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['balance'] as num?)?.toDouble() ?? 0.0;
    }
    throw Exception('Failed to load wallet balance.');
  }

  // Wallet transactions (paginated)
  Future<Map<String, dynamic>> getWalletTransactions({int limit = 50, int offset = 0}) async {
    final uri = Uri.parse('$baseUrl/wallet/transactions').replace(
      queryParameters: {'limit': limit.toString(), 'offset': offset.toString()},
    );
    final response = await _httpClient
        .get(uri, headers: await _getHeaders())
        .timeout(_requestTimeout, onTimeout: () {
      throw Exception('Connection timeout.');
    });
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load transactions.');
  }

  // Top-up wallet: creates Razorpay order; returns order_id, key_id, amount for checkout
  Future<Map<String, dynamic>> topupWallet(double amount) async {
    if (amount < 10 || amount > 10000) {
      throw Exception('Amount must be between ₹10 and ₹10,000');
    }
    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/wallet/topup'),
          headers: await _getHeaders(),
          body: jsonEncode({'amount': amount}),
        )
        .timeout(_requestTimeout, onTimeout: () {
      throw Exception('Connection timeout.');
    });
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    }
    final data = jsonDecode(response.body);
    final msg = data is Map && data['error'] != null ? data['error'].toString() : null;
    throw Exception(msg ?? 'Failed to create top-up order.');
  }

  // Check payment status
  Future<Map<String, dynamic>> getPaymentStatus(String orderId) async {
    final response = await _httpClient
        .get(
          Uri.parse('$baseUrl/payment-order/$orderId/status'),
          headers: await _getHeaders(),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your internet connection.');
        });

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get payment status');
    }
  }

  // Upload file(s) - supports multiple files
  Future<Map<String, dynamic>> uploadFile({
    required List<String> filePaths,
    required int copies,
    required String printMode,
    required String colorMode,
    required String paperSize,
    required String printType,
    int? shopId,
    String? comment,
    int? paymentOrderId,
  }) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/upload'),
    );

    request.headers['Authorization'] = 'Bearer $token';

    for (final filePath in filePaths) {
      request.files.add(await http.MultipartFile.fromPath('files[]', filePath));
    }

    request.fields['copies'] = copies.toString();
    request.fields['print_mode'] = printMode;
    request.fields['color_mode'] = colorMode;
    request.fields['paper_size'] = paperSize;
    request.fields['print_type'] = printType;

    if (paymentOrderId != null) {
      request.fields['payment_order_id'] = paymentOrderId.toString();
    }
    if (shopId != null) {
      request.fields['shop_id'] = shopId.toString();
    }
    if (comment != null && comment.isNotEmpty) {
      request.fields['comment'] = comment;
    }

    final streamedResponse = await request.send().timeout(_uploadTimeout, onTimeout: () {
      throw Exception('Upload timeout. Please try again.');
    });
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      String msg = 'Failed to upload files. Please try again.';
      try {
        final body = response.body.trim();
        if (body.startsWith('{')) {
          final data = jsonDecode(body) as Map<String, dynamic>?;
          final err = data?['error']?.toString();
          if (err != null && err.isNotEmpty) msg = err;
        } else if (body.isNotEmpty && body.length < 500) {
          msg = body;
        }
      } catch (_) {}
      throw Exception(msg);
    }
  }

  // Get my orders (grouped by batch - same view as shopkeeper)
  Future<List<dynamic>> getMyOrders() async {
    final response = await _httpClient
        .get(
          Uri.parse('$baseUrl/my-orders'),
          headers: await _getHeaders(),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your internet connection.');
        });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is Map && data.containsKey('orders')) {
        return data['orders'] as List;
      }
      return [];
    } else {
      throw Exception('Failed to load orders');
    }
  }

  // Get my files (legacy - flat list)
  Future<List<dynamic>> getMyFiles() async {
    final response = await _httpClient
        .get(
          Uri.parse('$baseUrl/my-files'),
          headers: await _getHeaders(),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your internet connection.');
        });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is List) {
        return data;
      } else if (data is Map && data.containsKey('files')) {
        return data['files'] as List;
      } else if (data is Map && data.containsKey('data')) {
        return data['data'] as List;
      } else {
        return [];
      }
    } else {
      throw Exception('Failed to load files');
    }
  }

  // Check file status
  Future<Map<String, dynamic>> checkFileStatus(int fileId) async {
    final response = await _httpClient
        .get(
          Uri.parse('$baseUrl/files/$fileId/status'),
          headers: await _getHeaders(),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your internet connection.');
        });

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to check file status');
    }
  }

  // Withdraw print
  Future<void> withdrawPrint(int fileId) async {
    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/withdraw/$fileId'),
          headers: await _getHeaders(),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your internet connection.');
        });

    if (response.statusCode != 200) {
      final body = response.body.trim();
      if (response.statusCode == 409 && body.isNotEmpty && body.length < 200) {
        throw Exception(body);
      }
      throw Exception('Failed to withdraw print');
    }
  }

  // Password Recovery
  Future<void> forgotPassword(String email) async {
    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/forgot-password'),
          headers: await _getHeaders(includeAuth: false),
          body: jsonEncode({'email': email}),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your internet connection.');
        });

    if (response.statusCode != 200) {
      throw Exception('Could not send reset email. Please check the email address and try again.');
    }
  }

  Future<void> resetPassword(String token, String password) async {
    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/reset-password'),
          headers: await _getHeaders(includeAuth: false),
          body: jsonEncode({
            'token': token,
            'password': password,
          }),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your internet connection.');
        });

    if (response.statusCode != 200) {
      throw Exception('Could not reset password. Please check the link and try again.');
    }
  }

  /// Clears token and auth data from memory and storage (used on 401 or logout).
  Future<void> _clearLocalAuth() async {
    _cachedToken = null;
    try {
      await _secureStorage.delete(key: _secureTokenKey);
    } catch (e) {
      if (kDebugMode) debugPrint('Secure storage delete failed: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      await prefs.remove(kDisplayNameKey);
      await prefs.remove('username');
      await prefs.remove('role');
    } catch (e) {
      if (kDebugMode) debugPrint('Preferences clear failed: $e');
    }
  }

  /// Returns true if the stored token is still valid (server returns 200).
  /// On 401, clears local auth and returns false so app can show login.
  Future<bool> validateToken() async {
    final token = await _getToken();
    if (token == null) return false;
    try {
      final response = await _httpClient
          .get(
            Uri.parse('$baseUrl/profile'),
            headers: await _getHeaders(),
          )
          .timeout(const Duration(seconds: 10), onTimeout: () {
            throw Exception('Timeout');
          });
      if (response.statusCode == 200) return true;
      if (response.statusCode == 401) {
        await _clearLocalAuth();
        return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Registers the device FCM token with the backend for push notifications (customer app).
  Future<void> registerFcmToken(String fcmToken, String platform) async {
    final token = await _getToken();
    if (token == null || fcmToken.isEmpty) return;
    try {
      await _httpClient
          .post(
            Uri.parse('$baseUrl/notifications/register-token'),
            headers: await _getHeaders(),
            body: jsonEncode({
              'fcm_token': fcmToken,
              'platform': platform.isEmpty ? 'android' : platform,
            }),
          )
          .timeout(const Duration(seconds: 10), onTimeout: () {
            throw Exception('Timeout');
          });
    } catch (e) {
      if (kDebugMode) debugPrint('registerFcmToken: $e');
    }
  }

  // Referral summary (total referred, credited, earnings, pending)
  Future<Map<String, dynamic>> getReferralSummary() async {
    final response = await _httpClient
        .get(
          Uri.parse('$baseUrl/referral/summary'),
          headers: await _getHeaders(),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout.');
        });
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    if (response.statusCode == 401) throw Exception('Session expired. Please log in again.');
    throw Exception('Failed to load referral summary.');
  }

  // Referral history (list of referred users, status, amount, dates)
  Future<Map<String, dynamic>> getReferralHistory({int limit = 50, int offset = 0}) async {
    final uri = Uri.parse('$baseUrl/referral/history').replace(
      queryParameters: {'limit': limit.toString(), 'offset': offset.toString()},
    );
    final response = await _httpClient
        .get(uri, headers: await _getHeaders())
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout.');
        });
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    if (response.statusCode == 401) throw Exception('Session expired. Please log in again.');
    throw Exception('Failed to load referral history.');
  }

  // Invite by email (sends invite with referral link via backend/Resend). Customer only.
  Future<void> inviteByEmail(String email) async {
    final trimmed = email.trim().toLowerCase();
    if (trimmed.isEmpty) throw Exception('Please enter an email address.');
    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/referral/invite'),
          headers: await _getHeaders(),
          body: jsonEncode({'email': trimmed}),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout.');
        });
    if (response.statusCode == 200) return;
    if (response.statusCode == 401) throw Exception('Session expired. Please log in again.');
    if (response.statusCode == 429) throw Exception('Daily invite limit reached. Try again tomorrow.');
    if (response.statusCode == 400) throw Exception('Invalid email address.');
    final body = jsonDecode(response.body);
    final msg = body is Map && body['message'] != null ? body['message'].toString() : 'Failed to send invite.';
    throw Exception(msg);
  }

  // Get profile
  Future<Map<String, dynamic>> getProfile() async {
    final response = await _httpClient
        .get(
          Uri.parse('$baseUrl/profile'),
          headers: await _getHeaders(),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your internet connection.');
        });

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    if (response.statusCode == 401) {
      await _clearLocalAuth();
      throw Exception('Session expired. Please log in again.');
    }
    throw Exception('Failed to load profile');
  }

  // Update profile
  Future<void> updateProfile({
    required String fullName,
    String? email,
    String? phone,
    String? password,
    String? currentPassword,
    required String address,
  }) async {
    final body = <String, dynamic>{
      'full_name': fullName,
      'address': address,
      if (email != null && email.isNotEmpty) 'email': email,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (password != null && password.isNotEmpty) 'password': password,
      if (currentPassword != null && currentPassword.isNotEmpty) 'current_password': currentPassword,
    };

    final response = await _httpClient
        .put(
          Uri.parse('$baseUrl/profile'),
          headers: await _getHeaders(),
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout, onTimeout: () {
          throw Exception('Connection timeout. Please check your internet connection.');
        });

    if (response.statusCode != 200) {
      throw Exception('Failed to update profile');
    }

    await writeCachedDisplayName(fullName);
  }

  // Logout: notify server then clear local state
  Future<void> logout() async {
    try {
      final token = await _getToken();
      if (token != null) {
        await _httpClient
            .post(
              Uri.parse('$baseUrl/logout'),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(const Duration(seconds: 5), onTimeout: () {
              throw Exception('Logout request timed out');
            });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Logout API call failed (clearing local anyway): $e');
    }
    await _clearLocalAuth();
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
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      final body = response.body.trim().toLowerCase();
      if (body.contains('invalid password')) {
        throw Exception('Invalid password');
      }
      // Never expose raw response body to UI (security)
      throw Exception('Failed to delete account. Please try again.');
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

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'https://qprint-72wr.onrender.com';
  // For local testing: 'http://localhost:8080'

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
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

  // Authentication
  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: await _getHeaders(includeAuth: false),
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      // Store token
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', data['token']);
      await prefs.setString('username', data['username']);
      await prefs.setString('role', data['role']);
      return data;
    } else {
      throw Exception(response.body);
    }
  }

  Future<void> register(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/register'),
      headers: await _getHeaders(includeAuth: false),
      body: jsonEncode({
        'username': username,
        'password': password,
        'role': 'customer',
      }),
    );

    if (response.statusCode != 201) {
      throw Exception(response.body);
    }
  }

  // Get nearest shops
  Future<List<dynamic>> getShops(double lat, double long) async {
    final response = await http.get(
      Uri.parse('$baseUrl/shops?lat=$lat&long=$long'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load shops');
    }
  }

  // Upload file
  Future<Map<String, dynamic>> uploadFile({
    required String filePath,
    required int copies,
    required String printMode,
    required String colorMode,
    required String paperSize,
    required String printType,
    int? shopId,
    String? comment,
  }) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/upload'),
    );

    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(await http.MultipartFile.fromPath('file', filePath));
    request.fields['copies'] = copies.toString();
    request.fields['print_mode'] = printMode;
    request.fields['color_mode'] = colorMode;
    request.fields['paper_size'] = paperSize;
    request.fields['print_type'] = printType;
    if (shopId != null) {
      request.fields['shop_id'] = shopId.toString();
    }
    if (comment != null && comment.isNotEmpty) {
      request.fields['comment'] = comment;
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception(response.body);
    }
  }

  // Get my files
  Future<List<dynamic>> getMyFiles() async {
    final response = await http.get(
      Uri.parse('$baseUrl/files'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load files');
    }
  }

  // Check file status
  Future<Map<String, dynamic>> checkFileStatus(int fileId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/files/$fileId/status'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to check file status');
    }
  }

  // Withdraw print
  Future<void> withdrawPrint(int fileId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/withdraw/$fileId'),
      headers: await _getHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to withdraw print');
    }
  }

  // Logout
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('username');
    await prefs.remove('role');
  }
}

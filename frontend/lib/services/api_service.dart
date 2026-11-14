import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

class ApiService {
  static String baseUrl = 'http://192.168.31.159:8080';
  static String? token;
  static Map<String, dynamic>? currentUser;

  static const String _keyToken = 'auth_token';
  static const String _keyUser = 'auth_user';
  static const String _keyBaseUrl = 'backend_base_url';

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString(_keyToken);
    final userJson = prefs.getString(_keyUser);
    if (userJson != null) {
      try {
        currentUser = jsonDecode(userJson) as Map<String, dynamic>;
      } catch (_) {}
    }
    baseUrl = prefs.getString(_keyBaseUrl) ?? 'http://192.168.31.159:8080';
  }

  static Future<void> setBaseUrl(String url) async {
    baseUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBaseUrl, url);
  }

  static bool get isAuthenticated => token != null && token!.isNotEmpty;

  static Map<String, String> _headers({bool isJson = true}) {
    final headers = <String, String>{};
    if (isJson) headers['Content-Type'] = 'application/json';
    if (token != null && token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  // --- AUTHENTICATION ---

  static Future<bool> login(String username, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (res.statusCode == 200) {
      final json = jsonDecode(res.body);
      token = json['token'] as String;
      currentUser = json['user'] as Map<String, dynamic>;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyToken, token!);
      await prefs.setString(_keyUser, jsonEncode(currentUser));
      return true;
    }

    final err = jsonDecode(res.body);
    throw Exception(err['error'] ?? 'Login failed');
  }

  static Future<void> logout() async {
    token = null;
    currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyUser);
  }

  static Future<bool> checkAuth() async {
    if (token == null) return false;
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/v1/auth/me'),
        headers: _headers(),
      );
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        currentUser = json['user'] as Map<String, dynamic>;
        return true;
      }
    } catch (_) {}
    await logout();
    return false;
  }

  static Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/auth/change-password'),
      headers: _headers(),
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    );

    if (res.statusCode != 200) {
      final err = jsonDecode(res.body);
      throw Exception(err['error'] ?? 'Failed to update password');
    }
  }

  // --- BACKUP & RESTORE ---

  static Future<String> exportBackup() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/v1/backup/export'),
      headers: _headers(),
    );

    if (res.statusCode == 200) {
      return res.body;
    }
    throw Exception('Failed to export database: ${res.statusCode}');
  }

  static Future<Map<String, dynamic>> importBackup(
    String backupJson, {
    String mode = 'merge',
  }) async {
    final parsed = jsonDecode(backupJson);
    final payload = {'mode': mode, 'data': parsed['data'] ?? parsed};

    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/backup/import'),
      headers: _headers(),
      body: jsonEncode(payload),
    );

    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    final err = jsonDecode(res.body);
    throw Exception(err['error'] ?? 'Failed to import backup');
  }

  // --- DATA ENDPOINTS ---

  static Future<GatewayStats> fetchStats() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/v1/stats'),
      headers: _headers(),
    );
    if (res.statusCode == 200) {
      final json = jsonDecode(res.body);
      return GatewayStats.fromJson(json['data'] as Map<String, dynamic>);
    }
    throw Exception('Failed to load stats');
  }

  static Future<List<Device>> fetchDevices() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/v1/devices'),
      headers: _headers(),
    );
    if (res.statusCode == 200) {
      final json = jsonDecode(res.body);
      final list = json['data'] as List;
      return list
          .map((item) => Device.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load devices');
  }

  static Future<Device> createDevice(String name) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/devices'),
      headers: _headers(),
      body: jsonEncode({'name': name}),
    );
    if (res.statusCode == 201) {
      final json = jsonDecode(res.body);
      return Device.fromJson(json['data'] as Map<String, dynamic>);
    }
    throw Exception('Failed to create device');
  }

  static Future<void> deleteDevice(String id) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/v1/devices/$id'),
      headers: _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to delete device');
    }
  }

  static Future<List<SmsMessage>> fetchMessages({
    int page = 1,
    int limit = 50,
    String? status,
    String? direction,
    String? search,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (direction != null && direction.isNotEmpty)
      params['direction'] = direction;
    if (search != null && search.isNotEmpty) params['search'] = search;

    final uri = Uri.parse(
      '$baseUrl/api/v1/sms/messages',
    ).replace(queryParameters: params);
    final res = await http.get(uri, headers: _headers());
    if (res.statusCode == 200) {
      final json = jsonDecode(res.body);
      final list = json['data'] as List;
      return list
          .map((item) => SmsMessage.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load messages');
  }

  static Future<SmsMessage> sendSms({
    required String to,
    required String message,
    String? deviceId,
    int simSlot = 0,
  }) async {
    final payload = {
      'to': to,
      'message': message,
      'simSlot': simSlot,
      if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
    };

    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/sms/send'),
      headers: _headers(),
      body: jsonEncode(payload),
    );

    if (res.statusCode == 201) {
      final json = jsonDecode(res.body);
      return SmsMessage.fromJson(json['data'] as Map<String, dynamic>);
    }
    final error = jsonDecode(res.body);
    throw Exception(error['error'] ?? 'Failed to send SMS');
  }

  static Future<void> retryMessage(String id) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/sms/messages/$id/retry'),
      headers: _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to retry message');
    }
  }

  static Future<void> deleteMessage(String id) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/v1/sms/messages/$id'),
      headers: _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to delete message');
    }
  }

  static Future<List<Webhook>> fetchWebhooks() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/v1/webhooks'),
      headers: _headers(),
    );
    if (res.statusCode == 200) {
      final json = jsonDecode(res.body);
      final list = json['data'] as List;
      return list
          .map((item) => Webhook.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load webhooks');
  }

  static Future<Webhook> createWebhook({
    required String url,
    required List<String> events,
    String? secret,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/webhooks'),
      headers: _headers(),
      body: jsonEncode({
        'url': url,
        'events': events,
        if (secret != null && secret.isNotEmpty) 'secret': secret,
      }),
    );
    if (res.statusCode == 201) {
      final json = jsonDecode(res.body);
      return Webhook.fromJson(json['data'] as Map<String, dynamic>);
    }
    throw Exception('Failed to create webhook');
  }

  static Future<void> testWebhook(String id) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/webhooks/$id/test'),
      headers: _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to trigger webhook test');
    }
  }

  static Future<void> deleteWebhook(String id) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/v1/webhooks/$id'),
      headers: _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to delete webhook');
    }
  }

  // --- API KEYS ---

  static Future<List<ApiKey>> fetchApiKeys() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/v1/api-keys'),
      headers: _headers(),
    );
    if (res.statusCode == 200) {
      final json = jsonDecode(res.body);
      final list = json['data'] as List;
      return list
          .map((item) => ApiKey.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load API keys');
  }

  static Future<ApiKey> createApiKey(String name) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/api-keys'),
      headers: _headers(),
      body: jsonEncode({'name': name}),
    );
    if (res.statusCode == 201) {
      final json = jsonDecode(res.body);
      return ApiKey.fromJson(json['data'] as Map<String, dynamic>);
    }
    throw Exception('Failed to create API key');
  }

  static Future<void> deleteApiKey(String id) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/v1/api-keys/$id'),
      headers: _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to delete API key');
    }
  }

  static Future<ApiKey> toggleApiKey(String id) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/api/v1/api-keys/$id/toggle'),
      headers: _headers(),
    );
    if (res.statusCode == 200) {
      final json = jsonDecode(res.body);
      return ApiKey.fromJson(json['data'] as Map<String, dynamic>);
    }
    throw Exception('Failed to toggle API key');
  }

  static Future<List<WebhookLog>> fetchWebhookLogs() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/v1/webhooks/logs'),
      headers: _headers(),
    );
    if (res.statusCode == 200) {
      final json = jsonDecode(res.body);
      final list = json['data'] as List;
      return list
          .map((item) => WebhookLog.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load webhook logs');
  }
}

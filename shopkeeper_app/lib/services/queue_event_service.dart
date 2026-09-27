import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'http_client_factory.dart';

/// Listens to the shopkeeper SSE stream and shows a Windows toast when a new queue job arrives.
class QueueEventService {
  QueueEventService._();
  static final QueueEventService instance = QueueEventService._();

  static String get _baseUrl => AppConfig.baseUrl;
  static Uri get _eventsUri => Uri.parse('$_baseUrl/shopkeeper/events');

  final http.Client _client = createHttpClient();
  bool _running = false;
  bool _stopRequested = false;
  int _backoffSeconds = 1;
  static const int _maxBackoffSeconds = 60;

  /// Start the stream. Call with a valid auth token. Stops on 401 or when [stop] is called.
  void start(String token) {
    if (_running) return;
    _running = true;
    _stopRequested = false;
    _backoffSeconds = 1;
    _runStream(token);
  }

  /// Stop the stream and do not reconnect.
  void stop() {
    _stopRequested = true;
  }

  bool get isRunning => _running;

  Future<void> _runStream(String token) async {
    while (!_stopRequested) {
      try {
        final request = http.Request('GET', _eventsUri);
        request.headers['Authorization'] = 'Bearer $token';
        request.headers['Accept'] = 'text/event-stream';

        final response = await _client.send(request).timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('Connection timeout'),
        );

        if (response.statusCode == 401) {
          if (kDebugMode) debugPrint('QueueEventService: unauthorized, stopping');
          _running = false;
          return;
        }
        if (response.statusCode != 200) {
          if (kDebugMode) debugPrint('QueueEventService: ${response.statusCode}, will retry');
          await _sleepBackoff();
          continue;
        }

        _backoffSeconds = 1; // reset on successful connect

        await for (final event in _parseSSE(response.stream)) {
          if (_stopRequested) break;
          if (event['event'] == 'new_order') {
            final data = event['data'];
            if (data is Map) {
              final message = data['message'] as String? ??
                  'New print job: ${data['file_count'] ?? 1} file(s) in queue';
              await _showNewOrderNotification(message);
            }
          }
        }
      } on TimeoutException catch (e) {
        if (kDebugMode) debugPrint('QueueEventService: $e');
      } catch (e) {
        if (kDebugMode) debugPrint('QueueEventService: $e');
      }

      if (_stopRequested) break;
      await _sleepBackoff();
    }
    _running = false;
  }

  Future<void> _sleepBackoff() async {
    await Future<void>.delayed(Duration(seconds: _backoffSeconds));
    if (_backoffSeconds < _maxBackoffSeconds) {
      _backoffSeconds = (_backoffSeconds * 2).clamp(1, _maxBackoffSeconds);
    }
  }

  /// Parse SSE stream into a stream of { "event": "...", "data": ... }.
  Stream<Map<String, dynamic>> _parseSSE(Stream<List<int>> byteStream) async* {
    String currentEvent = '';
    String currentData = '';
    final buffer = StringBuffer();

    await for (final chunk in byteStream) {
      if (_stopRequested) return;
      buffer.write(utf8.decode(chunk));
      final text = buffer.toString();
      final lines = text.split('\n');
      // If input doesn't end with \n, last segment may be a partial line
      final rejoin = !text.endsWith('\n') && lines.isNotEmpty;
      final tail = rejoin ? lines.removeLast() : null;
      buffer.clear();
      if (tail != null) buffer.write('$tail\n');

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) {
          if (currentEvent.isNotEmpty || currentData.isNotEmpty) {
            Object? data = currentData;
            if (currentData.startsWith('{')) {
              try {
                data = jsonDecode(currentData) as Map<String, dynamic>? ?? currentData;
              } catch (_) {}
            }
            yield {'event': currentEvent.isEmpty ? 'message' : currentEvent, 'data': data};
          }
          currentEvent = '';
          currentData = '';
          continue;
        }
        if (trimmed.startsWith('event:')) {
          currentEvent = trimmed.substring(6).trim();
        } else if (trimmed.startsWith('data:')) {
          currentData = trimmed.substring(5).trim();
        }
      }
    }
  }

  Future<void> _showNewOrderNotification(String message) async {
    await QueueNotificationHelper.showNewOrderNotification(title: 'New print job', body: message);
  }
}

/// Delegates to platform notification (Windows toast). Initialized from main.
class QueueNotificationHelper {
  static Future<void> Function({required String title, required String body})? showNewOrder;

  static Future<void> showNewOrderNotification({required String title, required String body}) async {
    await showNewOrder?.call(title: title, body: body);
  }
}

import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';

/// Handles FCM initialization, token registration with backend, and foreground message handling.
/// When app is in foreground, shows a local notification so the user sees it (FCM does not show one by default).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static bool _initialized = false;
  static const String _channelId = 'qprint_fcm_foreground';
  static const String _channelName = 'Qprint notifications';

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Call from main() before runApp. No-ops if Firebase is not configured.
  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      await Firebase.initializeApp();

      // Local notifications: show FCM messages when app is in foreground (Android)
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
      );
      await _localNotifications.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
      );
      if (Platform.isAndroid) {
        await _localNotifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(
              const AndroidNotificationChannel(
                _channelId,
                _channelName,
                description: 'Push notifications from Qprint',
                importance: Importance.high,
                playSound: true,
              ),
            );
      }

      // iOS: show notification banner/sound when app is in foreground
      if (Platform.isIOS) {
        await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      _initialized = true;
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);
      FirebaseMessaging.instance.onTokenRefresh.listen((String token) {
        ApiService().registerFcmToken(token, _platform);
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('NotificationService: Firebase init skipped: $e');
      }
    }
  }

  static String get _platform => Platform.isIOS ? 'ios' : 'android';

  /// Call when user is logged in (after login or from AuthWrapper). Registers current FCM token with backend.
  static Future<void> registerTokenWithBackend() async {
    if (!_initialized) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await ApiService().registerFcmToken(token, _platform);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('NotificationService: registerTokenWithBackend: $e');
      }
    }
  }

  /// Request notification permission (Android 13+). Call after login if desired.
  static Future<bool> requestPermission() async {
    if (!_initialized) return false;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      if (kDebugMode) debugPrint('NotificationService: requestPermission: $e');
      return false;
    }
  }

  static void _onForegroundMessage(RemoteMessage message) {
    if (kDebugMode) {
      debugPrint('NotificationService: foreground message: ${message.notification?.title}');
    }
    // Show a local notification so the user sees it when app is open (FCM does not show one in foreground).
    final title = message.notification?.title ?? 'Qprint';
    final body = message.notification?.body ?? '';
    if (body.isEmpty) return;
    _showForegroundNotification(
      id: message.hashCode.abs() % 0x7FFFFFFF,
      title: title,
      body: body,
    );
  }

  static Future<void> _showForegroundNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Push notifications from Qprint',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _localNotifications.show(id, title, body, details);
  }

  static void _onMessageOpenedApp(RemoteMessage message) {
    if (kDebugMode) {
      debugPrint('NotificationService: opened from notification: ${message.data}');
    }
    // Optionally navigate by message.data['type'] (e.g. print_ready -> My Orders).
  }
}

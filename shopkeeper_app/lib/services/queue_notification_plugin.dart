import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'queue_event_service.dart';

const int _newOrderNotificationId = 1;

final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

/// Initialize the notification plugin (Windows toast). Call from main() before runApp.
Future<void> initQueueNotifications() async {
  if (!Platform.isWindows) return;

  // GUID must be 8-4-4-4-12 hex without braces for Windows toast (flutter_local_notifications_windows).
  const windowsSettings = WindowsInitializationSettings(
    appName: 'Qprint Shop',
    appUserModelId: 'com.qprint.shopkeeper',
    guid: 'A1B2C3D4-E5F6-7890-ABCD-EF1234567890',
  );

  final windowsImpl = _plugin.resolvePlatformSpecificImplementation<FlutterLocalNotificationsWindows>();
  if (windowsImpl == null) {
    if (kDebugMode) debugPrint('QueueNotification: Windows implementation not available');
    return;
  }

  await windowsImpl.initialize(
    settings: windowsSettings,
    onDidReceiveNotificationResponse: (_) {},
  );

  QueueNotificationHelper.showNewOrder = _showNewOrder;
  if (kDebugMode) debugPrint('QueueNotification: Windows toast initialized');
}

Future<void> _showNewOrder({required String title, required String body}) async {
  const details = NotificationDetails(
    windows: WindowsNotificationDetails(),
  );
  await _plugin.show(
    id: _newOrderNotificationId,
    title: title,
    body: body,
    notificationDetails: details,
  );
}

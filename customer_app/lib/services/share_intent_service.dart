import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lightweight bridge to receive files shared to Qprint from Android's Share sheet.
///
/// This uses a platform method channel so we don't pull in an extra dependency
/// and we can keep behaviour aligned with our existing file validation flow
/// on `UploadScreen`.
class ShareIntentService {
  ShareIntentService._();

  static const MethodChannel _channel =
      MethodChannel('com.qprintsolutions.qprint/share_intent');

  static final ShareIntentService instance = ShareIntentService._();

  /// Returns any file paths passed via the initial share intent when the app
  /// is launched from Android's Share sheet.
  ///
  /// The native side is expected to return either:
  /// - `null` when there is no pending share intent
  /// - a `List<String>` of absolute file paths (already copied to cache dir
  ///   if needed for long‑term access).
  Future<List<File>> getInitialSharedFiles() async {
    if (!Platform.isAndroid) return const [];
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getInitialSharedFiles');
      if (result == null || result.isEmpty) return const [];
      return result
          .whereType<String>()
          .map((path) => File(path))
          .toList(growable: false);
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('ShareIntentService error: $e');
      }
      return const [];
    }
  }
}


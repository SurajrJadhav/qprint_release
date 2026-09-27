import 'dart:async';
import 'package:flutter/foundation.dart';

/// Tracks user activity and triggers idle logout after timeout.
class SessionService {
  static final SessionService _instance = SessionService._();
  static SessionService get instance => _instance;

  SessionService._();

  Timer? _idleTimer;
  DateTime? _lastActivity;
  VoidCallback? _onIdleTimeout;

  static const Duration idleTimeout = Duration(days: 15);

  /// Call when user performs an action (tap, scroll, etc.).
  void touch() {
    _lastActivity = DateTime.now();
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, () {
      if (kDebugMode) debugPrint('Session idle timeout');
      _onIdleTimeout?.call();
    });
  }

  /// Register callback for idle timeout. Call from DashboardScreen.
  void setOnIdleTimeout(VoidCallback cb) {
    _onIdleTimeout = cb;
  }

  /// Clear timeout callback and cancel timer (e.g. on logout).
  void clear() {
    _onIdleTimeout = null;
    _idleTimer?.cancel();
    _idleTimer = null;
  }
}

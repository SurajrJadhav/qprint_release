import 'package:flutter/foundation.dart';

/// Safe, user-facing error messages. Prevents API responses, stack traces, or
/// connection details from being shown in the UI (security best practice).
String getSafeErrorMessage(Object err, [String context = '']) {
  final msg = err.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
  // Allow a few known, safe messages to pass through
  if (msg.contains('customers only') ||
      msg.contains('shopkeepers only') ||
      msg.contains('Not authenticated - please login again') ||
      msg.contains('Session expired') ||
      msg.contains('Invalid password') ||
      msg.contains('Cannot withdraw') ||
      msg.contains('print is in progress') ||
      msg.contains('Plugin error:') ||
      (msg.toLowerCase().contains('already in use') &&
          (msg.toLowerCase().contains('email') ||
              msg.toLowerCase().contains('mobile') ||
              msg.toLowerCase().contains('phone')))) {
    return msg;
  }
  // Map common patterns to generic messages (never expose response.body or stack)
  if (msg.toLowerCase().contains('connection') ||
      msg.toLowerCase().contains('socket') ||
      msg.toLowerCase().contains('network') ||
      msg.toLowerCase().contains('timeout') ||
      msg.toLowerCase().contains('failed host lookup') ||
      msg.toLowerCase().contains('handshake') ||
      msg.toLowerCase().contains('certificate') ||
      msg.toLowerCase().contains('ssl')) {
    return 'Connection problem. Please check your network and try again.';
  }
  if (msg.toLowerCase().contains('login') || msg.toLowerCase().contains('credentials')) {
    return 'Login failed. Please check your email or mobile and password.';
  }
  if (msg.toLowerCase().contains('register')) {
    // Allow backend duplicate-account message to pass through (e.g. email/mobile already in use).
    if (msg.toLowerCase().contains('already in use') ||
        (msg.toLowerCase().contains('already exists') &&
            (msg.toLowerCase().contains('email') ||
                msg.toLowerCase().contains('mobile') ||
                msg.toLowerCase().contains('phone')))) {
      return msg;
    }
    return 'Registration failed. Please check your details and try again.';
  }
  if (msg.toLowerCase().contains('reset') || msg.toLowerCase().contains('password')) {
    return 'Could not complete request. Please check the link or try again later.';
  }
  if (msg.toLowerCase().contains('forgot')) {
    return 'Could not send reset email. Please check the email address and try again.';
  }
  if (msg.toLowerCase().contains('upload') || msg.toLowerCase().contains('calculate')) {
    // Allow safe, user-facing file validation messages from backend
    if (msg.toLowerCase().contains('corrupted') ||
        msg.toLowerCase().contains('invalid') ||
        msg.toLowerCase().contains('does not match') ||
        msg.toLowerCase().contains('valid pdf') ||
        msg.toLowerCase().contains('valid png') ||
        msg.toLowerCase().contains('valid jpeg') ||
        msg.toLowerCase().contains('valid jpg') ||
        msg.contains('Page count not available')) {
      return msg;
    }
    return 'Operation failed. Please try again.';
  }
  if (msg.toLowerCase().contains('payment')) {
    return 'Payment failed. Please try again.';
  }
  if (context == 'referral' || msg.toLowerCase().contains('profile')) {
    return 'Could not load your referral code. Pull down to refresh or tap Retry.';
  }
  // Default: never show raw API/stack to user
  if (kDebugMode) {
    debugPrint('SafeError[$context]: $msg');
  }
  return 'Something went wrong. Please try again.';
}

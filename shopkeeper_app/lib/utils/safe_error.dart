import 'package:flutter/foundation.dart';

/// Safe, user-facing error messages. Prevents API responses, stack traces, or
/// connection details from being shown in the UI (security best practice).
String getSafeErrorMessage(Object err, [String context = '']) {
  final msg = err.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
  final lower = msg.toLowerCase();

  // Allow safe, expected validation errors during registration to pass through.
  // These are short, non-sensitive messages returned by our backend (e.g. duplicates).
  if (context.toLowerCase().contains('register')) {
    if (lower.contains('already registered') ||
        lower.contains('already in use') ||
        lower.contains('invalid or expired code') ||
        lower.contains('email verification') ||
        lower.contains('email does not match') ||
        lower.contains('valid email is required') ||
        lower.contains('invalid email format') ||
        lower.contains('email is required') ||
        lower.contains('full name is required') ||
        lower.contains('phone number is required') ||
        lower.contains('phone number must be 10 digits') ||
        lower.contains('password must be at least') ||
        lower.contains('shop name is required') ||
        lower.contains('address is required') ||
        lower.contains('location') && (lower.contains('required') || lower.contains('invalid'))) {
      return msg;
    }
  }
  // Allow a few known, safe messages to pass through
  if (msg.contains('shopkeepers only') ||
      msg.contains('Not authenticated - please login again') ||
      msg.contains('Plugin error:')) {
    return msg;
  }
  // Map common patterns to generic messages (never expose response.body or stack)
  if (lower.contains('connection') ||
      lower.contains('socket') ||
      lower.contains('network') ||
      lower.contains('timeout') ||
      lower.contains('failed host lookup') ||
      lower.contains('handshake') ||
      lower.contains('certificate') ||
      lower.contains('ssl')) {
    return 'Connection problem. Please check your network and try again.';
  }
  if (lower.contains('login') || lower.contains('credentials')) {
    return 'Login failed. Please check your email or mobile and password.';
  }
  if (lower.contains('register')) {
    return 'Registration failed. Please check your details and try again.';
  }
  if (lower.contains('reset') || lower.contains('password')) {
    return 'Could not complete request. Please check the link or try again later.';
  }
  if (lower.contains('forgot')) {
    return 'Could not send reset email. Please check the email address and try again.';
  }
  // Default: never show raw API/stack to user
  if (kDebugMode) {
    debugPrint('SafeError[$context]: $msg');
  }
  return 'Something went wrong. Please try again.';
}

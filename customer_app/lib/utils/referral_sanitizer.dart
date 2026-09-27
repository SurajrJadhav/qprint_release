/// Sanitizes referral codes from deep links or user input.
/// Prevents injection: only allows safe characters, max length.
const int _maxReferralCodeLength = 64;
final RegExp _safeChar = RegExp(r'[a-zA-Z0-9_-]');

/// Returns a safe referral code: alphanumeric, underscore, hyphen only; max 64 chars.
/// Returns null if input is null/empty after trim; otherwise returns sanitized string.
String? sanitizeReferralCode(String? input) {
  if (input == null) return null;
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  final safe = StringBuffer();
  for (var i = 0; i < trimmed.length && safe.length < _maxReferralCodeLength; i++) {
    final c = trimmed[i];
    if (_safeChar.hasMatch(c)) safe.write(c);
  }
  final result = safe.toString();
  return result.isEmpty ? null : result;
}

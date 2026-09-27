import 'package:crypto/crypto.dart';

/// Verifies file integrity using SHA-256 hash.
/// Returns true if [expectedSha256] is null/empty (no verification requested)
/// or if the computed hash matches the expected value.
/// Returns false if the hash does not match.
bool verifyFileIntegrity(List<int> bytes, String? expectedSha256) {
  if (expectedSha256 == null || expectedSha256.trim().isEmpty) {
    return true;
  }
  final digest = sha256.convert(bytes);
  final computed = digest.toString();
  final expected = expectedSha256.trim().toLowerCase();
  return computed == expected;
}

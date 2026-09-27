import 'dart:io';

/// Sanitizes a filename from API/server to prevent path traversal.
/// Use only base name, strip path separators, replace unsafe chars, limit length.
String sanitizeFilename(String filename) {
  if (filename.isEmpty) return 'unnamed';
  // Get base name (strip any path)
  String base = filename;
  if (base.contains(Platform.pathSeparator)) {
    base = base.split(Platform.pathSeparator).last;
  }
  if (base.contains('/')) {
    base = base.split('/').last;
  }
  if (base.contains('\\')) {
    base = base.split('\\').last;
  }
  // Replace unsafe characters with underscore
  final sanitized = base.replaceAll(RegExp(r'[^\w\.\-]'), '_');
  return sanitized.isEmpty ? 'unnamed' : (sanitized.length > 200 ? sanitized.substring(0, 200) : sanitized);
}

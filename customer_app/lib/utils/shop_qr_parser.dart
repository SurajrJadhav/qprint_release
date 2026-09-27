/// Parses shop id from QR content: URL (https://.../s/123, qprint://shop/123) or plain digits.
/// Handles in-app scan (full URL) and deep links. Returns null if not a valid shop reference.
int? parseShopIdFromQrContent(String raw) {
  // Normalize: trim and remove control chars (barcode scanners sometimes add \r\n)
  final s = raw.replaceAll(RegExp(r'[\s\r\n]+'), ' ').trim();
  if (s.isEmpty) return null;
  // Plain numeric id (e.g. "123" or "123456" - 6-digit shop code)
  if (RegExp(r'^\d{1,9}$').hasMatch(s)) {
    final id = int.tryParse(s);
    if (id != null && id > 0) return id;
    return null;
  }
  // Regex: /s/123 or /s/123? or qprint://shop/123 (case-insensitive path /s/ and scheme)
  final slashSId = RegExp(r'/s/(\d{1,9})', caseSensitive: false);
  final match = slashSId.firstMatch(s);
  if (match != null) {
    final id = int.tryParse(match.group(1)!);
    if (id != null && id > 0) return id;
  }
  // qprint://shop/123 (explicit scheme)
  if (s.toLowerCase().contains('qprint://shop/')) {
    final start = s.toLowerCase().indexOf('qprint://shop/') + 'qprint://shop/'.length;
    final rest = s.substring(start);
    final end = rest.contains('/') ? rest.indexOf('/') : rest.length;
    final segment = rest.substring(0, end).split('?').first.trim();
    final id = int.tryParse(segment);
    if (id != null && id > 0) return id;
  }
  return null;
}

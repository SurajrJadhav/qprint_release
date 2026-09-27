import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'api_service.dart';
import 'converter_engine.dart';
import '../utils/filename_utils.dart';

/// Pre-conversion state for a single file (download + convert to PDF).
enum PreconvertStatus {
  idle,
  downloading,
  downloaded,
  converting,
  ready,
  failed_download,
  failed_convert,
}

/// Entry for one file in the preconvert cache.
class PreconvertEntry {
  PreconvertStatus status;
  String? downloadedPath;
  String? pdfPath;
  String? error;
  Completer<void>? _completer;

  PreconvertEntry({this.status = PreconvertStatus.idle});

  void complete() {
    _completer?.complete();
    _completer = null;
  }
}

/// Cache that pre-downloads and pre-converts queue files so Print is faster.
/// Keyed by file ID. After print, call [deleteLocalFiles] then [remove] for each file.
class PreconvertCache {
  PreconvertCache._();
  static final PreconvertCache instance = PreconvertCache._();

  final Map<int, PreconvertEntry> _entries = {};
  static const Duration _waitForReadyTimeout = Duration(seconds: 90);

  /// Starts background download + convert for one file. Idempotent: if already
  /// downloading/converting, does nothing. If failed or idle, can retry by calling again.
  void startPreconvert(
    int fileId,
    String filename,
    String paperSize,
    ApiService apiService,
  ) {
    final existing = _entries[fileId];
    if (existing != null &&
        (existing.status == PreconvertStatus.downloading ||
            existing.status == PreconvertStatus.converting)) {
      return; // already in progress
    }

    _entries[fileId] = PreconvertEntry(status: PreconvertStatus.downloading);
    _runPreconvert(fileId, filename, paperSize, apiService);
  }

  static const _maxReuseAge = Duration(hours: 2);

  Future<void> _runPreconvert(
    int fileId,
    String filename,
    String paperSize,
    ApiService apiService,
  ) async {
    final entry = _entries[fileId];
    if (entry == null) return;

    Directory tempDir;
    try {
      tempDir = await getTemporaryDirectory();
    } catch (e) {
      if (kDebugMode) print('Preconvert: path_provider failed: $e');
      entry.status = PreconvertStatus.failed_download;
      entry.error = 'Temp directory unavailable';
      entry.complete();
      return;
    }

    final sep = Platform.pathSeparator;

    // Reuse existing PDF from a previous run (e.g. before app restart) to avoid re-download/re-convert.
    final markerFile = File('${tempDir.path}${sep}preconvert_${fileId}_pdf.marker');
    if (await markerFile.exists()) {
      try {
        final pdfPath = (await markerFile.readAsString()).trim();
        if (pdfPath.isNotEmpty) {
          final pdf = File(pdfPath);
          if (await pdf.exists()) {
            final age = DateTime.now().difference(await pdf.lastModified());
            if (age < _maxReuseAge) {
              entry.pdfPath = pdfPath;
              entry.downloadedPath = null;
              entry.status = PreconvertStatus.ready;
              entry.complete();
              if (kDebugMode) print('Preconvert: reusing existing PDF fileId=$fileId');
              return;
            }
          }
        }
      } catch (_) {}
    }

    final safeName = sanitizeFilename(filename);
    final downloadedPath = '${tempDir.path}${sep}preconvert_${fileId}_$safeName';

    try {
      final bytes = await apiService.downloadFile(fileId);
      final file = File(downloadedPath);
      await file.writeAsBytes(bytes);
      entry.downloadedPath = downloadedPath;
      entry.status = PreconvertStatus.downloaded;
    } catch (e) {
      if (kDebugMode) print('Preconvert: download failed for $fileId: $e');
      entry.status = PreconvertStatus.failed_download;
      entry.error = e.toString();
      entry.complete();
      return;
    }

    entry.status = PreconvertStatus.converting;
    try {
      final pdfPath = await ConverterEngine.ensurePdf(
        downloadedPath,
        paperSize: paperSize,
      );
      entry.pdfPath = pdfPath;
      entry.status = PreconvertStatus.ready;
      try {
        await markerFile.writeAsString(pdfPath);
      } catch (_) {}
      if (kDebugMode) print('Preconvert: ready fileId=$fileId');
    } catch (e) {
      if (kDebugMode) print('Preconvert: convert failed for $fileId: $e');
      entry.status = PreconvertStatus.failed_convert;
      entry.error = e.toString();
    }
    entry.complete();
  }

  PreconvertEntry? getEntry(int fileId) => _entries[fileId];

  /// Returns the path to the ready PDF if status is ready and file exists; else null.
  String? getReadyPdfPath(int fileId) {
    final entry = _entries[fileId];
    if (entry == null || entry.status != PreconvertStatus.ready) return null;
    final path = entry.pdfPath;
    if (path == null) return null;
    final f = File(path);
    return f.existsSync() ? path : null;
  }

  /// If status is ready, returns path. If downloading/converting, waits up to [timeout].
  /// Returns path when ready, or null on timeout/failure.
  Future<String?> waitForReady(int fileId, [Duration? timeout]) async {
    final t = timeout ?? _waitForReadyTimeout;
    final entry = _entries[fileId];
    if (entry == null) return null;

    if (entry.status == PreconvertStatus.ready) return getReadyPdfPath(fileId);
    if (entry.status == PreconvertStatus.failed_download ||
        entry.status == PreconvertStatus.failed_convert) return null;

    entry._completer ??= Completer<void>();
    try {
      await entry._completer!.future.timeout(t);
    } on TimeoutException {
      if (kDebugMode) print('Preconvert: waitForReady timeout fileId=$fileId');
      return null;
    }
    return getReadyPdfPath(fileId);
  }

  /// Deletes local downloaded and converted files for this file id. Call after successful print.
  Future<void> deleteLocalFiles(int fileId) async {
    final entry = _entries[fileId];

    if (entry != null) {
      if (entry.downloadedPath != null) {
        try {
          final f = File(entry.downloadedPath!);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      if (entry.pdfPath != null && entry.pdfPath != entry.downloadedPath) {
        try {
          final f = File(entry.pdfPath!);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final sep = Platform.pathSeparator;
      final markerFile = File('${tempDir.path}${sep}preconvert_${fileId}_pdf.marker');
      if (await markerFile.exists()) await markerFile.delete();
    } catch (_) {}
  }

  /// Removes the entry from cache. Call after [deleteLocalFiles] when job is done.
  void remove(int fileId) {
    _entries.remove(fileId);
  }

  /// Remove entries for multiple file ids (e.g. when job is removed from queue).
  void removeAll(Iterable<int> fileIds) {
    for (final id in fileIds) _entries.remove(id);
  }
}

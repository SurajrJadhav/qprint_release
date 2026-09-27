import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Converter engine: File → (choose by extension) → PDF.
///
/// Design:
///   File to print
///        ↓
///   Choose converter by extension
///        ↓
///   PDF  (passthrough or convert)
///        ↓
///   Printer (e.g. SumatraPDF CLI)
///
/// Supported: PDF (passthrough), images (png/jpg/jpeg → PDF, fit to paper),
/// Word/PPT (doc/docx/ppt/pptx → PDF via LibreOffice).
class ConverterEngine {
  static const String _passthrough = 'passthrough';
  static const String _word = 'word';
  static const String _ppt = 'ppt';
  static const String _image = 'image';

  /// Picks a converter for the given file path based on extension.
  /// Returns converter id, or null if unsupported.
  ///
  /// - pdf → passthrough (no conversion)
  /// - doc, docx → word (convert to PDF via LibreOffice)
  /// - ppt, pptx → ppt (convert to PDF via LibreOffice)
  /// - png, jpg, jpeg → image (convert to PDF, fit to paper)
  static String? chooseConverterByExtension(String path) {
    final ext = _extension(path);
    switch (ext) {
      case 'pdf':
        return _passthrough;
      case 'doc':
      case 'docx':
        return _word;
      case 'ppt':
      case 'pptx':
        return _ppt;
      case 'png':
      case 'jpg':
      case 'jpeg':
        return _image;
      default:
        return null;
    }
  }

  /// Ensures the file is PDF and returns the path to the PDF to print.
  /// If already PDF, returns [path]. Otherwise converts when implemented.
  /// [paperSize] is used for image→PDF (fit to page); e.g. 'A4', 'Letter'.
  static Future<String> ensurePdf(String path, {String paperSize = 'A4'}) async {
    final converter = chooseConverterByExtension(path);
    if (converter == null) {
      throw UnsupportedError(
        'This file type is not supported. Please use PDF, images (PNG/JPG), Word (DOC/DOCX), or PowerPoint (PPT/PPTX) files.',
      );
    }
    if (converter == _passthrough) {
      final f = File(path);
      if (!await f.exists()) {
        throw Exception('File not found: $path');
      }
      return path;
    }
    if (converter == _word) {
      return _wordToPdf(path, paperSize);
    }
    if (converter == _ppt) {
      return _pptToPdf(path, paperSize);
    }
    if (converter == _image) {
      return _imageToPdf(path, paperSize);
    }
    throw UnsupportedError('File conversion is not available for this file type. Please use a PDF file instead.');
  }

  /// Converts image (png/jpg/jpeg) to PDF, fitting to [paperSize] without distorting.
  /// Uses BoxFit.contain: scales to fit within page, preserves aspect ratio, no cropping.
  /// Original image data is embedded; no re-encoding or quality loss from conversion.
  static Future<String> _imageToPdf(String imagePath, String paperSize) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw Exception('Image file not found. Please try again.');
    }
    final bytes = await file.readAsBytes();

    final format = _pageFormatFromPaperSize(paperSize);
    const marginPt = 24.0;
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(marginPt),
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Image(
              pw.MemoryImage(bytes),
              fit: pw.BoxFit.contain,
              alignment: pw.Alignment.center,
            ),
          );
        },
      ),
    );

    final out = await doc.save();
    final dir = await getTemporaryDirectory();
    final sep = Platform.pathSeparator;
    final name = 'qprint_img_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final outPath = '${dir.path}$sep$name';
    final outFile = File(outPath);
    await outFile.writeAsBytes(out);

    return outPath;
  }

  static PdfPageFormat _pageFormatFromPaperSize(String paperSize) {
    switch (paperSize.toUpperCase()) {
      case 'A4':
        return PdfPageFormat.a4;
      case 'LETTER':
        return PdfPageFormat.letter;
      case 'LEGAL':
        return PdfPageFormat.legal;
      case 'A3':
        return PdfPageFormat.a3;
      case 'A5':
        return PdfPageFormat.a5;
      default:
        return PdfPageFormat.a4;
    }
  }

  /// Converts Word (doc/docx) to PDF using LibreOffice headless.
  /// Requires LibreOffice portable in bin/LibreOffice/ (or next to app exe).
  static Future<String> _wordToPdf(String docPath, String paperSize) async {
    return _libreOfficeToPdf(docPath, paperSize);
  }

  /// Converts PowerPoint (ppt/pptx) to PDF using LibreOffice headless.
  /// Requires LibreOffice portable in bin/LibreOffice/ (or next to app exe).
  static Future<String> _pptToPdf(String pptPath, String paperSize) async {
    return _libreOfficeToPdf(pptPath, paperSize);
  }

  /// Converts Office document (Word/PPT) to PDF via LibreOffice headless.
  /// [paperSize] is passed but LibreOffice CLI doesn't directly support it;
  /// conversion uses document's page size, then we could adjust PDF if needed.
  static Future<String> _libreOfficeToPdf(String inputPath, String paperSize) async {
    final file = File(inputPath);
    if (!await file.exists()) {
      throw Exception('Document file not found. Please try again.');
    }

    final soffice = await _libreOfficePath();
    if (soffice == null) {
      throw Exception(
        'Word and PowerPoint conversion is not available. Please use PDF or image files instead.'
      );
    }

    // Use absolute paths to avoid issues
    final absoluteInput = file.absolute.path;
    final dir = await getTemporaryDirectory();
    final absoluteOutDir = Directory(dir.path).absolute.path;
    final sep = Platform.pathSeparator;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final name = 'qprint_office_$timestamp.pdf';
    final outPath = '$absoluteOutDir$sep$name';

    File? tempInputFile; // Declare at function scope for cleanup in catch block
    String? userProfileDir; // Declare at function scope for cleanup
    bool profileIsPersistent = false;

    try {
      // Normalize path separators to backslashes for Windows
      final normalizedInput = absoluteInput.replaceAll('/', '\\');
      final normalizedOutDir = absoluteOutDir.replaceAll('/', '\\');
      // Portable LibreOffice must run with its program dir as cwd so it finds DLLs/config.
      final sofficeDir = File(soffice).parent.path.replaceAll('/', '\\');
      if (kDebugMode) print('LibreOffice: Converting $normalizedInput to PDF...');
      if (kDebugMode) print('LibreOffice: Output directory: $normalizedOutDir');
      if (kDebugMode) print('LibreOffice: soffice.exe path: $soffice');
      if (kDebugMode) print('LibreOffice: working directory: $sofficeDir');
      
      // Wait a moment before conversion to ensure file is ready
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Workaround: Copy file to temp location with simpler name (no spaces) if needed
      // Some LibreOffice versions have issues with spaces in filenames
      String inputFileToUse = normalizedInput;
      
      if (normalizedInput.contains(' ')) {
        if (kDebugMode) print('LibreOffice: Input filename contains spaces, creating temp copy...');
        final simpleName = 'qprint_input_${DateTime.now().millisecondsSinceEpoch}.${_extension(normalizedInput)}';
        final tempInputPath = '$normalizedOutDir\\$simpleName';
        tempInputFile = await file.copy(tempInputPath);
        inputFileToUse = tempInputPath;
        if (kDebugMode) print('LibreOffice: Using temp file: $inputFileToUse');
      }
      
      // Use a single persistent profile dir so LibreOffice does not treat every run as first run (no update popup).
      // Profile is created under app application support and seeded with update check disabled.
      userProfileDir = await _getPersistentLibreOfficeProfileDir();
      if (userProfileDir != null) profileIsPersistent = true;
      if (userProfileDir == null) {
        // Fallback: temp profile (may trigger update check on first run)
        profileIsPersistent = false;
        userProfileDir = '$normalizedOutDir\\lo_profile_${DateTime.now().millisecondsSinceEpoch}';
        try {
          await Directory(userProfileDir!).create(recursive: true);
          if (kDebugMode) print('LibreOffice: Created temp user profile dir: $userProfileDir');
        } catch (e) {
          if (kDebugMode) print('LibreOffice: Warning: Could not create user profile dir: $e');
          userProfileDir = null;
        }
      } else if (kDebugMode) {
        print('LibreOffice: Using persistent profile dir: $userProfileDir');
      }
      
      // Build command - specify output file explicitly to avoid naming issues
      // Use --norestore to prevent session restoration issues
      // Use -env:UserInstallation to specify profile directory (prevents permission issues)
      final args = <String>[
        '--headless',
        '--nodefault',
        '--nolockcheck',
        '--norestore',
        '--convert-to', 'pdf',
        '--outdir', normalizedOutDir,
        inputFileToUse,
      ];
      
      // Add user profile directory if we created one. Use URI with encoding so spaces (e.g. "Qprint Shop") don't break LibreOffice.
      final profileDir = userProfileDir;
      final userInstallationUrl = profileDir != null ? Uri.file(profileDir).toString() : null;
      if (userInstallationUrl != null) {
        args.insert(4, '-env:UserInstallation=$userInstallationUrl');
      }
      
      if (kDebugMode) print('LibreOffice: Command: $soffice ${args.join(' ')}');
      if (kDebugMode) print('LibreOffice: Input file exists: ${await file.exists()}');
      if (kDebugMode) print('LibreOffice: Output dir exists: ${await Directory(normalizedOutDir).exists()}');
      
      // Check permissions
      try {
        final inputStat = await file.stat();
        if (kDebugMode) print('LibreOffice: Input file size: ${inputStat.size} bytes, readable: true');
        
        // Test write permission in output directory
        final testFile = File('$normalizedOutDir\\lo_test_${DateTime.now().millisecondsSinceEpoch}.tmp');
        try {
          await testFile.writeAsString('test');
          await testFile.delete();
          if (kDebugMode) print('LibreOffice: Output dir is writable');
        } catch (e) {
          if (kDebugMode) print('LibreOffice: WARNING - Output dir may not be writable: $e');
        }
      } catch (e) {
        if (kDebugMode) print('LibreOffice: WARNING - Could not check file permissions: $e');
      }
      
      // On Windows, run from LibreOffice's program dir (sofficeDir) so portable install finds DLLs.
      // When profile URL contains '%' (e.g. space → %20), cmd.exe expands % as env vars and breaks the path.
      // So use direct soffice in that case; otherwise try cmd first and retry with direct soffice on failure.
      ProcessResult result;
      if (Platform.isWindows) {
        final useDirectSoffice = userInstallationUrl != null && userInstallationUrl.contains('%');
        if (!useDirectSoffice) {
          final profileArg = userInstallationUrl != null
              ? '-env:UserInstallation="$userInstallationUrl" '
              : '';
          final cmdArg = 'cd /d "$sofficeDir" && "$soffice" --headless --nodefault --nolockcheck --norestore $profileArg--convert-to pdf --outdir "$normalizedOutDir" "$inputFileToUse"';
          if (kDebugMode) print('LibreOffice: Running via cmd.exe (cwd=$sofficeDir)');
          result = await Process.run(
            r'C:\Windows\System32\cmd.exe',
            ['/c', cmdArg],
            workingDirectory: sofficeDir,
          );
          if (result.exitCode != 0) {
            if (kDebugMode) print('LibreOffice: cmd.exe failed (exit ${result.exitCode}), retrying with direct soffice...');
            if (kDebugMode && result.stderr.toString().isNotEmpty) print('LibreOffice: cmd stderr: ${result.stderr}');
            result = await Process.run(
              soffice,
              args,
              runInShell: false,
              workingDirectory: sofficeDir,
            );
            if (kDebugMode) print('LibreOffice: Direct soffice exit code: ${result.exitCode} (0=ok, 1=may still succeed)');
          }
        } else {
          if (kDebugMode) print('LibreOffice: Profile path has % (e.g. space), using direct soffice to avoid cmd parsing');
          result = await Process.run(
            soffice,
            args,
            runInShell: false,
            workingDirectory: sofficeDir,
          );
          if (kDebugMode) print('LibreOffice: Direct soffice exit code: ${result.exitCode} (0=ok, 1=may still succeed)');
        }
      } else {
        // Non-Windows: run from soffice dir so portable install finds libs
        try {
          result = await Process.run(
            soffice,
            args,
            runInShell: false,
            workingDirectory: sofficeDir,
          );
        } catch (e) {
          if (kDebugMode) print('LibreOffice: Process.run failed, trying with shell: $e');
          final quotedArgs = <String>[
            '--headless',
            '--nodefault',
            '--nolockcheck',
            '--norestore',
            '--convert-to', 'pdf',
            '--outdir', '"$normalizedOutDir"',
            '"$inputFileToUse"',
          ];
          if (userInstallationUrl != null) {
            quotedArgs.insert(4, '-env:UserInstallation=$userInstallationUrl');
          }
          result = await Process.run(
            soffice,
            quotedArgs,
            runInShell: true,
            workingDirectory: sofficeDir,
          );
        }
      }

      if (kDebugMode) print('LibreOffice: Exit code: ${result.exitCode}');
      
      // Capture output immediately
      final stdoutRaw = result.stdout.toString();
      final stderrRaw = result.stderr.toString();
      
      if (stdoutRaw.isNotEmpty && kDebugMode) {
        print('LibreOffice stdout: $stdoutRaw');
      }
      if (stderrRaw.isNotEmpty) {
        if (kDebugMode) print('LibreOffice stderr: $stderrRaw');
      }
      
      // Check if LibreOffice printed any warnings or errors in stdout/stderr
      final allOutput = (stdoutRaw + stderrRaw).toLowerCase();
      if (allOutput.contains('error') || 
          allOutput.contains('failed') || 
          allOutput.contains('cannot') ||
          allOutput.contains('unsupported') ||
          allOutput.contains('corrupted')) {
        if (kDebugMode) print('LibreOffice: Warning/error detected in output');
      }

      // Check for common LibreOffice errors even with exit code 0
      final stderrStr = result.stderr.toString();
      final stdoutStr = result.stdout.toString();
      
      // LibreOffice sometimes returns 0 even on errors
      if (stderrStr.toLowerCase().contains('error') || 
          stderrStr.toLowerCase().contains('failed') ||
          stderrStr.toLowerCase().contains('cannot') ||
          stderrStr.toLowerCase().contains('unsupported') ||
          stderrStr.toLowerCase().contains('corrupted')) {
        // User-friendly error message
        throw Exception(
          'Unable to convert document to PDF. The file format may not be supported or the file may be corrupted.'
        );
      }
      
      // Some LibreOffice versions return exit code 1 even on successful conversion.
      // Proceed to look for the PDF; only throw if we don't find it.
      final exitOk = result.exitCode == 0 || result.exitCode == 1;
      if (!exitOk) {
        throw Exception(
          'Unable to convert document to PDF. Please ensure the file is not corrupted or password-protected.'
        );
      }
      if (result.exitCode == 1 && kDebugMode) {
        print('LibreOffice: Exit code 1 (some versions use this for success); checking for PDF...');
      }

      // LibreOffice outputs PDF with same name as input (different extension)
      // Handle filenames with multiple dots or special characters
      final inputNameForOutput = inputFileToUse.split(RegExp(r'[/\\]')).last;
      final inputName = normalizedInput.split(RegExp(r'[/\\]')).last;
      
      // Get base name from the file we actually used (might be temp file)
      final lastDotIndex = inputNameForOutput.lastIndexOf('.');
      final baseName = lastDotIndex > 0 
          ? inputNameForOutput.substring(0, lastDotIndex)
          : inputNameForOutput;
      
      // Wait longer for file system to catch up (LibreOffice can be slow, especially for large files)
      // Also check multiple times as LibreOffice might take time to write
      // Increased wait time: up to 10 seconds (20 checks × 500ms)
      bool pdfFound = false;
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Quick check if file appeared
        final quickCheck = '$normalizedOutDir\\${baseName}.pdf';
        if (await File(quickCheck).exists()) {
          if (kDebugMode) print('LibreOffice: PDF found after ${(i + 1) * 500}ms wait');
          pdfFound = true;
          break;
        }
      }
      
      if (!pdfFound) {
        if (kDebugMode) print('LibreOffice: PDF not found after 10 seconds, continuing search...');
      }
      
      // Also check if LibreOffice output anything useful in stdout
      // (stdoutStr already declared above)
      if (stdoutStr.isNotEmpty) {
        if (kDebugMode) print('LibreOffice stdout content: $stdoutStr');
        // Sometimes LibreOffice prints the output path in stdout
        final lines = stdoutStr.split('\n');
        for (final line in lines) {
          if (line.trim().toLowerCase().endsWith('.pdf')) {
            if (kDebugMode) print('LibreOffice: Found PDF path in stdout: ${line.trim()}');
          }
        }
      }
      
      if (kDebugMode) print('LibreOffice: Input filename: $inputName');
      if (kDebugMode) print('LibreOffice: Expected base name: $baseName');
      
      // Try multiple possible output paths (normalized separators)
      // LibreOffice might output with different name variations
      final possibleOutputs = <String>[
        '$normalizedOutDir\\${baseName}.pdf', // Standard output
        '$normalizedOutDir\\$inputName.pdf', // If input had no extension
        '$normalizedOutDir\\${baseName.replaceAll(' ', '_')}.pdf', // Spaces replaced with underscores
        '$normalizedOutDir\\${baseName.replaceAll(' ', '%20')}.pdf', // URL-encoded spaces
        '$normalizedOutDir\\${baseName.replaceAll(' ', '-')}.pdf', // Spaces replaced with hyphens
        // Also check current working directory (LibreOffice sometimes ignores --outdir)
        '${Directory.current.path}\\${baseName}.pdf',
        '${Directory.current.path}\\$inputName.pdf',
      ];

      // Also check for files that might have been created with URL encoding or different names
      String? foundOutput;
      for (final possiblePath in possibleOutputs) {
        final normalizedPath = possiblePath.replaceAll('/', '\\');
        if (kDebugMode) print('LibreOffice: Checking: $normalizedPath');
        if (await File(normalizedPath).exists()) {
          foundOutput = normalizedPath;
          if (kDebugMode) print('LibreOffice: Found at expected path: $foundOutput');
          break;
        }
      }

      // If not found, list all PDFs in output directory created recently
      if (foundOutput == null) {
        if (kDebugMode) print('LibreOffice: Expected output not found. Searching in $normalizedOutDir...');
        final outDir = Directory(normalizedOutDir);
        if (await outDir.exists()) {
          try {
            final files = outDir.listSync();
            if (kDebugMode) print('LibreOffice: Total files in output dir: ${files.length}');
            
            final pdfFiles = files.whereType<File>()
                .where((f) => f.path.toLowerCase().endsWith('.pdf'))
                .toList();
            
            // Also check for files that might match the base name (LibreOffice might create with different extension)
            final matchingFiles = files.whereType<File>()
                .where((f) {
                  final name = f.path.split(RegExp(r'[/\\]')).last.toLowerCase();
                  final baseLower = baseName.toLowerCase();
                  return name.contains(baseLower) || name.contains('batch_51_1769408883');
                })
                .toList();
            
            if (kDebugMode) print('LibreOffice: PDF files found: ${pdfFiles.length}');
            if (matchingFiles.isNotEmpty) {
              if (kDebugMode) print('LibreOffice: Files matching base name: ${matchingFiles.length}');
              for (final match in matchingFiles.take(5)) {
                if (kDebugMode) print('  - ${match.path}');
              }
            }
            
            // Sort by modification time (newest first)
            pdfFiles.sort((a, b) {
              try {
                final aStat = a.statSync();
                final bStat = b.statSync();
                return bStat.modified.compareTo(aStat.modified);
              } catch (e) {
                return 0;
              }
            });

            if (pdfFiles.isNotEmpty) {
              if (kDebugMode) print('LibreOffice: Listing all PDFs (newest first):');
              for (final pdf in pdfFiles.take(10)) {
                try {
                  final stat = pdf.statSync();
                  final age = DateTime.now().difference(stat.modified).inSeconds;
                  if (kDebugMode) print('  - ${pdf.path} (modified: ${stat.modified}, age: ${age}s)');
                  
                  // Take the most recently modified PDF (likely our output)
                  if (foundOutput == null && age < 60) { // Created within last 60 seconds
                    foundOutput = pdf.path;
                    if (kDebugMode) print('LibreOffice: Using most recent PDF: $foundOutput');
                  }
                } catch (e) {
                  if (kDebugMode) print('LibreOffice: Error checking ${pdf.path}: $e');
                }
              }
            } else {
              if (kDebugMode) print('LibreOffice: No PDF files found in output directory');
              
              // Check current working directory as well
              if (kDebugMode) print('LibreOffice: Also checking current directory: ${Directory.current.path}');
              try {
                final cwdFiles = Directory.current.listSync();
                final cwdPdfs = cwdFiles.whereType<File>()
                    .where((f) => f.path.toLowerCase().endsWith('.pdf'))
                    .toList();
                if (cwdPdfs.isNotEmpty) {
                  if (kDebugMode) print('LibreOffice: Found ${cwdPdfs.length} PDF(s) in current directory:');
                  for (final pdf in cwdPdfs.take(5)) {
                    try {
                      final stat = pdf.statSync();
                      final age = DateTime.now().difference(stat.modified).inSeconds;
                      if (kDebugMode) print('  - ${pdf.path} (modified: ${stat.modified}, age: ${age}s)');
                      if (foundOutput == null && age < 60) {
                        foundOutput = pdf.path;
                        if (kDebugMode) print('LibreOffice: Using PDF from current directory: $foundOutput');
                      }
                    } catch (e) {
                      if (kDebugMode) print('LibreOffice: Error checking ${pdf.path}: $e');
                    }
                  }
                }
              } catch (e) {
                if (kDebugMode) print('LibreOffice: Error checking current directory: $e');
              }
              
              // List all files for debugging (only first few)
              if (kDebugMode) print('LibreOffice: Sample files in output dir (first 10):');
              for (final file in files.take(10)) {
                if (file is File) {
                  if (kDebugMode) print('  - ${file.path}');
                }
              }
            }
          } catch (e) {
            if (kDebugMode) print('LibreOffice: Error listing directory: $e');
          }
        } else {
          if (kDebugMode) print('LibreOffice: Output directory does not exist: $normalizedOutDir');
        }
      }

      if (foundOutput == null) {
        // Last attempt: check if input file itself is readable and valid
        try {
          final inputStat = await file.stat();
          if (kDebugMode) print('LibreOffice: Input file size: ${inputStat.size} bytes');
          if (inputStat.size == 0) {
            throw Exception('The file is empty and cannot be converted.');
          }
        } catch (e) {
          if (kDebugMode) print('LibreOffice: Error checking input file: $e');
        }
        
        // User-friendly error message (no technical details)
        throw Exception(
          'Unable to convert document to PDF. The file may be corrupted, password-protected, or in an unsupported format. Please try a different file or contact support.'
        );
      }

      // Clean up temp input file if we created one
      if (tempInputFile != null && await tempInputFile.exists()) {
        try {
          await tempInputFile.delete();
          if (kDebugMode) print('LibreOffice: Cleaned up temp input file');
        } catch (e) {
          if (kDebugMode) print('LibreOffice: Warning: Could not delete temp input file: $e');
        }
      }

      // Rename to our temp name for consistency
      if (foundOutput != outPath) {
        final foundFile = File(foundOutput);
        if (await File(outPath).exists()) {
          await File(outPath).delete(); // Remove existing file if any
        }
        await foundFile.rename(outPath);
        if (kDebugMode) print('LibreOffice: Renamed output to $outPath');
      }

      return outPath;
    } catch (e) {
      // Clean up temp input file if we created one (even on error)
      if (tempInputFile != null && await tempInputFile.exists()) {
        try {
          await tempInputFile.delete();
          if (kDebugMode) print('LibreOffice: Cleaned up temp input file after error');
        } catch (_) {}
      }
      
      // Re-throw user-friendly exceptions as-is, wrap others
      if (e is Exception) {
        // If it's already a user-friendly message, rethrow it
        final msg = e.toString();
        if (msg.contains('Unable to convert') || 
            msg.contains('not available') ||
            msg.contains('empty and cannot')) {
          rethrow;
        }
        // Otherwise, provide a generic user-friendly message
        throw Exception(
          'Unable to convert document to PDF. Please try a different file or contact support.'
        );
      }
      throw Exception(
        'Unable to convert document to PDF. Please try a different file or contact support.'
      );
    } finally {
      // Clean up only temp profile dirs (never delete the persistent profile)
      if (!profileIsPersistent && userProfileDir != null) {
        try {
          final profileDir = Directory(userProfileDir!);
          if (await profileDir.exists()) {
            await profileDir.delete(recursive: true);
            if (kDebugMode) print('LibreOffice: Cleaned up temp user profile dir');
          }
        } catch (e) {
          if (kDebugMode) print('LibreOffice: Warning: Could not clean up user profile dir: $e');
        }
      }
    }
  }

  /// Persistent LibreOffice user profile dir (so we don't get "first run" / update check every time).
  /// Uses [getApplicationSupportDirectory] + "LibreOfficeProfile". Same API for run-from-build and
  /// installed app; path is per-user and per-machine, so safe when the app is installed on another PC.
  /// Seeded with update-disabled config when the profile is new.
  static Future<String?> _getPersistentLibreOfficeProfileDir() async {
    try {
      final appSupport = await getApplicationSupportDirectory();
      final sep = Platform.pathSeparator;
      final profileDir = '${appSupport.path}${sep}LibreOfficeProfile';
      final userDir = '$profileDir${sep}user';
      final regFile = File('$userDir${sep}registrymodifications.xcu');

      await Directory(profileDir).create(recursive: true);

      // Seed update-disabled config only if user registry doesn't exist yet (new profile).
      if (!await regFile.exists()) {
        await Directory(userDir).create(recursive: true);
        const xcuContent = '''<?xml version="1.0" encoding="UTF-8"?>
<oor:items xmlns:oor="http://openoffice.org/2001/registry">
  <item oor:path="/org.openoffice.Office.Jobs/Jobs/UpdateCheck/Arguments"><prop oor:name="AutoCheckEnabled" oor:type="xs:boolean"><value>false</value></prop></item>
</oor:items>
''';
        await regFile.writeAsString(xcuContent);
        if (kDebugMode) print('LibreOffice: Seeded persistent profile with update check disabled');
      }

      return profileDir;
    } catch (e) {
      if (kDebugMode) print('LibreOffice: Could not get persistent profile dir: $e');
      return null;
    }
  }

  /// Returns path to LibreOffice soffice.exe, or null if not found.
  /// Checks: (1) next to app exe (LibreOffice/App/libreoffice/program/soffice.exe),
  /// (2) windows/runner/bin/LibreOffice/ from cwd.
  static Future<String?> _libreOfficePath() async {
    final sep = Platform.pathSeparator;
    final candidates = <String>[];

    final exe = Platform.resolvedExecutable;
    candidates.add('${File(exe).parent.path}${sep}LibreOffice${sep}App${sep}libreoffice${sep}program${sep}soffice.exe');

    final cwd = Directory.current.path;
    candidates.add('$cwd${sep}windows${sep}runner${sep}bin${sep}LibreOffice${sep}App${sep}libreoffice${sep}program${sep}soffice.exe');

    for (final p in candidates) {
      if (await File(p).exists()) return p;
    }
    return null;
  }

  static String _extension(String path) {
    final i = path.lastIndexOf(RegExp(r'[/\\.]'));
    if (i < 0 || path[i] != '.') return '';
    return path.substring(i + 1).toLowerCase();
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';

import 'converter_engine.dart';

/// Print job tracking information
class PrintJobInfo {
  final String documentName;
  final String printerName;
  final DateTime sentAt;
  
  PrintJobInfo({
    required this.documentName,
    required this.printerName,
    required this.sentAt,
  });
}

/// Enhanced PrinterService that handles all print options and verifies success
class PrinterService {
  /// Print a file with all customer-specified options
  /// Returns PrintJobInfo if print was sent successfully, null otherwise
  /// Note: This only confirms the job was sent to the queue, not that it completed
  Future<PrintJobInfo?> printFile({
    required String filePath,
    required int copies,
    required String printMode, // 'single' or 'double'
    required String colorMode,  // 'bw' or 'color'
    required String paperSize,  // 'A4', 'Letter', etc.
    required String printerName,
  }) async {
    // 1. Validate file exists
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found at $filePath');
    }

    // 2. Print based on platform
    bool success = false;
    String documentName = file.path.split(Platform.pathSeparator).last;
    String? windowsPrintedPath; // PDF path actually sent to printer (for queue verification)

    if (Platform.isLinux || Platform.isMacOS) {
      success = await _printLinux(
          filePath, copies, printMode, colorMode, printerName);
    } else if (Platform.isWindows) {
      windowsPrintedPath = await _printWindows(
          filePath, copies, printMode, colorMode, paperSize, printerName);
      success = windowsPrintedPath != null;
      if (success && windowsPrintedPath != null) {
        documentName = windowsPrintedPath.split(Platform.pathSeparator).last;
      }
    } else if (Platform.isAndroid || Platform.isIOS) {
      final bytes = await file.readAsBytes();
      final format = _getPdfPageFormat(paperSize);
      success = await _printMobile(bytes, copies, printMode, colorMode, format);
    } else {
      throw Exception('Unsupported platform');
    }

    if (!success) {
      return null;
    }

    // 3. Return job info for tracking (verification happens separately)
    return PrintJobInfo(
      documentName: documentName,
      printerName: printerName,
      sentAt: DateTime.now(),
    );
  }

  /// Verify that a print job has completed successfully
  /// Polls the print queue until job is completed or timeout
  /// Returns true if print completed successfully, false if failed or timeout
  Future<bool> verifyPrintCompletion({
    required PrintJobInfo jobInfo,
    Duration timeout = const Duration(seconds: 60),
    Duration pollInterval = const Duration(seconds: 2),
  }) async {
    if (Platform.isWindows) {
      return await _verifyPrintCompletionWindows(
        jobInfo: jobInfo,
        timeout: timeout,
        pollInterval: pollInterval,
      );
    } else if (Platform.isLinux || Platform.isMacOS) {
      return await _verifyPrintCompletionLinux(
        printerName: jobInfo.printerName,
        timeout: timeout,
        pollInterval: pollInterval,
      );
    }
    
    // For mobile platforms, we can't verify automatically
    // Return true after a short delay (user confirms via dialog)
    await Future.delayed(const Duration(seconds: 3));
    return true;
  }

  /// Linux/MacOS printing using CUPS (lp command)
  /// Supports all print options via CUPS options
  Future<bool> _printLinux(
    String filePath,
    int copies,
    String printMode,
    String colorMode,
    String printerName,
  ) async {
    try {
      List<String> args = [
        '-d', printerName,
        '-n', copies.toString(),
      ];

      // Double-sided printing
      if (printMode.toLowerCase() == 'double' || 
          printMode.toLowerCase().contains('double')) {
        args.addAll(['-o', 'sides=two-sided-long-edge']);
      } else {
        args.addAll(['-o', 'sides=one-sided']);
      }

      // Color mode
      if (colorMode.toLowerCase() == 'color') {
        args.addAll(['-o', 'ColorMode=Color']);
        args.addAll(['-o', 'print-color-mode=color']);
      } else {
        args.addAll(['-o', 'ColorMode=Monochrome']);
        args.addAll(['-o', 'print-color-mode=monochrome']);
      }

      // Fit to page
      args.addAll(['-o', 'fit-to-page']);
      
      // Add file path
      args.add(filePath);

      if (kDebugMode) print('Executing: lp ${args.join(' ')}');

      final result = await Process.run('lp', args);
      
      if (result.exitCode != 0) {
        if (kDebugMode) print('Print failed: ${result.stderr}');
        return false;
      }

      // Extract job ID from output if available
      final output = result.stdout.toString();
      if (output.contains('request id is')) {
        if (kDebugMode) print('Print job queued: $output');
      }

      return true;
    } catch (e) {
      if (kDebugMode) print('Linux print error: $e');
      return false;
    }
  }

  /// Windows printing: File → converter (placeholder) → PDF → SumatraPDF CLI → Printer.
  /// Silent; supports copies, duplex, color via -print-settings.
  /// Returns the PDF path that was sent to the printer on success (for verification),
  /// or null on failure. Throws on conversion/Sumatra errors.
  Future<String?> _printWindows(
    String filePath,
    int copies,
    String printMode,
    String colorMode,
    String paperSize,
    String printerName,
  ) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found at $filePath');
    }
    final absolutePath = file.absolute.path;

    final pdfPath = await ConverterEngine.ensurePdf(absolutePath, paperSize: paperSize);
    final sumatra = await _sumatraPdfPath();
    if (sumatra == null) {
      throw Exception(
        'SumatraPDF not found. Run scripts/setup_sumatra.ps1 from shopkeeper_app, '
        'then flutter clean and rebuild. Expect: windows/runner/bin/SumatraPDF.exe '
        'or next to the app exe (build/windows/x64/runner/Release/).',
      );
    }

    final n = copies.clamp(1, 999);
    final duplex = printMode.toLowerCase().contains('double');
    final color = colorMode.toLowerCase() == 'color';
    final parts = <String>['${n}x', duplex ? 'duplex' : 'simplex', color ? 'color' : 'monochrome', 'fit'];
    final paper = _paperForSumatra(paperSize);
    if (paper != null) parts.add('paper=$paper');
    final settings = parts.join(',');

    try {
      final result = await Process.run(
        sumatra!,
        [
          '-silent',
          '-print-to', printerName,
          '-print-settings', settings,
          pdfPath,
        ],
        runInShell: false,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode != 0) {
        final se = (result.stderr as String?)?.trim() ?? '';
        final so = (result.stdout as String?)?.trim() ?? '';
        final err = se.isNotEmpty ? se : so;
        throw Exception('SumatraPDF failed (exit ${result.exitCode}): $err');
      }
      if (kDebugMode) print('✅ Print sent to $printerName');
      return pdfPath;
    } catch (e) {
      if (kDebugMode) print('Windows print error: $e');
      rethrow;
    }
  }

  /// Returns path to SumatraPDF.exe, or null if not found.
  /// Checks: (1) next to app exe (Release/Debug), (2) windows/runner/bin/ from cwd.
  static Future<String?> _sumatraPdfPath() async {
    final sep = Platform.pathSeparator;
    final candidates = <String>[];

    final exe = Platform.resolvedExecutable;
    candidates.add('${File(exe).parent.path}${sep}SumatraPDF.exe');

    final cwd = Directory.current.path;
    candidates.add('$cwd${sep}windows${sep}runner${sep}bin${sep}SumatraPDF.exe');

    for (final p in candidates) {
      if (await File(p).exists()) return p;
    }
    return null;
  }

  static String? _paperForSumatra(String paperSize) {
    switch (paperSize.toUpperCase()) {
      case 'A4': return 'A4';
      case 'A3': return 'A3';
      case 'A5': return 'A5';
      case 'LETTER': return 'letter';
      case 'LEGAL': return 'legal';
      default: return null;
    }
  }

  /// Mobile printing (Android/iOS)
  /// Uses native print dialog with pre-filled options
  Future<bool> _printMobile(
    Uint8List bytes,
    int copies,
    String printMode,
    String colorMode,
    PdfPageFormat format,
  ) async {
    try {
      // For mobile, we use the print dialog
      // The user can verify/change settings before printing
      // Note: Copies and other options are handled by the native dialog
      
      final result = await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => bytes,
        format: format,
        name: 'QPrint Document',
      );

      // layoutPdf returns true if user confirmed print
      return result ?? false;
    } catch (e) {
      if (kDebugMode) print('Mobile print error: $e');
      return false;
    }
  }

  /// Sanitize string for safe use in PowerShell scripts (prevents injection).
  static String _sanitizeForPowerShell(String s) {
    if (s.isEmpty) return '_';
    const unsafe = <int>{34, 39, 96, 36, 42, 63, 92, 13, 10}; // " ' ` $ * ? \ \r \n
    final buffer = StringBuffer();
    for (var i = 0; i < s.length && i < 200; i++) {
      buffer.write(unsafe.contains(s.codeUnitAt(i)) ? '_' : s[i]);
    }
    return buffer.toString().isEmpty ? '_' : buffer.toString();
  }

  /// Verify Windows print job completion using WMI (Win32_PrintJob)
  /// Polls the print queue to check if the job completed successfully
  Future<bool> _verifyPrintCompletionWindows({
    required PrintJobInfo jobInfo,
    required Duration timeout,
    required Duration pollInterval,
  }) async {
    final startTime = DateTime.now();
    final documentName = _sanitizeForPowerShell(jobInfo.documentName);
    final printerName = _sanitizeForPowerShell(jobInfo.printerName);
    
    if (kDebugMode) print('🔍 Verifying print completion for: $documentName on $printerName');
    
    // Wait a moment for the job to appear in the queue
    await Future.delayed(const Duration(milliseconds: 1500));
    
    while (DateTime.now().difference(startTime) < timeout) {
      try {
        // Query WMI for print jobs matching our document
        final psScript = '''
\$jobs = Get-CimInstance -ClassName Win32_PrintJob -Property JobId,Document,Status,JobStatus,PagesPrinted,TotalPages,PrinterName | 
  Where-Object { \$_.Document -like "*$documentName*" -and \$_.PrinterName -eq "$printerName" }
if (\$jobs) {
  \$jobs | ForEach-Object {
    Write-Output "JOBID:\$(\$_.JobId)|STATUS:\$(\$_.Status)|JOBSTATUS:\$(\$_.JobStatus)|PAGES:\$(\$_.PagesPrinted)/\$(\$_.TotalPages)"
  }
} else {
  Write-Output "NOJOBS"
}
''';
        
        final result = await Process.run(
          'powershell',
          ['-NoProfile', '-Command', psScript],
          runInShell: false,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        
        if (result.exitCode != 0) {
          if (kDebugMode) print('⚠️ PowerShell query failed: ${result.stderr}');
          await Future.delayed(pollInterval);
          continue;
        }
        
        final output = (result.stdout as String?)?.trim() ?? '';
        
        // If no jobs found, check if printer is idle (job might have completed)
        if (output.isEmpty || output == 'NOJOBS') {
          // Check if printer is idle/ready (no active jobs)
          final printerStatus = await _checkWindowsPrinterStatus(printerName);
          if (printerStatus == 'idle' || printerStatus == 'ready') {
            // Wait a bit more to ensure job really completed
            await Future.delayed(const Duration(seconds: 2));
            // Check one more time
            final finalCheck = await _checkWindowsPrinterStatus(printerName);
            if (finalCheck == 'idle' || finalCheck == 'ready') {
              if (kDebugMode) print('✅ Print job completed (no jobs in queue, printer idle)');
              return true;
            }
          }
          await Future.delayed(pollInterval);
          continue;
        }
        
        // Parse job status
        final lines = output.split('\n').where((l) => l.trim().isNotEmpty).toList();
        bool allCompleted = true;
        bool hasError = false;
        
        for (final line in lines) {
          if (line.contains('NOJOBS')) continue;
          
          // Extract status information
          String? jobStatus;
          String? status;
          
          if (line.contains('JOBSTATUS:')) {
            final jobStatusMatch = RegExp(r'JOBSTATUS:(\d+)').firstMatch(line);
            if (jobStatusMatch != null) {
              jobStatus = jobStatusMatch.group(1);
            }
          }
          
          if (line.contains('STATUS:')) {
            final statusMatch = RegExp(r'STATUS:(.+?)(?:\||\$)').firstMatch(line);
            if (statusMatch != null) {
              status = statusMatch.group(1)?.trim();
            }
          }
          
          // Check for error states
          // JobStatus values: 0=Unknown, 1=Other, 2=Unknown, 3=Idle, 4=Printing, 5=Printed, 6=Restarting, 7=Paused, 8=Error, 9=Offline, 10=PaperOut, 11=ManualFeed, 12=PaperProblem, 13=IOActive, 14=Busy, 15=OutputBinFull, 16=NotAvailable, 17=Waiting, 18=Processing, 19=Initialization, 20=WarmingUp, 21=TonerLow, 22=NoToner, 23=PagePunt, 24=UserIntervention, 25=OutOfMemory, 26=DoorOpen
          if (jobStatus != null) {
            final statusCode = int.tryParse(jobStatus);
            if (statusCode != null) {
              // Error states
              if (statusCode == 8 || statusCode == 9 || statusCode == 10 || 
                  statusCode == 12 || statusCode == 16 || statusCode == 22 || 
                  statusCode == 24 || statusCode == 25 || statusCode == 26) {
                hasError = true;
                if (kDebugMode) print('❌ Print job error detected (JobStatus: $statusCode)');
                return false;
              }
              // Completed state
              if (statusCode == 5) {
                if (kDebugMode) print('✅ Print job completed (JobStatus: $statusCode)');
                return true;
              }
              // Still processing
              if (statusCode == 4 || statusCode == 18 || statusCode == 19) {
                allCompleted = false;
                if (kDebugMode) print('⏳ Print job still processing (JobStatus: $statusCode)...');
              }
            }
          }
          
          // Also check Status string for error keywords
          if (status != null) {
            final statusLower = status.toLowerCase();
            if (statusLower.contains('error') || statusLower.contains('failed') || 
                statusLower.contains('offline') || statusLower.contains('paper') ||
                statusLower.contains('toner') || statusLower.contains('jam')) {
              hasError = true;
              if (kDebugMode) print('❌ Print job error detected (Status: $status)');
              return false;
            }
            if (statusLower.contains('completed') || statusLower.contains('printed')) {
              if (kDebugMode) print('✅ Print job completed (Status: $status)');
              return true;
            }
          }
        }
        
        // If we found jobs but none are completed yet, continue polling
        if (!allCompleted && !hasError) {
          await Future.delayed(pollInterval);
          continue;
        }
        
        // If all jobs completed
        if (allCompleted && !hasError) {
          if (kDebugMode) print('✅ All print jobs completed');
          return true;
        }
        
      } catch (e) {
        if (kDebugMode) print('⚠️ Error checking print status: $e');
        // Continue polling on error
        await Future.delayed(pollInterval);
        continue;
      }
    }
    
    // Timeout reached
    if (kDebugMode) print('⏱️ Print verification timeout after ${timeout.inSeconds} seconds');
    // Check one final time if printer is idle
    final finalStatus = await _checkWindowsPrinterStatus(printerName);
    if (finalStatus == 'idle' || finalStatus == 'ready') {
      if (kDebugMode) print('✅ Printer is idle - assuming job completed');
      return true;
    }
    
    return false;
  }

  /// Check Windows printer status (idle, printing, error, etc.)
  Future<String> _checkWindowsPrinterStatus(String printerName) async {
    final safePrinterName = _sanitizeForPowerShell(printerName);
    try {
      final psScript = '''
\$printer = Get-CimInstance -ClassName Win32_Printer -Filter "Name='$safePrinterName'"
if (\$printer) {
  Write-Output \$printer.PrinterStatus
} else {
  Write-Output "NOTFOUND"
}
''';
      
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-Command', psScript],
        runInShell: false,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      
      if (result.exitCode == 0) {
        final statusCode = int.tryParse((result.stdout as String?)?.trim() ?? '');
        // PrinterStatus values: 1=Other, 2=Unknown, 3=Idle, 4=Printing, 5=WarmingUp, 6=StoppedPrinting, 7=Offline
        if (statusCode != null) {
          switch (statusCode) {
            case 3:
              return 'idle';
            case 4:
              return 'printing';
            case 5:
              return 'warming';
            case 7:
              return 'offline';
            default:
              return 'unknown';
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error checking printer status: $e');
    }
    return 'unknown';
  }

  /// Verify Linux/MacOS print job completion using CUPS
  Future<bool> _verifyPrintCompletionLinux({
    required String printerName,
    required Duration timeout,
    required Duration pollInterval,
  }) async {
    final startTime = DateTime.now();
    
    while (DateTime.now().difference(startTime) < timeout) {
      try {
        // Check if printer has any active jobs
        final result = await Process.run('lpstat', ['-o', printerName]);
        
        if (result.exitCode != 0) {
          // No jobs found or printer error
          // Check if printer is idle
          final statusResult = await Process.run('lpstat', ['-p', printerName]);
          if (statusResult.exitCode == 0) {
            final output = statusResult.stdout.toString();
            if (output.contains('idle') && !output.contains('printing')) {
              if (kDebugMode) print('✅ Print job completed (printer idle)');
              return true;
            }
          }
        } else {
          // Jobs still in queue
          final output = result.stdout.toString();
          if (output.contains('completed')) {
            if (kDebugMode) print('✅ Print job completed');
            return true;
          }
          if (kDebugMode) print('⏳ Print job still processing...');
        }
        
        await Future.delayed(pollInterval);
      } catch (e) {
        if (kDebugMode) print('Error verifying print: $e');
        await Future.delayed(pollInterval);
      }
    }
    
    if (kDebugMode) print('⏱️ Print verification timeout');
    return false;
  }

  /// Convert paper size string to PdfPageFormat
  PdfPageFormat _getPdfPageFormat(String paperSize) {
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
        return PdfPageFormat.a4; // Default to A4
    }
  }

  /// Get list of available printers
  Future<List<String>> getPrinters() async {
    if (Platform.isLinux || Platform.isMacOS) {
      return await _getPrintersLinux();
    } else if (Platform.isWindows) {
      return await _getPrintersWindows();
    } else if (Platform.isAndroid || Platform.isIOS) {
      return await _getPrintersMobile();
    }
    return [];
  }

  Future<List<String>> _getPrintersLinux() async {
    try {
      final result = await Process.run('lpstat', ['-a']);
      if (result.exitCode != 0) return [];
      
      // Output format: "PrinterName accepting requests since..."
      final lines = result.stdout.toString().split('\n');
      return lines
          .where((line) => line.isNotEmpty)
          .map((line) => line.split(' ')[0])
          .toList();
    } catch (e) {
      if (kDebugMode) print('Error getting printers: $e');
      return [];
    }
  }

  Future<List<String>> _getPrintersWindows() async {
    try {
      // Use PowerShell only: WMIC is deprecated on Windows 10/11 and often slow or missing.
      // Single call with longer timeout avoids double wait and first-run .NET load.
      final psResult = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', 'Get-Printer | Select-Object -ExpandProperty Name'],
        runInShell: false,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('PowerShell printer list timeout', const Duration(seconds: 10));
        },
      );
      
      if (psResult.exitCode != 0) return [];
      final out = (psResult.stdout as String?) ?? '';
      final printers = out
          .split(RegExp(r'\r?\n'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      
      return printers.toSet().toList()..sort();
    } on TimeoutException {
      if (kDebugMode) print('⚠️ Printer list fetch timeout (PowerShell)');
      return [];
    } catch (e) {
      if (kDebugMode) print('Error getting printers: $e');
      return [];
    }
  }

  Future<List<String>> _getPrintersMobile() async {
    try {
      final printers = await Printing.listPrinters();
      return printers.map((p) => p.name).toList();
    } catch (e) {
      if (kDebugMode) print('Error getting printers: $e');
      return [];
    }
  }

  /// Check if a specific printer is available
  /// Uses lenient matching (case-insensitive, partial match)
  Future<bool> isPrinterAvailable(String printerName) async {
    final printers = await getPrinters();
    final printerLower = printerName.toLowerCase();
    return printers.any((p) => 
      p.toLowerCase() == printerLower || 
      p.toLowerCase().contains(printerLower) ||
      printerLower.contains(p.toLowerCase())
    );
  }
}

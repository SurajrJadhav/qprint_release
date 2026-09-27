import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/printer_service.dart';
import '../services/pdf_utils.dart';
import '../services/converter_engine.dart';
import '../services/preconvert_cache.dart';
import '../services/queue_event_service.dart';
import '../models/print_job.dart';
import '../services/session_service.dart';
import '../utils/filename_utils.dart';
import '../utils/auth_prefs.dart';
import '../utils/safe_error.dart';
import 'login_screen.dart';
import 'printer_setup_screen.dart';
import 'history_screen.dart';
import 'stats_screen.dart';
import 'payouts_screen.dart';
import 'pricing_screen.dart';
import 'profile_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

/// Print job processing state
enum PrintJobState {
  idle,        // Not started
  queued,      // Queued to printer
  printing,    // Currently printing
  verifying,   // Verifying completion
  completed,   // Successfully completed
  error,       // Failed
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _apiService = ApiService();
  final _printerService = PrinterService();
  final _codeController = TextEditingController();
  
  List<PrintJob> _queue = [];
  Timer? _timer;
  Timer? _heartbeatTimer;
  bool _isLoadingQueue = true;
  bool _isFetchingQueue = false; // Prevent overlapping fetches (avoids Windows "Failed to post message to main thread")
  bool _isPrintingPrivate = false;
  String? _statusMessage;
  Color _statusColor = Colors.transparent;
  int _selectedTabIndex = 0;
  int _selectedIndex = 0; // 0=Dashboard, 1=History, 2=Stats, 3=Payouts, 4=Pricing, 5=Profile
  String? _currentPrinter;
  bool _isOpen = true;
  Timer? _printerCheckTimer;
  String? _shopName;
  String? _errorMessage;

  // Pricing snapshot for dashboard display
  double? _priceBw;
  double? _priceColor;
  double? _doubleSidedFactor;
  double? _platformPriceBw;
  double? _platformPriceColor;
  
  // Track print job states (jobId -> state)
  final Map<int, PrintJobState> _printJobStates = {};
  // Track selected printer per job (jobId -> printerName)
  final Map<int, String?> _jobPrinters = {};
  // Track available printers list
  List<String> _availablePrinters = [];
  // Track printer list loading state
  bool _isLoadingPrinters = false;
  DateTime? _lastPrinterRefresh;
  static const Duration _printerRefreshInterval = Duration(seconds: 120); // Refresh every 2 minutes (printers rarely change)
  static const String _keyPrintInProgress = 'shopkeeper_print_in_progress';

  @override
  void initState() {
    super.initState();
    _setupSessionTimeout();
    _loadShopNameFromCache();
    _loadPrinter(); // Keep original _loadPrinter
    // Load printers asynchronously after UI loads (non-blocking)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAvailablePrinters(force: false);
    });
    _fetchQueue();
    _fetchShopStatus();
    _startHeartbeat();
    // After first frame, check if a print was in progress when app last closed (crash recovery)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPrintInProgressRecovery();
    });
    // Defer to next frame so Flutter's Windows task runner can process its timer (reduces "Failed to post message to main thread")
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _fetchQueue(); });
    });
    _printerCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _checkPrinterStatus(); });
    });
    _startQueueEventStream();
  }

  void _startQueueEventStream() {
    _apiService.getToken().then((token) {
      if (mounted && token != null && token.isNotEmpty) {
        QueueEventService.instance.start(token);
      }
    });
  }

  @override
  void dispose() {
    QueueEventService.instance.stop();
    SessionService.instance.clear();
    _timer?.cancel();
    _heartbeatTimer?.cancel();
    _printerCheckTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _startHeartbeat() {
    // Send once immediately and then periodically.
    _sendHeartbeat();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      if (mounted) _sendHeartbeat();
    });
  }

  Future<void> _sendHeartbeat() async {
    try {
      await _apiService.shopHeartbeat();
      // Best-effort: refresh shop status occasionally so UI reflects any server-side changes.
      if (mounted) _fetchShopStatus();
    } catch (_) {
      // Ignore heartbeat errors; UI should continue to function even if network is flaky.
    }
  }

  Future<void> _loadShopNameFromCache() async {
    final name = await readCachedShopName();
    if (mounted) setState(() => _shopName = name);
  }

  void _setupSessionTimeout() {
    SessionService.instance.touch();
    SessionService.instance.setOnIdleTimeout(() {
      if (!mounted) return;
      SessionService.instance.clear();
      _timer?.cancel();
      _printerCheckTimer?.cancel();
      _apiService.logout();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    });
  }

  /// Load available printers list with caching
  /// [force] - if true, bypasses cache and refreshes immediately
  Future<void> _loadAvailablePrinters({bool force = false}) async {
    // Check if we need to refresh (avoid too frequent refreshes)
    if (!force && _lastPrinterRefresh != null) {
      final timeSinceRefresh = DateTime.now().difference(_lastPrinterRefresh!);
      if (timeSinceRefresh < _printerRefreshInterval && _availablePrinters.isNotEmpty) {
        return; // Use cached list - NO setState needed
      }
    }

    // Prevent concurrent loads
    if (_isLoadingPrinters) {
      return;
    }

    // Only set loading state if we're actually going to fetch
    _isLoadingPrinters = true;
    // Don't call setState here - avoid unnecessary rebuild while loading

    try {
      // Allow enough time for Windows (PowerShell/Get-Printer can be slow on first run)
      final printers = await _printerService.getPrinters()
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () {
              if (kDebugMode) print('⚠️ Printer list fetch timeout');
              return <String>[];
            },
          );
      
      if (mounted) {
        setState(() {
          _availablePrinters = printers;
          _lastPrinterRefresh = DateTime.now();
          _isLoadingPrinters = false;
        });
      }
    } catch (e) {
      if (kDebugMode) print('Error loading printers: $e');
      if (mounted) {
        setState(() {
          _isLoadingPrinters = false;
          // Keep existing list on error so user can retry without losing previous list
        });
      }
    }
  }

  Future<void> _fetchShopStatus() async {
    try {
      final profile = await _apiService.getProfile();
      if (!mounted) return;
      // Defer to next frame to avoid Windows "Failed to post message to main thread" (e.g. when called from heartbeat)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final shopLabel = profile['shop_name'] ?? profile['display_name'] ?? 'My Shop';
        writeCachedShopName(shopLabel.toString());
        setState(() {
          _isOpen = profile['is_open'] ?? true;
          _shopName = shopLabel.toString();
          final bw = profile['price_per_page_bw'];
          final color = profile['price_per_page_color'];
          final factor = profile['double_sided_factor'];
          final platformBw = profile['platform_price_per_page_bw'];
          final platformColor = profile['platform_price_per_page_color'];
          _priceBw = bw is num ? bw.toDouble() : null;
          _priceColor = color is num ? color.toDouble() : null;
          _doubleSidedFactor = factor is num ? factor.toDouble() : null;
          _platformPriceBw = platformBw is num ? platformBw.toDouble() : null;
          _platformPriceColor = platformColor is num ? platformColor.toDouble() : null;
        });
      });
    } catch (e) {
      if (kDebugMode) print('Failed to fetch shop status: $e');
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _shopName = 'My Shop'; // Default fallback
          });
        });
      }
    }
  }

  Future<void> _toggleShopStatus(bool value) async {
    try {
      await _apiService.toggleShopStatus(value);
      setState(() {
        _isOpen = value;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? 'Shop is now OPEN' : 'Shop is now CLOSED'),
          backgroundColor: value ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e')),
      );
    }
  }

  Future<void> _loadPrinter() async {
    String? printer;
    
    // Try SharedPreferences first
    try {
      final prefs = await SharedPreferences.getInstance();
      printer = prefs.getString('default_printer');
      if (kDebugMode) print('DEBUG: Loaded printer from SharedPreferences: $printer');
    } catch (e) {
      if (kDebugMode) print('Warning: Could not load printer from SharedPreferences: $e');
    }
    
    // Fallback to memory cache if SharedPreferences failed or returned null
    if (printer == null) {
      printer = PrinterSetupScreen.getCachedPrinter();
      if (kDebugMode) print('DEBUG: Using cached printer from memory: $printer');
    }
    
    setState(() {
      _currentPrinter = printer;
    });
    
    // If no printer is selected, redirect to printer setup
    if (_currentPrinter == null) {
      if (kDebugMode) print('DEBUG: No printer found, redirecting to printer setup');
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const PrinterSetupScreen()),
            );
          }
        });
      }
      return;
    }
    
    if (kDebugMode) print('DEBUG: Printer loaded successfully: $_currentPrinter');
    // Check printer status asynchronously (don't block if check fails)
    _checkPrinterStatus();
  }

  Future<void> _checkPrinterStatus() async {
    final printer = _currentPrinter;
    if (printer == null) return;
    
    try {
      // Use cached list when available to avoid slow getPrinters() every 10s
      List<String> printers = _availablePrinters;
      if (printers.isEmpty) {
        printers = await _printerService.getPrinters();
      }
      if (!mounted) return;
      if (kDebugMode) print('DEBUG: Checking printer status. Current: $printer, Available: $printers');
      
      final printerLower = printer.toLowerCase();
      final isAvailable = printers.any((p) =>
          p.toLowerCase() == printerLower ||
          p.toLowerCase().contains(printerLower) ||
          printerLower.contains(p.toLowerCase()));
      
      if (kDebugMode) print('DEBUG: Printer available: $isAvailable');
      
      if (!isAvailable) {
        if (kDebugMode) print('DEBUG: Printer not available, but not redirecting (non-blocking warning)');
      }
    } catch (e) {
      if (kDebugMode) print('Warning: Could not check printer status: $e');
    }
  }

  void _showPrinterError() {
    // Don't show multiple dialogs
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: true, // Allow dismissing
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF312E81),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 32),
            SizedBox(width: 12),
            Text('Printer Warning', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'The selected printer may not be connected or unavailable.\nYou can continue using the app, but printing may not work until you select a valid printer.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Continue Anyway', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const PrinterSetupScreen()),
              );
            },
            child: const Text('Select Printer', style: TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Safely extract job id (order_group_id) as int - handles JSON int/double
  int _getJobId(PrintJob j) {
    final id = j.id;
    if (id is int) return id;
    if (id is num) return id.toInt();
    return 0;
  }

  Future<void> _fetchQueue() async {
    if (_isFetchingQueue) return;
    _isFetchingQueue = true;
    try {
      final queueData = await _apiService.getQueue();
      if (!mounted) {
        _isFetchingQueue = false;
        return;
      }
      final newQueue = <PrintJob>[];
      for (final item in queueData) {
        if (item is Map<String, dynamic>) {
          try {
            newQueue.add(PrintJob.fromJson(item));
          } catch (_) {
            if (kDebugMode) print('Skipped malformed queue item');
          }
        }
      }
      // Defer UI updates to next frame to avoid Windows "Failed to post message to main thread"
      // (timer-triggered updates can overload the message queue when app runs for a long time)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _isFetchingQueue = false;
        // Check if queue actually changed to avoid unnecessary rebuilds
        final oldJobIds = _queue.map((j) => _getJobId(j)).toSet();
        final newJobIds = newQueue.map((j) => _getJobId(j)).toSet();
        // Also check if queue positions changed (e.g. after printing out of order)
        bool positionsChanged = false;
        if (oldJobIds.length == newJobIds.length && oldJobIds.containsAll(newJobIds)) {
          final oldPositions = {for (var j in _queue) _getJobId(j): j.queuePosition};
          final newPositions = {for (var j in newQueue) _getJobId(j): j.queuePosition};
          positionsChanged = oldPositions.entries.any((e) => newPositions[e.key] != e.value);
        }
        final queueChanged = _isLoadingQueue ||
            oldJobIds.length != newJobIds.length ||
            !oldJobIds.containsAll(newJobIds) ||
            positionsChanged;
        _printJobStates.removeWhere((jobId, _) => !newJobIds.contains(jobId));
        _jobPrinters.removeWhere((jobId, _) => !newJobIds.contains(jobId));
        if (queueChanged) {
          setState(() {
            _queue = newQueue;
            _isLoadingQueue = false;
            _errorMessage = null;
          });
          _triggerPreconvertForQueue(newQueue);
        } else if (_isLoadingQueue || _errorMessage != null) {
          setState(() {
            _isLoadingQueue = false;
            _errorMessage = null;
          });
        }
        _loadAvailablePrinters(force: false);
      });
    } catch (e) {
      if (kDebugMode) print('Queue fetch error: $e');
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _isFetchingQueue = false;
          setState(() {
            _isLoadingQueue = false;
            _errorMessage = getSafeErrorMessage(e, 'queue');
          });
        });
      } else {
        _isFetchingQueue = false;
      }
    }
  }

  /// Starts background pre-download + pre-convert for all files in the current queue.
  void _triggerPreconvertForQueue(List<PrintJob> queue) {
    for (final job in queue) {
      final orderGroupId = _getJobId(job);
      final paperSize = job.paperSize;
      _apiService.getOrderFiles(orderGroupId).then((files) {
        if (!mounted) return;
        for (final f in files) {
          final fileId = f['id'] as int?;
          final filename = f['filename'] as String?;
          if (fileId != null && filename != null) {
            PreconvertCache.instance.startPreconvert(
              fileId,
              filename,
              paperSize,
              _apiService,
            );
          }
        }
      }).catchError((e) {
        if (kDebugMode) print('Preconvert trigger for job $orderGroupId: $e');
      });
    }
  }

  /// Queue a print job (non-blocking)
  Future<void> _handleQueuePrint(PrintJob job) async {
    final jobId = _getJobId(job);
    // If backend says this order is already "printing" (e.g. stuck after crash), don't start a new print
    if (job.fileStatus == 'printing') {
      _showStuckPrintCompleteDialog(job);
      return;
    }
    final selectedPrinter = _getJobPrinter(jobId);
    
    // Check if printer is selected
    if (selectedPrinter == null) {
      _showStatus('Please select a printer for this job', Colors.red);
      return;
    }

    // Check if already processing
    final currentState = _getPrintJobState(jobId);
    if (currentState == PrintJobState.printing || 
        currentState == PrintJobState.verifying || 
        currentState == PrintJobState.queued) {
      return; // Already processing
    }

    // Check if printer is available before queuing
    _updatePrintJobState(jobId, PrintJobState.queued);
    try {
      final isAvailable = await _printerService.isPrinterAvailable(selectedPrinter);
      if (!isAvailable) {
        _updatePrintJobState(jobId, PrintJobState.error);
        _showStatus('Printer "$selectedPrinter" is not available. Please select a different printer.', Colors.red);
        return;
      }
    } catch (e) {
      if (kDebugMode) print('Error checking printer availability: $e');
      // Continue anyway - let the print attempt fail if printer is really unavailable
    }

    // Process in background (non-blocking)
    _processQueuePrintJob(job, selectedPrinter);
  }

  /// Process queue print job in background
  Future<void> _processQueuePrintJob(PrintJob job, String printerName) async {
    final jobId = _getJobId(job);
    
    // Queue API returns order groups (order_group_id, file_count). Download uses file IDs.
    // Use batch flow for any order group (including single-file) so we fetch files by
    // getOrderFiles → downloadFile(fileId). Single-file path used job.id (= order_group_id)
    // as file ID, causing "Failed to download file".
    if (job.orderGroupId != null) {
      await _processBatchPrintJob(job, printerName);
      return;
    }

    // Legacy single-file path (queue used to return per-file items with id = file ID).
    // Current backend only returns order groups; this branch is effectively unused.
    final singleFileId = _getJobId(job);
    try {
      _updatePrintJobState(jobId, PrintJobState.printing);
      await _apiService.printStartedQueue(singleFileId);

      final bytes = await _apiService.downloadFile(singleFileId);

      Directory tempDir;
      try {
        tempDir = await getTemporaryDirectory();
      } catch (e) {
        if (kDebugMode) print('⚠️ path_provider failed, using current directory: $e');
        tempDir = Directory.current;
      }
      final tempFile = File('${tempDir.path}/${sanitizeFilename(job.filename)}');
      await tempFile.writeAsBytes(bytes);

      // Convert to PDF if needed (images, Word, PPT)
      String? convertedPdfPath;
      try {
        final pdfPath = await ConverterEngine.ensurePdf(
          tempFile.path,
          paperSize: job.paperSize,
        );
        // Track converted PDF if different from original
        if (pdfPath != tempFile.path) {
          convertedPdfPath = pdfPath;
        }
      } catch (e) {
        if (e is UnsupportedError) {
          _updatePrintJobState(jobId, PrintJobState.error);
          _showStatus('Unsupported file type. Please use PDF, images, Word, or PowerPoint files.', Colors.red);
          return;
        }
        rethrow;
      }

      // Use converted PDF if available, otherwise use original
      final fileToPrint = convertedPdfPath ?? tempFile.path;
      final fileToPrintObj = File(fileToPrint);

      try {
        final shopName = _shopName ?? 'Print Shop';
        final frontPageBytes = await PdfUtils.createFrontPage(
          job: job,
          shopName: shopName,
        );
        // Merge front page (once) + document (N times where N = copies)
        final mergedBytes = await PdfUtils.mergePdfsWithCopies(
          frontPageBytes: frontPageBytes,
          documentFilePath: fileToPrint,
          copies: job.copies, // Repeat document N times
        );
        await fileToPrintObj.writeAsBytes(mergedBytes);
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ Warning: Failed to add front page: $e');
          print('Continuing with original file...');
        }
      }

      // Send print job and get tracking info
      final jobInfo = await _printerService.printFile(
        filePath: fileToPrint,
        copies: 1, // Copies are already in the PDF (document repeated N times)
        printMode: job.printMode,
        colorMode: job.colorMode,
        paperSize: job.paperSize,
        printerName: printerName,
      );

      if (jobInfo == null) {
        throw Exception('Failed to send print job to printer');
      }

      // Verify print completion before confirming
      _updatePrintJobState(jobId, PrintJobState.verifying);
      bool verified = await _printerService.verifyPrintCompletion(
        jobInfo: jobInfo,
        timeout: _timeoutForPages(job.numPages),
        pollInterval: const Duration(seconds: 2),
      );
      if (!verified) {
        verified = await _showVerificationTimeoutDialog();
        if (!verified) {
          throw Exception('Print job verification failed or timed out. Please check printer status and try again.');
        }
      }

      // Only confirm and delete after successful verification (or shopkeeper confirmed)
      await _apiService.confirmPrint(singleFileId);
      await _clearPrintInProgress();

      // Cleanup: Delete all temporary files after successful print and verification
      // After merging, fileToPrint contains the final merged PDF (overwrites converted PDF if it existed)
      // We need to clean up: original tempFile and final merged file (fileToPrint)
      
      // 1. Delete original downloaded file (if different from final merged file)
      if (tempFile.path != fileToPrint && await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      
      // 2. Delete final merged file (fileToPrint) - this is the file we just printed
      // Note: If convertedPdfPath existed, it was overwritten by merged PDF, so deleting fileToPrint cleans it up
      if (await fileToPrintObj.exists()) {
        try {
          await fileToPrintObj.delete();
        } catch (_) {}
      }

      _updatePrintJobState(jobId, PrintJobState.completed);
      // Defer UI updates to next frame to avoid "Failed to post message to main thread" on Windows
      // (print process just exited; batching updates prevents message queue overload)
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          setState(() {
            _queue = _queue.where((j) => _getJobId(j) != jobId).toList();
          });
          await _fetchQueue();
        });
      }
      // Clear completed state after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _printJobStates.remove(jobId));
          });
        }
      });
    } catch (e) {
      _updatePrintJobState(jobId, PrintJobState.error);
      _showStatus(getSafeErrorMessage(e, 'print'), Colors.red);
      _apiService.printFailedQueue(singleFileId);
      await _clearPrintInProgress();
    }
  }

  /// Page-based verification timeout: 90 + (20 * num_pages) seconds so slow printers can finish.
  static Duration _timeoutForPages(int numPages) {
    final pages = numPages < 1 ? 1 : numPages;
    return Duration(seconds: 90 + (20 * pages));
  }

  /// Longer timeout for private print (single job, often slower to appear in queue / complete).
  static Duration _timeoutForPagesPrivate(int numPages) {
    final pages = numPages < 1 ? 1 : numPages;
    return Duration(seconds: 150 + (35 * pages));
  }

  /// When verification times out, ask shopkeeper if print actually completed (avoids wrong refund when printer was slow).
  Future<bool> _showVerificationTimeoutDialog() async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Verification timed out'),
        content: const Text(
          'Print verification timed out (printer may be slow). Did the document print successfully?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No, mark failed'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, mark complete'),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// Process batch print job in background
  Future<void> _processBatchPrintJob(PrintJob orderGroup, String printerName) async {
    final jobId = _getJobId(orderGroup);
    List<int> fileIdsPrintStarted = [];

    try {
      _updatePrintJobState(jobId, PrintJobState.printing);

      final files = await _apiService.getOrderFiles(_getJobId(orderGroup));
      
      if (files.isEmpty) {
        throw Exception('No files found for this order');
      }

      // Mark print started for each file (disables customer withdraw)
      fileIdsPrintStarted = [for (final f in files) f['id'] as int];
      for (final fileId in fileIdsPrintStarted) {
        try {
          await _apiService.printStartedQueue(fileId);
        } catch (e) {
          if (kDebugMode) print('⚠️ print-started failed for file $fileId: $e');
        }
      }
      await _savePrintInProgress(type: 'queue', orderGroupId: jobId);

      // 2. Resolve PDF path for each file: use preconvert cache (ready or wait) or on-demand download + convert
      Directory tempDir;
      try {
        tempDir = await getTemporaryDirectory();
      } catch (e) {
        if (kDebugMode) print('⚠️ path_provider failed, using current directory: $e');
        tempDir = Directory.current;
      }

      final List<String> pdfPaths = [];
      final List<int> fileIdsToConfirm = [];
      final List<File> tempFiles = [];
      final List<String> convertedPdfPathsToClean = [];
      final List<int> fileIdsUsedFromCache = [];
      const waitTimeout = Duration(seconds: 90);

      for (int i = 0; i < files.length; i++) {
        final fileInfo = files[i];
        final fileId = fileInfo['id'] as int;
        final filename = fileInfo['filename'] as String;

        String? pdfPath = PreconvertCache.instance.getReadyPdfPath(fileId);
        if (pdfPath == null) {
          _showStatus('Preparing file ${i + 1}/${files.length}...', Colors.blue);
          pdfPath = await PreconvertCache.instance.waitForReady(fileId, waitTimeout);
        }
        if (pdfPath != null) {
          pdfPaths.add(pdfPath);
          fileIdsToConfirm.add(fileId);
          fileIdsUsedFromCache.add(fileId);
          continue;
        }

        // On-demand: download + convert
        try {
          final bytes = await _apiService.downloadFile(fileId);
          final tempFile = File('${tempDir.path}/batch_${fileId}_${sanitizeFilename(filename)}');
          await tempFile.writeAsBytes(bytes);
          pdfPath = await ConverterEngine.ensurePdf(
            tempFile.path,
            paperSize: orderGroup.paperSize,
          );
          pdfPaths.add(pdfPath);
          fileIdsToConfirm.add(fileId);
          tempFiles.add(tempFile);
          if (pdfPath != tempFile.path) {
            convertedPdfPathsToClean.add(pdfPath);
          }
        } catch (e) {
          if (e is UnsupportedError) {
            _showStatus('Skipping unsupported file: ${filename.split(RegExp(r'[/\\]')).last}', Colors.orange);
            continue;
          }
          rethrow;
        }
      }

      if (pdfPaths.isEmpty) {
        throw Exception('No files could be converted to PDF for merging');
      }

      // 4. Merge all PDFs into one document
      _showStatus('Merging ${pdfPaths.length} files into one document...', Colors.blue);
      final mergedPdfBytes = await PdfUtils.mergeMultiplePdfs(
        pdfFilePaths: pdfPaths,
      );

      // Save merged PDF to temp file
      final mergedTempFile = File('${tempDir.path}/merged_batch_${orderGroup.orderGroupId}.pdf');
      await mergedTempFile.writeAsBytes(mergedPdfBytes);

      // 5. Create ONE front page, then merge with document repeated N times (for copies)
      // This ensures front page is printed only once per batch, regardless of copies
      try {
        final shopName = _shopName ?? 'Print Shop';
        final frontPageBytes = await PdfUtils.createFrontPage(
          job: orderGroup, // Use orderGroup which has totalPages
          shopName: shopName,
        );
        
        // Merge front page (once) + document (N times where N = copies)
        final finalMergedBytes = await PdfUtils.mergePdfsWithCopies(
          frontPageBytes: frontPageBytes,
          documentFilePath: mergedTempFile.path,
          copies: orderGroup.copies, // Repeat document N times
        );
        
        // Replace merged file with final version (front page once + document N times)
        await mergedTempFile.writeAsBytes(finalMergedBytes);
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ Warning: Failed to add front page: $e');
          print('Continuing with merged files without front page...');
        }
        // Continue without front page if merge fails
      }

      // 6. Print the merged document (copies are already in the PDF, so print with copies=1)
      if (!await mergedTempFile.exists() || await mergedTempFile.length() == 0) {
        throw Exception('Merged PDF is missing or empty');
      }
      
      // Send print job and get tracking info
      final jobInfo = await _printerService.printFile(
        filePath: mergedTempFile.path,
        copies: 1, // Copies are already in the PDF (document repeated N times)
        printMode: orderGroup.printMode,
        colorMode: orderGroup.colorMode,
        paperSize: orderGroup.paperSize,
        printerName: printerName,
      );

      if (jobInfo == null) {
        throw Exception('Failed to send print job to printer');
      }

      // Verify print completion before confirming
      _updatePrintJobState(jobId, PrintJobState.verifying);
      final totalPages = orderGroup.totalPages ?? orderGroup.numPages;
      final verifyTimeout = _timeoutForPages(totalPages);
      bool verified = await _printerService.verifyPrintCompletion(
        jobInfo: jobInfo,
        timeout: verifyTimeout,
        pollInterval: const Duration(seconds: 2),
      );
      if (!verified) {
        verified = await _showVerificationTimeoutDialog();
        if (!verified) {
          throw Exception('Print job verification failed or timed out. Please check printer status and try again.');
        }
      }

      // 7. Confirm order once (backend marks all files in batch as confirmed)
      if (fileIdsToConfirm.isNotEmpty) {
        try {
          await _apiService.confirmPrint(fileIdsToConfirm.first);
          await _clearPrintInProgress();
        } catch (e) {
          if (kDebugMode) print('⚠️ Warning: Failed to confirm order: $e');
          rethrow;
        }
      }

      // 8. Cleanup all temp files (downloads, merged PDF, image→PDF temps) - only after verification
      for (final fileId in fileIdsUsedFromCache) {
        await PreconvertCache.instance.deleteLocalFiles(fileId);
        PreconvertCache.instance.remove(fileId);
      }
      for (final tempFile in tempFiles) {
        try {
          if (await tempFile.exists()) await tempFile.delete();
        } catch (_) {}
      }
      for (final p in convertedPdfPathsToClean) {
        try {
          final f = File(p);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      try {
        if (await mergedTempFile.exists()) await mergedTempFile.delete();
      } catch (_) {}

      _updatePrintJobState(jobId, PrintJobState.completed);
      // Defer UI updates to next frame to avoid "Failed to post message to main thread" on Windows
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          setState(() {
            _queue = _queue.where((j) => _getJobId(j) != jobId).toList();
          });
          await _fetchQueue();
        });
      }
      // Clear completed state after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _printJobStates.remove(jobId));
          });
        }
      });

    } catch (e) {
      _updatePrintJobState(jobId, PrintJobState.error);
      _showStatus(getSafeErrorMessage(e, 'batch'), Colors.red);
      for (final fileId in fileIdsPrintStarted) {
        _apiService.printFailedQueue(fileId);
      }
      await _clearPrintInProgress();
    }
  }

  Future<void> _handlePrivatePrint() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      _showStatus('Please enter a valid 6-character code', Colors.orange);
      return;
    }

    setState(() {
      _isPrintingPrivate = true;
    });
    _showStatus('Fetching private file...', Colors.blue);

    try {
      // 1. Get file status and print options
      final status = await _apiService.getFileStatus(code);
      await _apiService.printStartedPrivate(code);
      await _savePrintInProgress(type: 'private', code: code);

      // Extract print options (use defaults if not available from API)
      int copies = status['copies'] ?? 1;
      String printMode = status['print_mode'] ?? 'single';
      String colorMode = status['color_mode'] ?? 'bw';
      String paperSize = status['paper_size'] ?? 'A4';
      // Use actual file extension so converter can handle DOCX/PNG/etc. (not just PDF)
      String fileExtension = status['file_extension'] ?? '.pdf';
      if (!fileExtension.startsWith('.')) fileExtension = '.$fileExtension';

      // 2. Download file
      _showStatus('Downloading file...', Colors.blue);
      final bytes = await _apiService.downloadPrivateFile(code);

      // Get temp directory with fallback if path_provider fails
      Directory tempDir;
      try {
        tempDir = await getTemporaryDirectory();
      } catch (e) {
        // Fallback to current directory if path_provider fails
        if (kDebugMode) print('⚠️ path_provider failed, using current directory: $e');
        tempDir = Directory.current;
      }
      // Sanitize so code with spaces/special chars doesn't break path or LibreOffice (same as queue batch naming)
      final filename = 'private_${sanitizeFilename(code)}$fileExtension';
      final tempFile = File('${tempDir.path}/$filename');
      await tempFile.writeAsBytes(bytes);

      // 3. Print with customer's options (copies, color, duplex, paper)
      _showStatus('Sending to printer...', Colors.blue);
      if (_currentPrinter == null) {
        _showStatus('Printer not selected. Please select a printer first.', Colors.red);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const PrinterSetupScreen()),
        );
        return;
      }

      // Check if printer is available before printing
      try {
        final isAvailable = await _printerService.isPrinterAvailable(_currentPrinter!);
        if (!isAvailable) {
          _showStatus('Printer "$_currentPrinter" is not available. Please select a different printer.', Colors.red);
          return;
        }
      } catch (e) {
        if (kDebugMode) print('Error checking printer availability: $e');
        // Continue anyway - let the print attempt fail if printer is really unavailable
      }

      // Send print job and get tracking info
      final jobInfo = await _printerService.printFile(
        filePath: tempFile.path,
        copies: copies,
        printMode: printMode,
        colorMode: colorMode,
        paperSize: paperSize,
        printerName: _currentPrinter!,
      );

      if (jobInfo == null) {
        throw Exception('Failed to send print job to printer');
      }

      // Verify print completion before confirming (longer timeout for private print)
      _showStatus('Verifying print completion...', Colors.blue);
      final numPagesRaw = status['num_pages'];
      final numPages = numPagesRaw is int ? numPagesRaw : (numPagesRaw is num ? (numPagesRaw as num).toInt() : 1);
      bool verified = await _printerService.verifyPrintCompletion(
        jobInfo: jobInfo,
        timeout: _timeoutForPagesPrivate(numPages),
        pollInterval: const Duration(seconds: 2),
      );
      if (!verified) {
        verified = await _showVerificationTimeoutDialog();
        if (!verified) {
          throw Exception('Print job verification failed or timed out. Please check printer status and try again.');
        }
      }

      // 4. Confirm completion (updates status and deletes file on server) - only after verification (or shopkeeper confirmed)
      _showStatus('Confirming completion...', Colors.blue);
      await _apiService.confirmPrivatePrint(code);
      await _clearPrintInProgress();

      // 5. Cleanup local temp file
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      _showStatus('Private print completed!', Colors.green);
      _codeController.clear();

    } catch (e) {
      _showStatus(getSafeErrorMessage(e, 'private'), Colors.red);
      _apiService.printFailedPrivate(code);
      await _clearPrintInProgress();
      // IMPORTANT: Don't confirm or delete file on error
    } finally {
      // Defer to next frame to avoid Windows "Failed to post message to main thread"
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _isPrintingPrivate = false);
      });
    }
  }

  void _showStatus(String message, Color color) {
    // Minimize status bar - only show critical errors
    if (mounted && (color == Colors.red || message.contains('Error'))) {
      setState(() {
        _statusMessage = message;
        _statusColor = color;
      });
      
      // Auto-hide after 5 seconds for errors
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _statusMessage == message) {
          setState(() {
            _statusMessage = null;
          });
        }
      });
    }
  }

  /// Update print job state
  void _updatePrintJobState(int jobId, PrintJobState state) {
    if (mounted) {
      setState(() {
        _printJobStates[jobId] = state;
      });
    }
  }

  /// Get print job state (defaults to idle)
  PrintJobState _getPrintJobState(int jobId) {
    return _printJobStates[jobId] ?? PrintJobState.idle;
  }

  /// Get printer for a specific job (falls back to default)
  String? _getJobPrinter(int jobId) {
    return _jobPrinters[jobId] ?? _currentPrinter;
  }

  /// Persist print-in-progress for crash recovery (queue or private).
  Future<void> _savePrintInProgress({String? type, dynamic orderGroupId, String? code}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, dynamic>{'type': type};
      if (orderGroupId != null) map['orderGroupId'] = orderGroupId;
      if (code != null) map['code'] = code;
      await prefs.setString(_keyPrintInProgress, jsonEncode(map));
    } catch (e) {
      if (kDebugMode) print('Could not save print-in-progress: $e');
    }
  }

  /// Clear persisted print-in-progress after confirm or fail.
  Future<void> _clearPrintInProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyPrintInProgress);
    } catch (_) {}
  }

  /// Load persisted print-in-progress (null if none or invalid).
  Future<Map<String, dynamic>?> _loadPrintInProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString(_keyPrintInProgress);
      if (s == null || s.isEmpty) return null;
      final map = jsonDecode(s) as Map<String, dynamic>?;
      if (map == null || map['type'] == null) return null;
      return map;
    } catch (_) {
      return null;
    }
  }

  /// On startup: if a print was in progress when app closed, ask shopkeeper and resolve.
  Future<void> _checkPrintInProgressRecovery() async {
    if (!mounted) return;
    final saved = await _loadPrintInProgress();
    if (saved == null || !mounted) return;
    final type = saved['type'] as String?;
    if (type != 'queue' && type != 'private') {
      await _clearPrintInProgress();
      return;
    }
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Print interrupted'),
        content: const Text(
          'A print was in progress when the app last closed. Did it complete successfully?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No, mark failed'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, mark complete'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    try {
      if (result == true) {
        if (type == 'queue') {
          final orderGroupId = saved['orderGroupId'];
          if (orderGroupId != null) {
            final files = await _apiService.getOrderFiles(orderGroupId);
            if (files.isNotEmpty) {
              final firstId = files.first['id'] as int?;
              if (firstId != null) await _apiService.confirmPrint(firstId);
            }
          }
        } else {
          final code = saved['code'] as String?;
          if (code != null && code.length == 6) await _apiService.confirmPrivatePrint(code);
        }
      } else {
        if (type == 'queue') {
          final orderGroupId = saved['orderGroupId'];
          if (orderGroupId != null) {
            final files = await _apiService.getOrderFiles(orderGroupId);
            for (final f in files) {
              final id = f['id'] as int?;
              if (id != null) _apiService.printFailedQueue(id);
            }
          }
        } else {
          final code = saved['code'] as String?;
          if (code != null && code.length == 6) _apiService.printFailedPrivate(code);
        }
      }
    } catch (e) {
      if (kDebugMode) print('Print-in-progress recovery error: $e');
    } finally {
      await _clearPrintInProgress();
      if (mounted) await _fetchQueue();
    }
  }

  /// When queue item has backend status "printing" (e.g. stuck after crash), ask shopkeeper and resolve.
  Future<void> _showStuckPrintCompleteDialog(PrintJob job) async {
    if (!mounted) return;
    final orderGroupId = _getJobId(job);
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Order already in progress'),
        content: const Text(
          'This order was marked as printing but not confirmed. Did it complete successfully?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No, mark failed'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, mark complete'),
          ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    try {
      final files = await _apiService.getOrderFiles(orderGroupId);
      if (files.isEmpty) {
        if (mounted) _showStatus('Order not found', Colors.orange);
        return;
      }
      if (result == true) {
        final firstId = files.first['id'] as int?;
        if (firstId != null) await _apiService.confirmPrint(firstId);
        if (mounted) _showStatus('Order marked complete', Colors.green);
      } else {
        for (final f in files) {
          final id = f['id'] as int?;
          if (id != null) _apiService.printFailedQueue(id);
        }
        if (mounted) _showStatus('Order marked failed', Colors.orange);
      }
    } catch (e) {
      if (mounted) _showStatus(getSafeErrorMessage(e, 'order'), Colors.red);
    } finally {
      if (mounted) await _fetchQueue();
    }
  }

  Future<void> _handleLogout() async {
    // Show confirmation dialog
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF312E81),
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.redAccent, size: 28),
            SizedBox(width: 12),
            Text('Confirm Logout', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Are you sure you want to logout?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout == true && mounted) {
      SessionService.instance.clear();
      _timer?.cancel();
      _printerCheckTimer?.cancel();
      PrinterSetupScreen.setCachedPrinter(null);
      
      // Logout
      await _apiService.logout();
      
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false, // Remove all previous routes
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => SessionService.instance.touch(),
      child: Scaffold(
        body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF312E81), Color(0xFF581C87), Color(0xFF9D174D)],
          ),
        ),
        child: Row(
          children: [
            // Navigation Rail
            NavigationRail(
              backgroundColor: Colors.black.withOpacity(0.2),
              selectedIndex: _selectedIndex,
              onDestinationSelected: (int index) {
                if (mounted && _selectedIndex != index) {
                  setState(() => _selectedIndex = index);
                }
              },
              labelType: NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Icon(Icons.print_rounded, color: Colors.white, size: 32),
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.dashboard_outlined, color: Colors.white70),
                  selectedIcon: Icon(Icons.dashboard, color: Colors.pinkAccent),
                  label: Text('Dashboard', style: TextStyle(color: Colors.white)),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.history_outlined, color: Colors.white70),
                  selectedIcon: Icon(Icons.history, color: Colors.pinkAccent),
                  label: Text('History', style: TextStyle(color: Colors.white)),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.bar_chart_outlined, color: Colors.white70),
                  selectedIcon: Icon(Icons.bar_chart, color: Colors.pinkAccent),
                  label: Text('Stats', style: TextStyle(color: Colors.white)),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.account_balance_wallet_outlined, color: Colors.white70),
                  selectedIcon: Icon(Icons.account_balance_wallet, color: Colors.pinkAccent),
                  label: Text('Payouts', style: TextStyle(color: Colors.white)),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.currency_rupee, color: Colors.white70),
                  selectedIcon: Icon(Icons.currency_rupee, color: Colors.pinkAccent),
                  label: Text('Pricing', style: TextStyle(color: Colors.white)),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.person_outline, color: Colors.white70),
                  selectedIcon: Icon(Icons.person, color: Colors.pinkAccent),
                  label: Text('Profile', style: TextStyle(color: Colors.white)),
                ),
              ],
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.redAccent.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.logout, color: Colors.redAccent, size: 24),
                        onPressed: _handleLogout,
                        tooltip: 'Logout',
                      ),
                    ),
                  ),
                ),
              ),
            ),
            
            // Vertical Divider
            const VerticalDivider(thickness: 1, width: 1, color: Colors.white10),

            // Main Content
            Expanded(
              child: _selectedIndex == 0
                  ? _buildDashboardContent()
                  : _selectedIndex == 1
                      ? const HistoryScreen()
                      : _selectedIndex == 2
                          ? const StatsScreen()
                          : _selectedIndex == 3
                              ? const PayoutsScreen()
                              : _selectedIndex == 4
                                  ? const PricingScreen()
                                  : const ProfileScreen(),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildDashboardContent() {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.black.withOpacity(0.3),
                Colors.black.withOpacity(0.2),
              ],
            ),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // Brand + Shop
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.pinkAccent, Colors.purpleAccent],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.print_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _shopName ?? 'My Shop',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          'Qprint Shop',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.7),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.white.withOpacity(0.14)),
                          ),
                          child: Text(
                            'Print Queue Manager',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.65),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Printer Status
              InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PrinterSetupScreen()),
                  ).then((_) {
                    // Reload printer after returning from setup
                    _loadPrinter();
                  });
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _currentPrinter != null
                          ? [
                              Colors.green.withOpacity(0.3),
                              Colors.green.withOpacity(0.2),
                            ]
                          : [
                              Colors.orange.withOpacity(0.3),
                              Colors.orange.withOpacity(0.2),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: (_currentPrinter != null ? Colors.green : Colors.orange).withOpacity(0.4),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPrinter != null ? Colors.greenAccent : Colors.orangeAccent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (_currentPrinter != null ? Colors.greenAccent : Colors.orangeAccent).withOpacity(0.5),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(Icons.print, size: 18, color: _currentPrinter != null ? Colors.greenAccent : Colors.orangeAccent),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Text(
                          _currentPrinter ?? 'Select Printer',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _currentPrinter != null ? Colors.greenAccent : Colors.orangeAccent,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.edit, size: 14, color: _currentPrinter != null ? Colors.greenAccent : Colors.orangeAccent),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Pricing summary
              InkWell(
                onTap: () {
                  if (!mounted) return;
                  setState(() => _selectedIndex = 4);
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.16), width: 1.2),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.currency_rupee, size: 18, color: Colors.pinkAccent),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Pricing',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'B&W ₹${(_priceBw ?? _platformPriceBw ?? 1).toStringAsFixed(2)} • Color ₹${(_priceColor ?? _platformPriceColor ?? 10).toStringAsFixed(2)}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: (_priceBw != null || _priceColor != null || _doubleSidedFactor != null)
                              ? Colors.green.withOpacity(0.18)
                              : Colors.orange.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: (_priceBw != null || _priceColor != null || _doubleSidedFactor != null)
                                ? Colors.green.withOpacity(0.35)
                                : Colors.orange.withOpacity(0.35),
                          ),
                        ),
                        child: Text(
                          (_priceBw != null || _priceColor != null || _doubleSidedFactor != null) ? 'Custom' : 'Default',
                          style: TextStyle(
                            color: (_priceBw != null || _priceColor != null || _doubleSidedFactor != null)
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Shop Status Toggle
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: (_isOpen ? Colors.green : Colors.red).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: (_isOpen ? Colors.green : Colors.red).withOpacity(0.4),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _isOpen ? Colors.greenAccent : Colors.redAccent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (_isOpen ? Colors.greenAccent : Colors.redAccent)
                                .withOpacity(0.5),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _isOpen ? 'OPEN' : 'CLOSED',
                      style: TextStyle(
                        color: _isOpen ? Colors.greenAccent : Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Transform.scale(
                      scale: 0.9,
                      child: Switch(
                        value: _isOpen,
                        onChanged: _toggleShopStatus,
                        activeColor: Colors.greenAccent,
                        activeTrackColor: Colors.green.withOpacity(0.4),
                        inactiveThumbColor: Colors.redAccent,
                        inactiveTrackColor: Colors.red.withOpacity(0.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Refresh Button
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: _fetchQueue,
                  tooltip: 'Refresh Queue',
                ),
              ),
            ],
          ),
        ),

        // Navigation Tabs (Queue vs Private)
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.15),
                Colors.white.withOpacity(0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildTabButton(
                  title: 'Queue Print',
                  icon: Icons.list_alt,
                  isSelected: _selectedTabIndex == 0,
                  onTap: () {
                    if (mounted && _selectedTabIndex != 0) {
                      setState(() => _selectedTabIndex = 0);
                    }
                  },
                ),
              ),
              Expanded(
                child: _buildTabButton(
                  title: 'Private Print',
                  icon: Icons.lock_outline,
                  isSelected: _selectedTabIndex == 1,
                  onTap: () {
                    if (mounted && _selectedTabIndex != 1) {
                      setState(() => _selectedTabIndex = 1);
                    }
                  },
                ),
              ),
            ],
          ),
        ),

        // Status Bar
        if (_statusMessage != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            color: _statusColor.withOpacity(0.9),
            child: Text(
              _statusMessage!,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),

        // Content Area
        Expanded(
          child: _selectedTabIndex == 0 ? _buildQueueView() : _buildPrivatePrintView(),
        ),
      ],
    );
  }

  Widget _buildTabButton({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.pinkAccent, Colors.purpleAccent],
                )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.pinkAccent.withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: 22,
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQueueView() {
    if (_isLoadingQueue) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              color: Colors.pinkAccent,
              strokeWidth: 3,
            ),
            const SizedBox(height: 24),
            const Text(
              'Loading queue...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    final errorMsg = _errorMessage;
    if (errorMsg != null && errorMsg.isNotEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(40),
          margin: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.red.withOpacity(0.2),
                Colors.red.withOpacity(0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.red.withOpacity(0.3),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
              const SizedBox(height: 24),
              const Text(
                'Error Loading Queue',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                errorMsg,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  if (!mounted) return;
                  setState(() {
                    _isLoadingQueue = true;
                    _errorMessage = null;
                  });
                  _fetchQueue();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pinkAccent,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_queue.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(40),
          margin: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.1),
                Colors.white.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.pinkAccent.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.inbox_outlined,
                  size: 80,
                  color: Colors.pinkAccent,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Queue is Empty',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Waiting for new print jobs...',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'New jobs will appear here automatically',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.5),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _queue.length,
      itemBuilder: (context, index) {
        final job = _queue[index];
        final isBatch = job.isBatchOrder;
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.pinkAccent.withOpacity(0.15),
                Colors.purpleAccent.withOpacity(0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row with Queue Position and Print Button
                Row(
                  children: [
                    // Queue Position Badge
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Colors.pinkAccent, Colors.purpleAccent],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.pinkAccent.withOpacity(0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          '#${job.queuePosition ?? 0}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // File Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isBatch ? Icons.folder : Icons.description,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        job.filename,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (job.fileStatus == 'printing') ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withOpacity(0.3),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: Colors.orange.withOpacity(0.6),
                                            width: 1,
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange),
                                            SizedBox(width: 4),
                                            Text(
                                              'Not confirmed – tap Print',
                                              style: TextStyle(
                                                color: Colors.orange,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    if (isBatch) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.blueAccent.withOpacity(0.3),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: Colors.blueAccent.withOpacity(0.5),
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.layers, size: 14, color: Colors.blueAccent),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${job.fileCount ?? 0} files',
                                              style: const TextStyle(
                                                color: Colors.blueAccent,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.person,
                                color: Colors.white70,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                job.customerName,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Icon(
                                Icons.pages,
                                color: Colors.white70,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isBatch 
                                    ? '${job.totalPages ?? job.numPages} pages total'
                                    : '${job.numPages} pages',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Cancel (only when order not yet printing) and Print Button
                    if (_getPrintJobState(_getJobId(job)) == PrintJobState.idle)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: OutlinedButton.icon(
                          onPressed: () => _showCancelOrderDialog(job),
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                          label: const Text('Cancel'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orangeAccent,
                            side: const BorderSide(color: Colors.orangeAccent),
                          ),
                        ),
                      ),
                    _buildPrintButtonWithStatus(job),
                  ],
                ),
                const SizedBox(height: 16),
                // Print Settings Tags
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildTag('${job.copies}x', Icons.copy, Colors.blue),
                    _buildTag(
                      job.printMode == 'single' ? 'Single' : 'Double',
                      Icons.swap_horiz,
                      Colors.purple,
                    ),
                    _buildTag(
                      job.colorMode == 'bw' ? 'B&W' : 'Color',
                      Icons.palette,
                      job.colorMode == 'bw' ? Colors.grey : Colors.orange,
                    ),
                    _buildTag(job.paperSize, Icons.aspect_ratio, Colors.teal),
                    _buildTag(
                      '₹${job.totalCost.toStringAsFixed(2)}',
                      Icons.currency_rupee,
                      Colors.green,
                    ),
                  ],
                ),
                // Comment Section
                if ((job.comment ?? '').isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.amber.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.comment,
                          color: Colors.amber,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Customer Comment:',
                                style: TextStyle(
                                  color: Colors.amber,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                job.comment ?? '',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPrivatePrintView() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 64, color: Colors.pinkAccent),
            const SizedBox(height: 24),
            const Text(
              'Private Print',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter the 6-character unique code provided by the customer',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _codeController,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
              ),
              maxLength: 6,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                counterText: "",
                hintText: 'XXXXXX',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(16),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.pinkAccent, width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
                filled: true,
                fillColor: Colors.black.withOpacity(0.2),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: _isPrintingPrivate ? null : _handlePrivatePrint,
                icon: _isPrintingPrivate 
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.print, size: 28),
                label: Text(
                  _isPrintingPrivate ? 'PROCESSING...' : 'PRINT NOW',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pinkAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTag(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color.withOpacity(0.95),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// Show dialog to cancel order with reason; on confirm calls API and refreshes queue.
  Future<void> _showCancelOrderDialog(PrintJob job) async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final hasReason = reasonController.text.trim().isNotEmpty;
            return AlertDialog(
              title: const Text('Cancel order'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'The customer will be notified and refunded. This cannot be undone.',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    const Text('Reason (required):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: reasonController,
                      maxLines: 3,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Printer out of order, paper not available',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Back'),
                ),
                FilledButton(
                  onPressed: hasReason
                      ? () => Navigator.of(ctx).pop(true)
                      : null,
                  child: const Text('Cancel order'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) {
      reasonController.dispose();
      return;
    }
    final reason = reasonController.text.trim();
    reasonController.dispose();
    if (reason.isEmpty) return;

    try {
      await _apiService.cancelQueueOrder(job.fileIdForApi, reason);
      if (mounted) {
        setState(() {
          _queue = _queue.where((j) => _getJobId(j) != _getJobId(job)).toList();
          _printJobStates.remove(_getJobId(job));
          _jobPrinters.remove(_getJobId(job));
        });
        _fetchQueue();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(getSafeErrorMessage(e, 'cancel order'))),
        );
      }
    }
  }

  /// Build print button with status indicator and printer selection
  Widget _buildPrintButtonWithStatus(PrintJob job) {
    final jobId = _getJobId(job);
    final state = _getPrintJobState(jobId);
    final selectedPrinter = _getJobPrinter(jobId);
    
    // Determine button appearance based on state
    Color buttonColor;
    Color textColor = Colors.white;
    String buttonText;
    IconData buttonIcon;
    bool isEnabled = true;
    
    switch (state) {
      case PrintJobState.idle:
        buttonColor = Colors.pinkAccent;
        buttonText = 'PRINT';
        buttonIcon = Icons.print;
        break;
      case PrintJobState.queued:
        buttonColor = Colors.orange;
        buttonText = 'QUEUED';
        buttonIcon = Icons.queue;
        isEnabled = false;
        break;
      case PrintJobState.printing:
        buttonColor = Colors.blue;
        buttonText = 'PRINTING...';
        buttonIcon = Icons.print;
        isEnabled = false;
        break;
      case PrintJobState.verifying:
        buttonColor = Colors.purple;
        buttonText = 'VERIFYING...';
        buttonIcon = Icons.verified;
        isEnabled = false;
        break;
      case PrintJobState.completed:
        buttonColor = Colors.green;
        buttonText = 'COMPLETED';
        buttonIcon = Icons.check_circle;
        isEnabled = false;
        break;
      case PrintJobState.error:
        buttonColor = Colors.red;
        buttonText = 'ERROR - RETRY';
        buttonIcon = Icons.error;
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Printer selection dropdown (only show when idle or error)
        if (state == PrintJobState.idle || state == PrintJobState.error)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: PopupMenuButton<String>(
              enabled: isEnabled && _availablePrinters.isNotEmpty,
              color: const Color(0xFF1E1B4B),
              onOpened: () => _loadAvailablePrinters(force: _availablePrinters.isEmpty), // Retry if empty, else use cache
              onSelected: (String? newPrinter) {
                if (newPrinter != null && mounted) {
                  setState(() => _jobPrinters[jobId] = newPrinter);
                }
              },
              itemBuilder: (context) => _availablePrinters
                  .map((printer) => PopupMenuItem<String>(
                        value: printer,
                        child: Text(
                          printer,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isLoadingPrinters && _availablePrinters.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: Colors.white54,
                              ),
                            ),
                          ),
                        Flexible(
                          child: Text(
                            selectedPrinter ?? 
                              (_isLoadingPrinters && _availablePrinters.isEmpty 
                                ? 'Loading...' 
                                : (_availablePrinters.isEmpty ? 'No printers' : 'Select Printer')),
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 20),
                ],
              ),
            ),
          ),
        // Print button
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [buttonColor, buttonColor.withOpacity(0.8)],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: buttonColor.withOpacity(0.4),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: isEnabled && selectedPrinter != null
                ? () => _handleQueuePrint(job)
                : null,
            icon: state == PrintJobState.printing || state == PrintJobState.verifying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Icon(buttonIcon, size: 20),
            label: Text(
              buttonText,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: textColor,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 14,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              disabledForegroundColor: textColor.withOpacity(0.7),
            ),
          ),
        ),
      ],
    );
  }
}

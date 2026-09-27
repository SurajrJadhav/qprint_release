import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../theme/app_colors.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/razorpay_service.dart';
import '../utils/safe_error.dart';
import '../utils/shop_qr_parser.dart';
import 'widgets/shop_selection_widget.dart';
import 'shop_qr_scanner_screen.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({
    super.key,
    this.onUploadSuccess,
    this.initialShopId,
    this.initialSharedFilePaths,
  });

  /// Called after a successful upload (and any wallet/payment deductions).
  final VoidCallback? onUploadSuccess;
  /// When set (e.g. from app link or QR), pre-select this shop and switch to queue mode.
  final int? initialShopId;
  /// When the app is launched from Android's Share sheet, these are the
  /// absolute file paths that should be pre-populated into the upload list.
  final List<String>? initialSharedFilePaths;

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> with WidgetsBindingObserver {
  List<File> _selectedFiles = [];
  int _copies = 1;
  String _printMode = 'single';
  String _colorMode = 'bw';
  String _paperSize = 'A4';
  String _printType = 'queue';
  int? _selectedShopId;
  String _comment = '';
  bool _isUploading = false;
  String? _errorMessage;
  String? _successMessage;
  String? _uniqueCode;
  int? _queuePosition;

  final _apiService = ApiService();
  final _locationService = LocationService();
  final _razorpayService = RazorpayService();
  double? _userLat;
  double? _userLong;
  List<dynamic> _shops = [];
  bool _shopLoadError = false;
  bool _sessionExpired = false; // true when getShops returned 401
  bool _shopsLoading = false;
  bool _isProcessingPayment = false;
  
  // Estimated cost before upload
  double? _estimatedCost;
  int? _estimatedPages;
  bool _isCalculatingCost = false;
  /// Cached page count per file (same order as _selectedFiles). Used to avoid re-upload when only shop/print type changes.
  List<int> _pagesPerFile = [];
  /// Filename (from backend error) for which page count could not be calculated; show in list so user can remove it.
  String? _costErrorFileName;
  // Wallet: balance fetched when cost is known; used for payment method choice
  double? _walletBalance;
  bool _walletBalanceLoading = false;
  
  // TextEditingController for copies field
  late final TextEditingController _copiesController;
  final TextEditingController _shopCodeController = TextEditingController();

  // ScrollController for auto-scroll after shop selection
  late final ScrollController _scrollController;
  
  // Store payment settings to prevent reset before upload
  int? _storedCopies;
  String? _storedPrintMode;
  String? _storedColorMode;
  String? _storedPaperSize;
  String? _storedPrintType;
  int? _storedShopId;
  String? _storedComment;

  /// Refresh shop list periodically so open/closed status stays live (no app restart).
  Timer? _shopRefreshTimer;

  /// Applied once when initialShopId is provided (e.g. from app link).
  bool _appliedInitialShopId = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _copiesController = TextEditingController(text: _copies.toString());
    _scrollController = ScrollController();
    _loadDefaultPreferences();
    _getUserLocation();
    _razorpayService.init(); // Initialize Razorpay
    // Load shops immediately (don't wait for location); backend returns list with or without distance
    _loadShops();
    _shopRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) _loadShops();
    });
    // If opened from Android Share with initial files, pre-populate selection.
    if (widget.initialSharedFilePaths != null &&
        widget.initialSharedFilePaths!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _addInitialSharedFiles(widget.initialSharedFilePaths!);
      });
    }
    if (widget.initialShopId != null && !_appliedInitialShopId) {
      _appliedInitialShopId = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        setState(() {
          _selectedShopId = widget.initialShopId;
          _printType = 'queue';
        });
        await _ensureShopInList(widget.initialShopId!);
      });
    }
  }

  /// When opening from shop QR link, ensure the shop is in _shops so the dropdown shows its name.
  Future<void> _ensureShopInList(int shopId) async {
    if (_shops.any((s) => s['id'] == shopId)) return;
    try {
      final shop = await _apiService.getShopById(shopId);
      if (mounted) setState(() => _shops = [..._shops, shop]);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant UploadScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialShopId != null && widget.initialShopId != oldWidget.initialShopId && !_appliedInitialShopId) {
      _appliedInitialShopId = true;
      setState(() {
        _selectedShopId = widget.initialShopId;
        _printType = 'queue';
      });
      _ensureShopInList(widget.initialShopId!);
    }
    // If new shared files arrive while the screen is kept alive, merge them.
    if (widget.initialSharedFilePaths != null &&
        widget.initialSharedFilePaths!.isNotEmpty &&
        widget.initialSharedFilePaths != oldWidget.initialSharedFilePaths) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _addInitialSharedFiles(widget.initialSharedFilePaths!);
      });
    }
  }

  @override
  void dispose() {
    _shopRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _copiesController.dispose();
    _shopCodeController.dispose();
    _scrollController.dispose();
    _razorpayService.dispose(); // Clean up Razorpay
    super.dispose();
  }

  /// Parse QR/link string to shop id; validate with API and set selected shop. Do not open URL in browser.
  Future<void> _applyShopFromCodeOrScan(String raw) async {
    final shopId = parseShopIdFromQrContent(raw);
    if (shopId == null) {
      if (mounted) {
        setState(() => _errorMessage = 'Invalid shop code. Scan the shop\'s QR or enter a valid shop number.');
      }
      return;
    }
    try {
      final shop = await _apiService.getShopById(shopId);
      if (!mounted) return;
      setState(() {
        _errorMessage = null;
        _selectedShopId = shopId;
        _printType = 'queue';
        final inList = _shops.any((s) => s['id'] == shopId);
        if (!inList) {
          _shops = [..._shops, shop];
        }
      });
      _scrollToUploadSection();
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = getSafeErrorMessage(e, 'shop'));
      }
    }
  }

  void _scrollToUploadSection() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        final target = (_scrollController.position.pixels + 150).clamp(0.0, maxScroll);
        _scrollController.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _openShopQrScanner() async {
    final result = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => const ShopQrScannerScreen(),
    ));
    if (result != null && mounted) await _applyShopFromCodeOrScan(result);
  }

  Future<void> _submitShopCode() async {
    final code = _shopCodeController.text.trim();
    if (code.isEmpty) {
      setState(() => _errorMessage = 'Enter a shop code or scan the QR.');
      return;
    }
    await _applyShopFromCodeOrScan(code);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _loadDefaultPreferences();
      _loadShops();
    }
  }

  DateTime? _lastPreferenceReload;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload preferences when screen becomes visible (e.g., returning from profile)
    // But only if it's been more than 1 second since last reload to avoid excessive calls
    final now = DateTime.now();
    if (_lastPreferenceReload == null || 
        now.difference(_lastPreferenceReload!).inSeconds > 1) {
      _lastPreferenceReload = now;
      _loadDefaultPreferences();
    }
  }

  Future<void> _loadDefaultPreferences() async {
    // Don't reload preferences if we're in the middle of payment/upload
    // This prevents resetting values that were used for payment
    if (_isProcessingPayment || _isUploading || _storedCopies != null) {
      return;
    }
    
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _colorMode = prefs.getString('default_color_mode') ?? 'bw';
        _printMode = prefs.getString('default_print_mode') ?? 'single';
        _paperSize = prefs.getString('default_paper_size') ?? 'A4';
        _copies = prefs.getInt('default_copies') ?? 1;
        _copiesController.text = _copies.toString();
      });
    }
  }

  Future<void> _getUserLocation() async {
    try {
      final position = await _locationService.getCurrentPosition();
      setState(() {
        _userLat = position.latitude;
        _userLong = position.longitude;
      });
      _loadShops();
    } catch (e) {
      if (kDebugMode) debugPrint('Location error: $e');
      // Location not available, still try to load shops without location
      if (mounted) {
        _loadShops();
      }
    }
  }

  Future<void> _loadShops() async {
    final lat = _userLat ?? 0.0;
    final long = _userLong ?? 0.0;
    if (mounted) setState(() => _shopsLoading = true);
    try {
      final shops = await _apiService.getShops(lat, long);
      if (mounted) {
        setState(() {
          _shops = shops is List ? shops : [];
          _shopLoadError = false;
          _sessionExpired = false;
          _shopsLoading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading shops: $e');
      if (mounted) {
        setState(() {
          _shops = [];
          _shopLoadError = true;
          _sessionExpired = e.toString().contains('Session expired');
          _shopsLoading = false;
        });
      }
    }
  }

  static const _allowedExtensions = ['pdf', 'png', 'jpg', 'jpeg', 'doc', 'docx', 'ppt', 'pptx'];
  static const _supportedMsg = 'Supported: PDF, images (PNG/JPG/JPEG), Word (DOC/DOCX), PowerPoint (PPT/PPTX)';

  Future<void> _addInitialSharedFiles(List<String> paths) async {
    if (paths.isEmpty) return;
    const maxFileSize = 20 * 1024 * 1024; // 20MB per file
    const maxGroupSize = 100 * 1024 * 1024; // 100MB total

    int currentTotalSize = 0;
    for (final file in _selectedFiles) {
      currentTotalSize += await file.length();
    }

    final newFiles = <File>[];

    for (final rawPath in paths) {
      final file = File(rawPath);
      if (!await file.exists()) {
        continue;
      }

      final fileSize = await file.length();
      if (fileSize > maxFileSize) {
        setState(() {
          _errorMessage =
              'File "$rawPath" exceeds maximum limit of 20MB per file.';
        });
        continue;
      }
      if (currentTotalSize + fileSize > maxGroupSize) {
        setState(() {
          _errorMessage =
              'Adding "$rawPath" would exceed the 100MB total limit.';
        });
        continue;
      }

      // Magic-bytes validation so we accept real PDFs/images even if
      // the provider's filename has no or wrong extension.
      try {
        final header = await file.openRead(0, 16).first;
        final isPdf = header.length >= 5 &&
            header[0] == 0x25 &&
            header[1] == 0x50 &&
            header[2] == 0x44 &&
            header[3] == 0x46 &&
            header[4] == 0x2D; // %PDF-
        final isPng = header.length >= 8 &&
            header[0] == 0x89 &&
            header[1] == 0x50 &&
            header[2] == 0x4e &&
            header[3] == 0x47 &&
            header[4] == 0x0d &&
            header[5] == 0x0a &&
            header[6] == 0x1a &&
            header[7] == 0x0a; // PNG
        final isJpeg = header.length >= 3 &&
            header[0] == 0xff &&
            header[1] == 0xd8 &&
            header[2] == 0xff; // JPEG
        // DOCX/PPTX: ZIP (PK)
        final isDocxOrPptx = header.length >= 4 &&
            header[0] == 0x50 &&
            header[1] == 0x4b; // PK
        // DOC/PPT: OLE
        final isDocOrPpt = header.length >= 8 &&
            header[0] == 0xD0 &&
            header[1] == 0xCF &&
            header[2] == 0x11 &&
            header[3] == 0xE0;

        if (!isPdf && !isPng && !isJpeg && !isDocxOrPptx && !isDocOrPpt) {
          setState(() {
            _errorMessage = 'File "$rawPath": $_supportedMsg';
          });
          continue;
        }
      } catch (_) {
        setState(() {
          _errorMessage = 'Could not read "$rawPath". Please try again.';
        });
        continue;
      }

      newFiles.add(file);
      currentTotalSize += fileSize;
    }

    if (newFiles.isNotEmpty) {
      setState(() {
        _selectedFiles.addAll(newFiles);
        _errorMessage = null;
      });
      _calculateEstimatedCost();
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedExtensions,
        allowMultiple: true, // Enable multiple file selection
      );

      if (result != null && result.files.isNotEmpty) {
        const maxFileSize = 20 * 1024 * 1024; // 20MB per file
        const maxGroupSize = 100 * 1024 * 1024; // 100MB total
        
        // Calculate current total size
        int currentTotalSize = 0;
        for (final file in _selectedFiles) {
          currentTotalSize += await file.length();
        }
        
        final newFiles = <File>[];
        
        for (final platformFile in result.files) {
          if (platformFile.path == null) continue;
          
          final name = platformFile.name.toLowerCase();
          if (!_allowedExtensions.any((e) => name.endsWith('.$e'))) {
            setState(() {
              _errorMessage = 'File "${platformFile.name}": $_supportedMsg';
            });
            continue;
          }
          
          final file = File(platformFile.path!);
          final fileSize = await file.length();
          
          // Validate individual file size
          if (fileSize > maxFileSize) {
            setState(() {
              _errorMessage = 'File "${platformFile.name}" exceeds maximum limit of 20MB per file. Size: ${(fileSize / (1024 * 1024)).toStringAsFixed(2)}MB';
            });
            continue;
          }
          
          // Validate total group size
          if (currentTotalSize + fileSize > maxGroupSize) {
            setState(() {
              _errorMessage = 'Adding "${platformFile.name}" would exceed the 100MB total limit. Current total: ${(currentTotalSize / (1024 * 1024)).toStringAsFixed(2)}MB';
            });
            continue;
          }

          // Magic-bytes check: reject renamed or wrong-type files early
          try {
            if (name.endsWith('.pdf')) {
              final bytes = await file.openRead(0, 5).first;
              const pdfMagic = [0x25, 0x50, 0x44, 0x46, 0x2D]; // %PDF-
              if (bytes.length < 5 ||
                  !List.generate(5, (i) => bytes[i] == pdfMagic[i]).every((e) => e)) {
                setState(() {
                  _errorMessage = 'File "${platformFile.name}" does not appear to be a valid PDF. Please choose a valid PDF file.';
                });
                continue;
              }
            } else if (name.endsWith('.png')) {
              final bytes = await file.openRead(0, 8).first;
              const pngMagic = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]; // PNG
              if (bytes.length < 8 ||
                  !List.generate(8, (i) => bytes[i] == pngMagic[i]).every((e) => e)) {
                setState(() {
                  _errorMessage = 'File "${platformFile.name}" does not appear to be a valid PNG. Please choose a valid image file.';
                });
                continue;
              }
            } else if (name.endsWith('.jpg') || name.endsWith('.jpeg')) {
              final bytes = await file.openRead(0, 3).first;
              const jpegMagic = [0xff, 0xd8, 0xff]; // JPEG
              if (bytes.length < 3 ||
                  !List.generate(3, (i) => bytes[i] == jpegMagic[i]).every((e) => e)) {
                setState(() {
                  _errorMessage = 'File "${platformFile.name}" does not appear to be a valid JPEG. Please choose a valid image file.';
                });
                continue;
              }
            } else if (name.endsWith('.docx') || name.endsWith('.pptx')) {
              final bytes = await file.openRead(0, 4).first;
              if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4b) {
                setState(() {
                  _errorMessage = 'File "${platformFile.name}" does not appear to be a valid Word/PowerPoint file.';
                });
                continue;
              }
            } else if (name.endsWith('.doc') || name.endsWith('.ppt')) {
              final bytes = await file.openRead(0, 8).first;
              const oleMagic = [0xD0, 0xCF, 0x11, 0xE0];
              if (bytes.length < 4 ||
                  !List.generate(4, (i) => bytes[i] == oleMagic[i]).every((e) => e)) {
                setState(() {
                  _errorMessage = 'File "${platformFile.name}" does not appear to be a valid Word/PowerPoint file.';
                });
                continue;
              }
            }
          } catch (_) {
            setState(() {
              _errorMessage = 'Could not read "${platformFile.name}". Please try again.';
            });
            continue;
          }
          
          newFiles.add(file);
          currentTotalSize += fileSize;
        }
        
        if (newFiles.isNotEmpty) {
          setState(() {
            _selectedFiles.addAll(newFiles);
            _errorMessage = null;
          });
          _calculateEstimatedCost();
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to pick file. Please try again.';
      });
    }
  }
  
  void _removeFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
      _errorMessage = null;
    });
    _calculateEstimatedCost();
  }

  IconData _fileIcon(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return Icons.image;
    }
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) return Icons.description;
    if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) return Icons.slideshow;
    return Icons.description;
  }
  
  Future<void> _calculateEstimatedCost() async {
    if (_selectedFiles.isEmpty) {
      setState(() {
        _estimatedCost = null;
        _estimatedPages = null;
        _pagesPerFile = [];
        _costErrorFileName = null;
      });
      return;
    }

    // For queue prints, we need a shop to know pricing; defer cost
    // calculation until a shop is selected.
    if (_printType == 'queue' && _selectedShopId == null) {
      setState(() {
        _estimatedCost = null;
        _estimatedPages = null;
      });
      return;
    }

    setState(() {
      _isCalculatingCost = true;
    });

    final useCostOnly = _pagesPerFile.length == _selectedFiles.length && _pagesPerFile.isNotEmpty;
    final shopId = _printType == 'queue' ? _selectedShopId : null;

    try {
      if (useCostOnly) {
        final totalPages = _pagesPerFile.fold<int>(0, (a, b) => a + b);
        final costData = await _apiService.calculateCostFromPages(
          totalPages: totalPages,
          copies: _copies,
          printMode: _printMode,
          colorMode: _colorMode,
          shopId: shopId,
        );
        if (mounted) {
          setState(() {
            _costErrorFileName = null;
            _estimatedCost = (costData['total_cost'] as num).toDouble();
            _estimatedPages = costData['total_pages'] as int? ?? costData['num_pages'] as int? ?? totalPages;
          });
          if (mounted && _estimatedCost != null && _estimatedCost! > 0) {
            _fetchWalletBalance();
          }
        }
      } else {
        final filePaths = _selectedFiles.map((f) => f.path).toList();
        final costData = await _apiService.calculateCost(
          filePaths: filePaths,
          copies: _copies,
          printMode: _printMode,
          colorMode: _colorMode,
          paperSize: _paperSize,
          shopId: shopId,
        );
        if (mounted) {
          final filesList = costData['files'] as List<dynamic>?;
          final perFile = filesList?.map<int>((f) => (f is Map && f['pages'] != null) ? (f['pages'] as num).toInt() : 0).toList() ?? <int>[];
          setState(() {
            _costErrorFileName = null;
            _pagesPerFile = perFile;
            _estimatedCost = (costData['total_cost'] as num).toDouble();
            _estimatedPages = costData['total_pages'] as int? ?? costData['num_pages'] as int? ?? 0;
          });
          if (mounted && _estimatedCost != null && _estimatedCost! > 0) {
            _fetchWalletBalance();
          }
        }
      }
    } catch (e) {
      if (mounted) {
        // Parse "File 'filename': ..." from backend so we can mark the problematic file in the list
        String? errorFileName;
        final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        final match = RegExp(r"File '([^']+)'").firstMatch(msg);
        if (match != null) errorFileName = match.group(1);
        setState(() {
          _estimatedCost = null;
          _estimatedPages = null;
          if (!useCostOnly) _pagesPerFile = [];
          _costErrorFileName = errorFileName;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCalculatingCost = false;
        });
      }
    }
  }

  Future<void> _fetchWalletBalance() async {
    if (_walletBalanceLoading) return;
    setState(() => _walletBalanceLoading = true);
    try {
      final balance = await _apiService.getWalletBalance();
      if (mounted) setState(() {
        _walletBalance = balance;
        _walletBalanceLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _walletBalance = null;
        _walletBalanceLoading = false;
      });
    }
  }

  /// Proceed to upload after payment (wallet or Razorpay success)
  Future<void> _proceedToUpload(int paymentOrderId) async {
    try {
      setState(() {
        _isProcessingPayment = false;
        _isUploading = true;
      });
      final filePaths = _selectedFiles.map((f) => f.path).toList();
      final result = await _apiService.uploadFile(
        filePaths: filePaths,
        copies: _storedCopies ?? _copies,
        printMode: _storedPrintMode ?? _printMode,
        colorMode: _storedColorMode ?? _colorMode,
        paperSize: _storedPaperSize ?? _paperSize,
        printType: _storedPrintType ?? _printType,
        shopId: (_storedPrintType ?? _printType) == 'queue' ? (_storedShopId ?? _selectedShopId) : null,
        comment: (_storedComment?.isNotEmpty ?? false) ? _storedComment : (_comment.isNotEmpty ? _comment : null),
        paymentOrderId: paymentOrderId,
      );
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _successMessage = '${_selectedFiles.length} file(s) uploaded successfully!';
        if (result['code'] != null) _uniqueCode = result['code'];
        if (result['queue_position'] != null) _queuePosition = result['queue_position'];
        _storedCopies = null;
        _storedPrintMode = null;
        _storedColorMode = null;
        _storedPaperSize = null;
        _storedPrintType = null;
        _storedShopId = null;
        _storedComment = null;
        _selectedFiles = [];
        _pagesPerFile = [];
        _copies = 1;
        _copiesController.text = '1';
        _printMode = 'single';
        _colorMode = 'bw';
        _paperSize = 'A4';
        _printType = 'private';
        _selectedShopId = null;
        _comment = '';
        _estimatedCost = null;
        _estimatedPages = null;
        _walletBalance = null;
      });
      // Notify dashboard to refresh wallet balance immediately.
      widget.onUploadSuccess?.call();
      _showSuccessDialog();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _errorMessage = getSafeErrorMessage(e, 'upload');
          _storedCopies = null;
          _storedPrintMode = null;
          _storedColorMode = null;
          _storedPaperSize = null;
          _storedPrintType = null;
          _storedShopId = null;
          _storedComment = null;
        });
      }
    }
  }

  /// For queue prints, fetches latest shop status and shows a warning if the selected shop is closed.
  /// Returns true to proceed with payment, false to cancel.
  Future<bool> _checkShopStatusBeforePayment() async {
    if (_printType != 'queue' || _selectedShopId == null) return true;
    try {
      final lat = _userLat ?? 0.0;
      final long = _userLong ?? 0.0;
      final shops = await _apiService.getShops(lat, long);
      final list = shops is List ? shops : <dynamic>[];
      final selected = list.cast<Map<String, dynamic>>().where((s) => s['id'] == _selectedShopId).toList();
      if (selected.isEmpty) return true;
      final isOpen = selected.first['is_open'] == true;
      if (isOpen) return true;

      // Shop is closed: warn and let user cancel or proceed
      if (!mounted) return false;
      final proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.white10,
          title: const Row(
            children: [
              Icon(Icons.warning, color: AppColors.yellow500),
              SizedBox(width: 8),
              Text('Shop is currently closed', style: TextStyle(color: AppColors.white)),
            ],
          ),
          content: Text(
            '${selected.first['shop_name'] ?? 'This shop'} is currently closed. Your print will be queued and the shop can print it when they open. Do you want to proceed?',
            style: const TextStyle(color: AppColors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.white70)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Proceed anyway', style: TextStyle(color: AppColors.pink500)),
            ),
          ],
        ),
      );
      return proceed == true;
    } catch (_) {
      // On network/API error, allow proceeding (don't block user)
      return true;
    }
  }

  /// Shows a confirmation dialog with files, configuration and total. Returns true if user taps "Confirm and Pay".
  Future<bool> _showUploadConfirmationDialog(double totalCost) async {
    String? selectedShopName;
    if (_selectedShopId != null && _shops.isNotEmpty) {
      final matches = _shops.cast<Map<String, dynamic>>().where(
            (s) => s['id'] == _selectedShopId,
          ).toList();
      if (matches.isNotEmpty) {
        selectedShopName = matches.first['shop_name']?.toString();
      }
    }
    final fileNames = _selectedFiles.map((f) {
      final path = f.path;
      final segments = path.split(RegExp(r'[/\\]'));
      return segments.isNotEmpty ? segments.last : path;
    }).toList();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.indigo900,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.white20),
          ),
          title: const Text(
            'Review & pay',
            style: TextStyle(color: AppColors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Files',
                  style: TextStyle(
                    color: AppColors.purple200,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                ...fileNames.map(
                  (name) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• $name',
                      style: const TextStyle(color: AppColors.white70, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Configuration',
                  style: TextStyle(
                    color: AppColors.purple200,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Copies: $_copies • ${_printMode == 'single' ? 'Single-sided' : 'Double-sided'} • ${_colorMode == 'bw' ? 'B&W' : 'Color'} • $_paperSize',
                  style: const TextStyle(color: AppColors.white70, fontSize: 13),
                ),
                Text(
                  'Type: ${_printType == 'queue' ? 'Queue Print' : 'Private Print'}${selectedShopName != null ? ' • $selectedShopName' : ''}',
                  style: const TextStyle(color: AppColors.white70, fontSize: 13),
                ),
                if (_comment.isNotEmpty)
                  Text(
                    'Note: $_comment',
                    style: const TextStyle(color: AppColors.white50, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (_selectedFiles.any((f) {
                  final n = f.path.split(RegExp(r'[/\\]')).last.toLowerCase();
                  return n.endsWith('.ppt') || n.endsWith('.pptx');
                }))
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 18, color: Colors.amber.shade200),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'PowerPoint (.ppt/.pptx) files will be printed in landscape mode.',
                              style: TextStyle(color: Colors.amber, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.pink500.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.pink400.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '₹${totalCost.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: AppColors.pink400,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.white70)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.pink500),
              child: const Text('Confirm and pay'),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  Future<void> _handleUpload() async {
    if (_selectedFiles.isEmpty) {
      setState(() {
        _errorMessage = 'Please select at least one file';
      });
      return;
    }

    if (_printType == 'queue' && _selectedShopId == null) {
      setState(() {
        _errorMessage = 'Please select a shop for queue print';
      });
      return;
    }

    setState(() {
      _isProcessingPayment = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      double totalCost;
      if (_pagesPerFile.length == _selectedFiles.length && _pagesPerFile.isNotEmpty) {
        final totalPages = _pagesPerFile.fold<int>(0, (a, b) => a + b);
        final costData = await _apiService.calculateCostFromPages(
          totalPages: totalPages,
          copies: _copies,
          printMode: _printMode,
          colorMode: _colorMode,
          shopId: _printType == 'queue' ? _selectedShopId : null,
        );
        totalCost = (costData['total_cost'] as num).toDouble();
      } else {
        final filePaths = _selectedFiles.map((f) => f.path).toList();
        final costData = await _apiService.calculateCost(
          filePaths: filePaths,
          copies: _copies,
          printMode: _printMode,
          colorMode: _colorMode,
          paperSize: _paperSize,
          shopId: _printType == 'queue' ? _selectedShopId : null,
        );
        totalCost = (costData['total_cost'] as num).toDouble();
      }

      final confirmed = await _showUploadConfirmationDialog(totalCost);
      if (!confirmed) {
        setState(() => _isProcessingPayment = false);
        return;
      }

      // For queue prints: fetch latest shop status and warn if selected shop is closed
      final canProceed = await _checkShopStatusBeforePayment();
      if (!canProceed) {
        setState(() => _isProcessingPayment = false);
        return;
      }

      // Fetch wallet balance if not already available
      if (_walletBalance == null && !_walletBalanceLoading) {
        await _fetchWalletBalance();
      }
      final balance = _walletBalance ?? 0.0;

      // Payment method choice when user has wallet balance
      bool useWallet = false;
      double? walletAmount;
      if (balance > 0) {
        final choice = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            final options = <String>[];
            if (balance >= totalCost) {
              options.add('wallet_full');
            }
            options.add('razorpay_only');
            if (balance < totalCost && balance > 0) {
              options.add('hybrid');
            }
            return AlertDialog(
              backgroundColor: AppColors.indigo900,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.white20)),
              title: const Text('Payment method', style: TextStyle(color: AppColors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total: ₹${totalCost.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.purple200, fontSize: 14)),
                  if (balance > 0) Text('Wallet balance: ₹${balance.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.purple200, fontSize: 14)),
                  const SizedBox(height: 16),
                  if (options.contains('wallet_full'))
                    ListTile(
                      title: const Text('Pay from wallet', style: TextStyle(color: AppColors.white)),
                      subtitle: Text('₹${totalCost.toStringAsFixed(2)} (instant)', style: const TextStyle(color: AppColors.white50, fontSize: 12)),
                      onTap: () => Navigator.pop(ctx, 'wallet_full'),
                    ),
                  ListTile(
                    title: const Text('Pay via card/UPI', style: TextStyle(color: AppColors.white)),
                    subtitle: const Text('Razorpay', style: TextStyle(color: AppColors.white50, fontSize: 12)),
                    onTap: () => Navigator.pop(ctx, 'razorpay_only'),
                  ),
                  if (options.contains('hybrid'))
                    ListTile(
                      title: const Text('Use wallet + card/UPI', style: TextStyle(color: AppColors.white)),
                      subtitle: Text('₹${balance.toStringAsFixed(2)} from wallet + ₹${(totalCost - balance).toStringAsFixed(2)} via Razorpay', style: const TextStyle(color: AppColors.white50, fontSize: 12)),
                      onTap: () => Navigator.pop(ctx, 'hybrid'),
                    ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Cancel', style: TextStyle(color: AppColors.white70))),
              ],
            );
          },
        );
        if (choice == 'cancel' || choice == null) {
          setState(() => _isProcessingPayment = false);
          return;
        }
        if (choice == 'wallet_full') {
          useWallet = true;
          walletAmount = totalCost;
        } else if (choice == 'hybrid') {
          useWallet = true;
          walletAmount = balance;
        }
      }

      _storedCopies = _copies;
      _storedPrintMode = _printMode;
      _storedColorMode = _colorMode;
      _storedPaperSize = _paperSize;
      _storedPrintType = _printType;
      _storedShopId = _selectedShopId;
      _storedComment = _comment;

      final paymentOrder = await _apiService.createPaymentOrder(
        amount: totalCost,
        copies: _copies,
        printMode: _printMode,
        colorMode: _colorMode,
        paperSize: _paperSize,
        printType: _printType,
        shopkeeperId: _printType == 'queue' ? _selectedShopId : null,
        comment: _comment.isNotEmpty ? _comment : null,
        useWallet: useWallet,
        walletAmount: walletAmount,
      );

      final paymentOrderId = paymentOrder['id'] as int;
      final skipPayment = paymentOrder['skip_payment'] == true;

      if (skipPayment) {
        await _proceedToUpload(paymentOrderId);
        return;
      }

      final razorpayOrderId = paymentOrder['order_id'] as String?;
      final keyId = paymentOrder['key_id'] as String?;
      final razorpayAmount = (paymentOrder['razorpay_amount'] as num?)?.toDouble() ?? (paymentOrder['amount'] as num?)?.toDouble() ?? totalCost;
      if (razorpayOrderId == null || keyId == null) {
        setState(() {
          _isProcessingPayment = false;
          _errorMessage = 'Payment setup failed. Please try again.';
        });
        return;
      }

      _razorpayService.openCheckout(
        keyId: keyId,
        amount: razorpayAmount,
        orderId: razorpayOrderId,
        name: 'Qprint',
        description: 'Print Service Payment',
        prefill: {},
        onSuccess: (PaymentSuccessResponse response) async {
          await Future.delayed(const Duration(seconds: 2));
          await _proceedToUpload(paymentOrderId);
        },
        onError: (PaymentFailureResponse response) {
          setState(() {
            _isProcessingPayment = false;
            _errorMessage = response.message ?? 'Payment failed. Please try again.';
            _storedCopies = null;
            _storedPrintMode = null;
            _storedColorMode = null;
            _storedPaperSize = null;
            _storedPrintType = null;
            _storedShopId = null;
            _storedComment = null;
          });
        },
      );
    } catch (e) {
      setState(() {
        _isProcessingPayment = false;
        _errorMessage = getSafeErrorMessage(e, 'payment');
      });
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.indigo900,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.white20, width: 1),
        ),
        title: const Text(
          'Upload Successful!',
          style: TextStyle(
            color: AppColors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_printType == 'private' && _uniqueCode != null) ...[
              const Text(
                'Your unique code:',
                style: TextStyle(
                  color: AppColors.purple200,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.pink500.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.pink400,
                    width: 2,
                  ),
                ),
                child: Text(
                  _uniqueCode!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.pink400,
                    fontFamily: 'monospace',
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Share this code with the shopkeeper to print.',
                style: TextStyle(
                  color: AppColors.white70,
                  fontSize: 14,
                ),
              ),
            ] else if (_printType == 'queue' && _queuePosition != null) ...[
              Text(
                'Your file is in queue position #$_queuePosition',
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 16,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.pink400,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text(
              'OK',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Upload Section
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.white10,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.white20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.upload, size: 32, color: AppColors.white),
                    SizedBox(width: 12),
                    Text(
                      'Upload Document',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // File Picker
                ElevatedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.file_upload),
                  label: Text(_selectedFiles.isEmpty
                      ? 'Select Files (PDF, images, Word, or PowerPoint) - Max 100MB'
                      : '${_selectedFiles.length} file(s) selected'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: AppColors.white20,
                    foregroundColor: AppColors.white,
                  ),
                ),
                if (_selectedFiles.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Selected: ${_selectedFiles.length} file(s) - ${(_selectedFiles.fold(0, (sum, f) => sum + f.lengthSync()) / (1024 * 1024)).toStringAsFixed(2)}MB',
                    style: const TextStyle(
                      color: AppColors.purple200,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _selectedFiles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final file = _selectedFiles[index];
                      final pathSegments = file.path.split(RegExp(r'[/\\]'));
                      final fileName = pathSegments.isNotEmpty ? pathSegments.last : file.path;
                      final fileSize = (file.lengthSync() / (1024 * 1024)).toStringAsFixed(2);
                      final isProblemFile = _costErrorFileName != null &&
                          (fileName == _costErrorFileName || fileName.endsWith(_costErrorFileName!) || _costErrorFileName!.endsWith(fileName));
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isProblemFile ? Colors.amber.withOpacity(0.12) : Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isProblemFile ? Colors.amber : AppColors.white20,
                            width: isProblemFile ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.white10,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppColors.white20),
                                  ),
                                  child: Icon(_fileIcon(fileName), color: AppColors.white),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        fileName,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.white,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${fileSize} MB',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.purple200,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Remove',
                                  icon: const Icon(Icons.close, size: 20, color: AppColors.red300),
                                  onPressed: () => _removeFile(index),
                                ),
                              ],
                            ),
                            if (isProblemFile) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber.shade200),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Page count not available. Remove this file to continue.',
                                      style: TextStyle(fontSize: 12, color: Colors.amber.shade200),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ],

                const SizedBox(height: 24),

                // Print Settings
                const Text(
                  'Print Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.white,
                  ),
                ),
                const SizedBox(height: 16),

                // Copies
                Row(
                  children: [
                    const Expanded(
                      child: Text('Copies:', style: TextStyle(color: AppColors.white)),
                    ),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _copiesController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.all(12),
                        ),
                        onChanged: (value) {
                          // Allow empty value while typing
                          if (value.isEmpty) {
                            setState(() {
                              _copies = 1; // Default to 1 if empty
                            });
                            return;
                          }
                          
                          final copies = int.tryParse(value);
                          if (copies != null && copies >= 1 && copies <= 100) {
                            setState(() {
                              _copies = copies;
                            });
                            _calculateEstimatedCost();
                          } else if (copies != null && copies > 100) {
                            // Limit to 100
                            setState(() {
                              _copies = 100;
                              _copiesController.text = '100';
                              _copiesController.selection = TextSelection.collapsed(offset: 3);
                            });
                            _calculateEstimatedCost();
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Print Mode
                DropdownButtonFormField<String>(
                  value: _printMode,
                  decoration: InputDecoration(
                    labelText: 'Print Mode',
                    labelStyle: const TextStyle(color: AppColors.purple200),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.white10,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.white20),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.white20),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.pink400, width: 2),
                    ),
                  ),
                  dropdownColor: AppColors.indigo900,
                  style: const TextStyle(color: AppColors.white, fontSize: 16),
                  iconEnabledColor: AppColors.pink400,
                  iconDisabledColor: AppColors.white50,
                  menuMaxHeight: 200,
                  items: const [
                    DropdownMenuItem(
                      value: 'single',
                      child: Text('Single-sided', style: TextStyle(color: AppColors.white)),
                    ),
                    DropdownMenuItem(
                      value: 'double',
                      child: Text('Double-sided', style: TextStyle(color: AppColors.white)),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _printMode = value!;
                    });
                    _calculateEstimatedCost();
                  },
                ),
                const SizedBox(height: 16),

                // Color Mode
                DropdownButtonFormField<String>(
                  value: _colorMode,
                  decoration: InputDecoration(
                    labelText: 'Color',
                    labelStyle: const TextStyle(color: AppColors.purple200),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.white10,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.white20),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.white20),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.pink400, width: 2),
                    ),
                  ),
                  dropdownColor: AppColors.indigo900,
                  style: const TextStyle(color: AppColors.white, fontSize: 16),
                  iconEnabledColor: AppColors.pink400,
                  iconDisabledColor: AppColors.white50,
                  menuMaxHeight: 200,
                  items: const [
                    DropdownMenuItem(
                      value: 'bw',
                      child: Text('Black & White', style: TextStyle(color: AppColors.white)),
                    ),
                    DropdownMenuItem(
                      value: 'color',
                      child: Text('Color', style: TextStyle(color: AppColors.white)),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _colorMode = value!;
                    });
                    _calculateEstimatedCost();
                  },
                ),
                const SizedBox(height: 16),

                // Paper Size
                DropdownButtonFormField<String>(
                  value: _paperSize,
                  decoration: InputDecoration(
                    labelText: 'Paper Size',
                    labelStyle: const TextStyle(color: AppColors.purple200),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.white10,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.white20),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.white20),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.pink400, width: 2),
                    ),
                  ),
                  dropdownColor: AppColors.indigo900,
                  style: const TextStyle(color: AppColors.white, fontSize: 16),
                  iconEnabledColor: AppColors.pink400,
                  iconDisabledColor: AppColors.white50,
                  menuMaxHeight: 200,
                  items: const [
                    DropdownMenuItem(
                      value: 'A4',
                      child: Text('A4', style: TextStyle(color: AppColors.white)),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _paperSize = value!;
                    });
                    _calculateEstimatedCost();
                  },
                ),
                const SizedBox(height: 24),

                // Print Type
                const Text(
                  'Print Type',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _printType = 'queue';
                          });
                          _calculateEstimatedCost();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _printType == 'queue'
                                ? AppColors.pink500.withOpacity(0.3)
                                : AppColors.white10,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _printType == 'queue'
                                  ? AppColors.pink400
                                  : AppColors.white20,
                              width: 2,
                            ),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.queue, size: 32),
                              const SizedBox(height: 8),
                              const Text(
                                'Queue Print',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.white,
                                ),
                              ),
                              const Text(
                                'Send to shop',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.purple200,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _printType = 'private';
                            _selectedShopId = null;
                          });
                          _calculateEstimatedCost();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _printType == 'private'
                                ? AppColors.pink500.withOpacity(0.3)
                                : AppColors.white10,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _printType == 'private'
                                  ? AppColors.pink400
                                  : AppColors.white20,
                              width: 2,
                            ),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.lock, size: 32),
                              const SizedBox(height: 8),
                              const Text(
                                'Private Print',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.white,
                                ),
                              ),
                              const Text(
                                'Get unique code',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.purple200,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // Shop Selection (for queue prints) — separate box so user can identify and scroll past it
                if (_printType == 'queue') ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.indigo900.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.pink400.withOpacity(0.6), width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.pink500.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.store, color: AppColors.pink400, size: 24),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Select Shop',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // At a shop? Scan QR or enter code (parse only; never open URL in browser)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.pink500.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.pink400.withOpacity(0.5)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'At a shop? Scan QR or enter code',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.white,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _shopCodeController,
                                      decoration: const InputDecoration(
                                        hintText: 'Shop code or number',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                      keyboardType: TextInputType.number,
                                      onSubmitted: (_) => _submitShopCode(),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton.filled(
                                    onPressed: _openShopQrScanner,
                                    icon: const Icon(Icons.qr_code_scanner),
                                    tooltip: 'Scan shop QR',
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    onPressed: _submitShopCode,
                                    child: const Text('Go'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_shopLoadError && _shops.isEmpty)
                          InkWell(
                            onTap: _sessionExpired ? null : _loadShops,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.orange.withOpacity(0.5)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _sessionExpired
                                          ? 'Session expired. Please log out from Profile and log in again.'
                                          : 'Could not load shops. Tap to retry.',
                                      style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                  if (!_sessionExpired) const Icon(Icons.refresh, color: Colors.orange, size: 20),
                                ],
                              ),
                            ),
                          )
                        else if (_shopsLoading && _shops.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator(color: Colors.white54)),
                          )
                        else
                          ShopSelectionWidget(
                            shops: _shops,
                            selectedShopId: _selectedShopId,
                            onShopSelected: (shopId) {
                              setState(() {
                                _selectedShopId = shopId;
                              });
                              _calculateEstimatedCost();
                            },
                            onShopsUpdated: _loadShops,
                            parentScrollController: _scrollController,
                          ),
                        const SizedBox(height: 8),
                        const Text(
                          'Scroll down for comment, cost & upload',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.purple200,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Comment Field
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Comment (Optional)',
                    hintText: 'Add any special instructions...',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 3,
                  maxLength: 500,
                  onChanged: (value) {
                    setState(() {
                      _comment = value;
                    });
                  },
                ),

                const SizedBox(height: 24),

                // Estimated Cost Display
                if (_selectedFiles.isNotEmpty &&
                    (_printType == 'private' ||
                        (_printType == 'queue' && _selectedShopId != null)))
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.orange.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Estimated Cost',
                              style: TextStyle(
                                color: AppColors.purple200,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            _isCalculatingCost
                                ? const Text(
                                    'Calculating...',
                                    style: TextStyle(
                                      color: AppColors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : _estimatedCost != null
                                    ? Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '₹${_estimatedCost!.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              color: AppColors.white,
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          if (_estimatedPages != null)
                                            Text(
                                              '${_estimatedPages} page${_estimatedPages! > 1 ? 's' : ''} × $_copies cop${_copies > 1 ? 'ies' : 'y'}',
                                              style: const TextStyle(
                                                color: AppColors.purple200,
                                                fontSize: 12,
                                              ),
                                            ),
                                          if (_walletBalance != null)
                                            Text(
                                              'Wallet: ₹${_walletBalance!.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                color: AppColors.green300,
                                                fontSize: 12,
                                              ),
                                            ),
                                        ],
                                      )
                                    : const Text(
                                        'Unable to calculate',
                                        style: TextStyle(
                                          color: AppColors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                          ],
                        ),
                        const Icon(
                          Icons.account_balance_wallet,
                          size: 40,
                          color: Colors.orange,
                        ),
                      ],
                    ),
                  ),
                if (_selectedFiles.isNotEmpty &&
                    _printType == 'queue' &&
                    _selectedShopId == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Select a shop to see queue pricing.',
                      style: const TextStyle(
                        color: AppColors.purple200,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),

                const SizedBox(height: 24),

                // Error/Success Messages
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.red500.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppColors.red300),
                    ),
                  ),
                if (_successMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.green500.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _successMessage!,
                      style: const TextStyle(color: AppColors.green300),
                    ),
                  ),

                const SizedBox(height: 16),

                // Upload Button
                ElevatedButton(
                  onPressed: (_isUploading || _isProcessingPayment) ? null : _handleUpload,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppColors.pink500,
                  ),
                  child: (_isUploading || _isProcessingPayment)
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.white,
                          ),
                        )
                      : const Text(
                          'Upload',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

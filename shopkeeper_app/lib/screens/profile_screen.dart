import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' show ImageByteFormat;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/api_service.dart';
import '../utils/auth_prefs.dart';
import 'login_screen.dart';
import 'printer_setup_screen.dart';
import 'how_to_use_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _apiService = ApiService();
  final _formKey = GlobalKey<FormState>();
  
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isOpen = true;
  String? _errorMessage;
  String? _successMessage;
  String? _memberSince;
  int? _shopId;
  int? _shopCode; // 6-digit unique code for customers to enter when QR fails
  final GlobalKey _qrRepaintKey = GlobalKey();

  late TextEditingController _shopNameController;
  late TextEditingController _addressController;
  late TextEditingController _fullNameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _passwordController;
  late TextEditingController _currentPasswordController;

  @override
  void initState() {
    super.initState();
    _shopNameController = TextEditingController();
    _addressController = TextEditingController();
    _fullNameController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _passwordController = TextEditingController();
    _currentPasswordController = TextEditingController();
    _fetchProfile();
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _addressController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _currentPasswordController.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    try {
      final profile = await _apiService.getProfile();
      if (mounted) {
        setState(() {
          final shopName = profile['shop_name'] ?? profile['display_name'] ?? '';
          _shopNameController.text = shopName;
          if (shopName.toString().trim().isNotEmpty) {
            writeCachedShopName(shopName.toString());
          }
          _addressController.text = profile['address'] ?? '';
          _fullNameController.text = profile['full_name']?.toString() ?? '';
          _emailController.text = profile['email']?.toString() ?? '';
          _phoneController.text = profile['phone']?.toString() ?? '';
          _isOpen = profile['is_open'] ?? true;
          _shopId = profile['id'] is int ? profile['id'] as int : null;
          _shopCode = profile['shop_code'] is int ? profile['shop_code'] as int : null;
          final createdAt = profile['created_at'];
          _memberSince = createdAt != null ? _formatMemberSince(createdAt) : null;
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load profile: ${e.toString().replaceAll('Exception: ', '')}';
          _isLoading = false;
        });
      }
    }
  }

  String _formatMemberSince(dynamic createdAt) {
    if (createdAt == null) return '';
    try {
      final d = DateTime.parse(createdAt.toString());
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[d.month - 1]} ${d.year}';
    } catch (_) {
      return '';
    }
  }

  Future<void> _toggleShopStatus() async {
    try {
      await _apiService.toggleShopStatus(!_isOpen);
      if (mounted) setState(() => _isOpen = !_isOpen);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final newPassword = _passwordController.text.trim();
    if (newPassword.isNotEmpty && _currentPasswordController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Enter current password to set a new password.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final updatedShopName = _shopNameController.text.trim();
      await _apiService.updateProfile(
        address: _addressController.text.trim(),
        password: newPassword.isEmpty ? null : newPassword,
        currentPassword: _currentPasswordController.text.trim().isEmpty ? null : _currentPasswordController.text.trim(),
        fullName: _fullNameController.text.trim().isEmpty ? null : _fullNameController.text.trim(),
        email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        shopName: updatedShopName.isEmpty ? null : updatedShopName,
      );
      if (updatedShopName.isNotEmpty) {
        await writeCachedShopName(updatedShopName);
      }

      if (mounted) {
        setState(() {
          _successMessage = 'Profile updated successfully!';
          _passwordController.clear();
          _currentPasswordController.clear();
          _isSaving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isSaving = false;
        });
      }
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
      // Clear printer cache
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

  Future<void> _handleDeleteAccount() async {
    final passwordController = TextEditingController();
    
    final password = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF312E81),
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.redAccent, size: 28),
            SizedBox(width: 12),
            Text('Delete Account', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This action cannot be undone. All your data, including order history and files, will be permanently deleted.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            const Text(
              'Enter your password to confirm:',
              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: passwordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Password',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                filled: true,
                fillColor: Colors.black.withOpacity(0.2),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(passwordController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete My Account'),
          ),
        ],
      ),
    );

    if (password != null && password.isNotEmpty && mounted) {
      try {
        // Show loading
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(color: Colors.pinkAccent),
          ),
        );

        await _apiService.deleteAccount(password);

        if (mounted) {
          Navigator.of(context).pop(); // Close loading
          // Clear printer cache
          PrinterSetupScreen.setCachedPrinter(null);
          // Navigate to login screen
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Account deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.of(context).pop(); // Close loading
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString().replaceAll('Exception: ', '')),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// QR points to backend /s/{id} so scan opens redirect page (or app if installed).
  String get _shopQrUrl => '${ApiService.baseUrl}/s/$_shopId';

  Future<Uint8List?> _captureQrImage() async {
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return null;
    final boundary = _qrRepaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  String get _shopDisplayName => _shopNameController.text.isEmpty ? 'Qprint Shop' : _shopNameController.text;
  String get _shopCodeDisplay => _shopCode != null ? '$_shopCode' : (_shopId != null ? '$_shopId' : '—');

  static PdfColor get _brandPurple => PdfColor.fromInt(0xFF6B21A8);
  static PdfColor get _brandPink => PdfColor.fromInt(0xFFEC4899);
  static PdfColor get _grey800 => PdfColor.fromInt(0xFF1F2937);
  static PdfColor get _grey600 => PdfColor.fromInt(0xFF4B5563);
  static PdfColor get _grey100 => PdfColor.fromInt(0xFFF3F4F6);

  pw.Widget _buildQrPdfPage(Uint8List qrBytes) {
    final hasAddress = _addressController.text.trim().isNotEmpty;
    final hasFullName = _fullNameController.text.trim().isNotEmpty;
    final hasPhone = _phoneController.text.trim().isNotEmpty;
    final hasEmail = _emailController.text.trim().isNotEmpty;

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Qprint branding header
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text('Q', style: pw.TextStyle(fontSize: 32, fontWeight: pw.FontWeight.bold, color: _brandPurple)),
              pw.Text('print', style: pw.TextStyle(fontSize: 32, fontWeight: pw.FontWeight.bold, color: _brandPink)),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text('Print at this shop', style: pw.TextStyle(fontSize: 14, color: _grey600)),
          pw.SizedBox(height: 2),
          pw.Text('qprint.co.in', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _brandPurple)),
          pw.SizedBox(height: 24),
          // Shop details card
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(20),
            decoration: pw.BoxDecoration(
              color: _grey100,
              borderRadius: pw.BorderRadius.circular(12),
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(_shopDisplayName, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: _grey800)),
                pw.SizedBox(height: 12),
                pw.Row(
                  children: [
                    pw.Text('Shop code: ', style: pw.TextStyle(fontSize: 12, color: _grey600)),
                    pw.Text(_shopCodeDisplay, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _brandPurple)),
                  ],
                ),
                if (hasAddress) ...[
                  pw.SizedBox(height: 8),
                  pw.Text('Address: ${_addressController.text.trim()}', style: pw.TextStyle(fontSize: 11, color: _grey600)),
                ],
                if (hasFullName || hasPhone || hasEmail) ...[
                  pw.SizedBox(height: 8),
                  pw.Text([
                    if (hasFullName) _fullNameController.text.trim(),
                    if (hasPhone) _phoneController.text.trim(),
                    if (hasEmail) _emailController.text.trim(),
                  ].join(' • '), style: pw.TextStyle(fontSize: 11, color: _grey600)),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 24),
          // Scan instruction
          pw.Text('Scan to print at this shop', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _grey800)),
          pw.SizedBox(height: 16),
          // QR code in card
          pw.Container(
            padding: const pw.EdgeInsets.all(20),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(12),
              border: pw.Border.all(color: PdfColors.grey300),
              boxShadow: [pw.BoxShadow(color: PdfColors.grey300, blurRadius: 8, offset: const PdfPoint(0, 2))],
            ),
            child: pw.Column(
              children: [
                pw.Image(pw.MemoryImage(qrBytes), width: 220, height: 220),
                pw.SizedBox(height: 12),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: pw.BoxDecoration(color: _grey100, borderRadius: pw.BorderRadius.circular(8)),
                  child: pw.Text('Shop code: $_shopCodeDisplay', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _brandPurple)),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Text('Can\'t scan? Enter the shop code above in the Qprint customer app.', style: pw.TextStyle(fontSize: 11, color: _grey600)),
          pw.SizedBox(height: 12),
          pw.Text('More info & download app: qprint.co.in', style: pw.TextStyle(fontSize: 11, color: _grey600)),
        ],
      ),
    );
  }

  Future<void> _printShopQr() async {
    final qrBytes = await _captureQrImage();
    if (qrBytes == null || !mounted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not capture QR. Try again.')));
      return;
    }
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => _buildQrPdfPage(qrBytes),
      ),
    );
    final pdfBytes = await pdf.save();
    if (!mounted) return;
    await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
  }

  Future<void> _downloadShopQr() async {
    final qrBytes = await _captureQrImage();
    if (qrBytes == null || !mounted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not capture QR. Try again.')));
      return;
    }
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => _buildQrPdfPage(qrBytes),
      ),
    );
    final pdfBytes = await pdf.save();
    if (!mounted) return;
    final suggestedName = 'qprint_shop_${_shopCode ?? _shopId ?? 'shop'}.pdf';
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save QR as PDF',
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (!mounted) return;
    if (path != null && path.isNotEmpty) {
      try {
        final file = File(path);
        await file.writeAsBytes(pdfBytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to ${file.path}')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save file: $e')));
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Save cancelled.')));
      }
    }
  }

  Widget _buildShopQrSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Shop QR code', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Customers scan this to print at your shop.', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_shopDisplayName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Shop code: $_shopCodeDisplay', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 2),
                Text('If QR doesn\'t work, customers can enter this code in the app.', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          RepaintBoundary(
            key: _qrRepaintKey,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: QrImageView(
                data: _shopQrUrl,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _downloadShopQr,
                icon: const Icon(Icons.download, size: 20),
                label: const Text('Download QR'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _printShopQr,
                icon: const Icon(Icons.print, size: 20),
                label: const Text('Print QR'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'Shop Profile',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'View and update your shop details',
            style: TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else
            Expanded(
              child: Stack(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                    // Summary card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.15)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Your shop', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(
                            _shopNameController.text.isEmpty ? '—' : _shopNameController.text,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _addressController.text.isEmpty ? 'No address set' : _addressController.text,
                            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _isOpen ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _isOpen ? '● Open' : '● Closed',
                                  style: TextStyle(color: _isOpen ? Colors.greenAccent : Colors.redAccent, fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                              ),
                              if (_memberSince != null) ...[
                                const SizedBox(width: 12),
                                Text('Member since $_memberSince', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Shop status toggle
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.15)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Shop status', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text('Your shop is currently ', style: TextStyle(color: Colors.white.withOpacity(0.8))),
                              GestureDetector(
                                onTap: _toggleShopStatus,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _isOpen ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(_isOpen ? 'Open' : 'Closed', style: TextStyle(color: _isOpen ? Colors.greenAccent : Colors.redAccent, fontWeight: FontWeight.w600)),
                                ),
                              ),
                              Text(' — Tap to change', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (_shopId != null) ...[
                      const SizedBox(height: 24),
                      _buildShopQrSection(),
                    ],
                    const SizedBox(height: 24),
                    // Edit form
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Edit profile', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 20),
                            if (_errorMessage != null)
                              Container(
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 20),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.red.withOpacity(0.5)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline, color: Colors.redAccent),
                                    const SizedBox(width: 12),
                                    Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.white))),
                                  ],
                                ),
                              ),
                            if (_successMessage != null)
                              Container(
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 20),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.green.withOpacity(0.5)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.check_circle_outline, color: Colors.greenAccent),
                                    const SizedBox(width: 12),
                                    Expanded(child: Text(_successMessage!, style: const TextStyle(color: Colors.white))),
                                  ],
                                ),
                              ),

                            _buildTextField(
                              controller: _shopNameController,
                              label: 'Shop name (also your login name)',
                              icon: Icons.store,
                              validator: (value) => value?.isEmpty ?? true ? 'Shop name is required' : null,
                              helperText: 'Displayed to customers',
                            ),
                            const SizedBox(height: 20),
                            _buildTextField(
                              controller: _fullNameController,
                              label: 'Owner / contact name',
                              icon: Icons.person_outline,
                              helperText: 'Optional',
                            ),
                            const SizedBox(height: 20),
                            _buildTextField(
                              controller: _addressController,
                              label: 'Address',
                              icon: Icons.location_on,
                              validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                              maxLines: 3,
                              helperText: 'Full address shown to customers for directions',
                            ),
                            const SizedBox(height: 20),
                            _buildTextField(
                              controller: _emailController,
                              label: 'Email',
                              icon: Icons.email_outlined,
                              helperText: 'Optional',
                            ),
                            const SizedBox(height: 20),
                            _buildTextField(
                              controller: _phoneController,
                              label: 'Phone',
                              icon: Icons.phone_outlined,
                              helperText: 'Optional',
                            ),
                            const SizedBox(height: 24),
                            const Text('Change password', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(
                              'Leave blank to keep your current password. To set a new password, enter your current password below.',
                              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _currentPasswordController,
                              label: 'Current password (required when changing)',
                              icon: Icons.lock_outline,
                              isPassword: true,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _passwordController,
                              label: 'New password',
                              icon: Icons.lock,
                              isPassword: true,
                            ),
                            const SizedBox(height: 32),
                        
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: _isSaving ? null : _saveProfile,
                            icon: _isSaving 
                                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.save),
                            label: Text(
                              _isSaving ? 'SAVING...' : 'SAVE CHANGES',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                        const SizedBox(height: 24),
                        Divider(color: Colors.white.withOpacity(0.2), thickness: 1),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const HowToUseScreen()),
                              );
                            },
                            icon: const Icon(Icons.help_outline),
                            label: const Text(
                              'HOW TO USE',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: OutlinedButton.icon(
                            onPressed: _handleLogout,
                            icon: const Icon(Icons.logout, color: Colors.redAccent),
                            label: const Text(
                              'LOGOUT',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.redAccent,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.redAccent, width: 2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Divider(color: Colors.white.withOpacity(0.2), thickness: 1),
                        const SizedBox(height: 16),
                        const Text(
                          'Danger Zone',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: OutlinedButton.icon(
                            onPressed: _handleDeleteAccount,
                            icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                            label: const Text(
                              'DELETE ACCOUNT',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.redAccent,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.redAccent, width: 2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                  ],
                ),
              ),
            ),
          ),
                  // Fade at bottom so it's clear more content is below (scroll cue)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 120,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.35),
                            ],
                          ),
                        ),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    String? Function(String?)? validator,
    int maxLines = 1,
    String? helperText,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 16)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: isPassword,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white),
          validator: validator,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: Colors.white70),
            helperText: helperText,
            helperStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            filled: true,
            fillColor: Colors.black.withOpacity(0.2),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.pinkAccent),
            ),
            errorStyle: const TextStyle(color: Colors.redAccent),
          ),
        ),
      ],
    );
  }
}

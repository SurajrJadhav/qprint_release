import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';
import '../services/api_service.dart';
import '../utils/auth_prefs.dart';
import '../utils/safe_error.dart';
import 'files_screen.dart';
import 'expenses_screen.dart';
import 'favorites_screen.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';
import 'how_to_use_screen.dart';
import 'wallet_screen.dart';
import 'dashboard_tour_overlay.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _apiService = ApiService();
  bool _isLoading = true;
  bool _isEditing = false;
  bool _isLoadingStats = false;
  
  // Profile data
  String _displayName = '';
  String? _fullName;
  String? _email;
  String? _phone;
  String? _address;
  int _id = 0;
  
  // Statistics
  int _totalFiles = 0;
  double _totalSpent = 0.0;
  String? _accountCreatedDate;
  
  // Default print settings (stored locally)
  String _defaultColorMode = 'bw';
  String _defaultPrintMode = 'single';
  String _defaultPaperSize = 'A4';
  int _defaultCopies = 1;
  
  // Login history (last 5 logins)
  List<String> _loginHistory = [];
  
  // Edit form
  final _fullNameEditController = TextEditingController();
  final _addressController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _fullNameEditController.dispose();
    _addressController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    // Load profile, stats, and preferences in parallel
    await Future.wait([
      _loadProfile(),
      _loadStatistics(),
      _loadPreferences(),
      _loadLoginHistory(),
    ]);
    
    setState(() => _isLoading = false);
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _apiService.getProfile();
      setState(() {
        _id = profile['id'] ?? 0;
        _displayName = profile['display_name'] ?? profile['full_name'] ?? '';
        _fullName = profile['full_name'];
        if (_displayName.isNotEmpty) {
          writeCachedDisplayName(_displayName);
        }
        _email = profile['email'];
        _phone = profile['phone'];
        _address = profile['address'] ?? '';
        
        _fullNameEditController.text = _fullName?.toString() ?? _displayName;
        _addressController.text = _address ?? '';
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading profile: $e');
    }
  }

  Future<void> _loadStatistics() async {
    setState(() => _isLoadingStats = true);
    try {
      final files = await _apiService.getMyFiles();
      final completedFiles = files.where((f) => f['status'] == 'downloaded').toList();
      final totalSpent = completedFiles.fold<double>(0.0, (sum, f) => sum + (f['total_cost'] ?? 0.0));
      
      setState(() {
        _totalFiles = files.length;
        _totalSpent = totalSpent;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading statistics: $e');
    } finally {
      setState(() => _isLoadingStats = false);
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _defaultColorMode = prefs.getString('default_color_mode') ?? 'bw';
      _defaultPrintMode = prefs.getString('default_print_mode') ?? 'single';
      _defaultPaperSize = prefs.getString('default_paper_size') ?? 'A4';
      _defaultCopies = prefs.getInt('default_copies') ?? 1;
      _accountCreatedDate = prefs.getString('account_created_date');
    });
  }

  Future<void> _loadLoginHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList('login_history') ?? [];
    setState(() {
      _loginHistory = historyJson.take(5).toList();
    });
  }

  Future<void> _saveLoginToHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final history = prefs.getStringList('login_history') ?? [];
    history.insert(0, now);
    if (history.length > 10) history.removeRange(10, history.length);
    await prefs.setStringList('login_history', history);
    _loadLoginHistory();
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('default_color_mode', _defaultColorMode);
    await prefs.setString('default_print_mode', _defaultPrintMode);
    await prefs.setString('default_paper_size', _defaultPaperSize);
    await prefs.setInt('default_copies', _defaultCopies);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Preferences saved successfully',
            style: TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppColors.green500,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      await _apiService.updateProfile(
        fullName: _fullNameEditController.text.trim(),
        email: _email?.toString(),
        phone: _phone?.toString(),
        password: _passwordController.text.isNotEmpty ? _passwordController.text : null,
        address: _addressController.text.trim(),
      );

      setState(() {
        _isEditing = false;
        _displayName = _fullNameEditController.text.trim();
        _fullName = _fullNameEditController.text.trim();
        _address = _addressController.text.trim();
        _passwordController.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully'),
          backgroundColor: AppColors.green500,
        ),
      );
      _loadProfile();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(getSafeErrorMessage(e, 'profile')),
          backgroundColor: AppColors.red500,
        ),
      );
    }
  }

  Future<void> _exportData() async {
    try {
      final files = await _apiService.getMyFiles();
      final profile = await _apiService.getProfile();
      
      final data = {
        'profile': profile,
        'total_files': _totalFiles,
        'total_spent': _totalSpent,
        'files': files,
        'export_date': DateTime.now().toIso8601String(),
      };
      
      // Show data in a dialog (in real app, would save to file)
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.indigo900,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.white20),
          ),
          title: const Text('Data Export', style: TextStyle(color: AppColors.white)),
          content: SingleChildScrollView(
            child: Text(
              'Profile: ${profile['display_name'] ?? profile['full_name']}\n'
              'Total Files: $_totalFiles\n'
              'Total Spent: ₹$_totalSpent\n'
              'Files: ${files.length} records\n\n'
              'Full data would be exported to a JSON file.',
              style: const TextStyle(color: AppColors.white70),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(color: AppColors.pink400)),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(getSafeErrorMessage(e, 'export')),
          backgroundColor: AppColors.red500,
        ),
      );
    }
  }

  Future<void> _deleteAccount() async {
    final passwordController = TextEditingController();
    
    final password = await showDialog<String>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.indigo900,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.white20),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning, color: AppColors.red500),
            SizedBox(width: 8),
            Text(
              'Delete Account',
              style: TextStyle(color: AppColors.red500, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This action cannot be undone. All your data will be permanently deleted.',
              style: TextStyle(color: AppColors.white70),
            ),
            const SizedBox(height: 16),
            const Text(
              'Enter your password to confirm:',
              style: TextStyle(color: AppColors.white70, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: passwordController,
              obscureText: true,
              style: const TextStyle(color: AppColors.white),
              decoration: InputDecoration(
                hintText: 'Password',
                hintStyle: const TextStyle(color: AppColors.white50),
                filled: true,
                fillColor: AppColors.white10,
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
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel', style: TextStyle(color: AppColors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, passwordController.text),
            child: const Text(
              'Delete My Account',
              style: TextStyle(color: AppColors.red500, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (password != null && password.isNotEmpty) {
      try {
        // Show loading
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(color: AppColors.pink400),
          ),
        );

        await _apiService.deleteAccount(password);

        if (mounted) {
          Navigator.of(context).pop(); // Close loading
          // Navigate to login screen
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Account deleted successfully'),
              backgroundColor: AppColors.green500,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.of(context).pop(); // Close loading
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString().replaceAll('Exception: ', '')),
              backgroundColor: AppColors.red500,
            ),
          );
        }
      }
    }
  }

  void _navigateToScreen(Widget screen) {
    String title = 'Screen';
    if (screen is FilesScreen) {
      title = 'My Files';
    } else if (screen is ExpensesScreen) {
      title = 'Expense Tracker';
    } else if (screen is FavoritesScreen) {
      title = 'Favorite Shops';
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(
              title,
              style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: Container(
            decoration: const BoxDecoration(
              gradient: AppColors.backgroundGradient,
            ),
            child: screen,
          ),
        ),
      ),
    );
  }

  void _openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        throw Exception('Could not launch $url');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open link. Please check your internet connection.'),
            backgroundColor: AppColors.red500,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      if (kDebugMode) debugPrint('Error launching URL: $e');
    }
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white10,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.white20),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.purple200,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, String? value, IconData icon) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white10,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.white20),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.pink400, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: AppColors.purple200, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuTile(String title, IconData icon, VoidCallback onTap, {Color? iconColor}) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? AppColors.pink400),
      title: Text(title, style: const TextStyle(color: AppColors.white)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.white50),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.purple200, size: 20),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: AppColors.purple200, fontSize: 12)),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(color: AppColors.white, fontSize: 16)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildClickableRow(String title, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: AppColors.pink400, size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Text(title, style: const TextStyle(color: AppColors.white, fontSize: 16)),
            ),
            const Icon(Icons.open_in_new, color: AppColors.white50, size: 18),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit, color: AppColors.pink400),
              onPressed: () => setState(() => _isEditing = true),
            ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Profile Header
                      Center(
                        child: Column(
                          children: [
                            Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.pink500,
                                border: Border.all(color: AppColors.pink400, width: 3),
                              ),
                              child: Center(
                                child: Text(
                                  _displayName.isNotEmpty ? _displayName[0].toUpperCase() : 'U',
                                  style: const TextStyle(color: AppColors.white, fontSize: 40, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(_displayName, style: const TextStyle(color: AppColors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                            if (_fullName != null && _fullName!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(_fullName!, style: const TextStyle(color: AppColors.purple200, fontSize: 16)),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      if (_isEditing) ...[
                        // Edit Form
                        TextFormField(
                          controller: _fullNameEditController,
                          decoration: InputDecoration(
                            labelText: 'Full name',
                            labelStyle: const TextStyle(color: AppColors.purple200),
                            filled: true,
                            fillColor: AppColors.white10,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.white20)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.white20)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.pink400, width: 2)),
                          ),
                          style: const TextStyle(color: AppColors.white),
                          validator: (value) => value == null || value.trim().isEmpty ? 'Full name is required' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _addressController,
                          decoration: InputDecoration(
                            labelText: 'Address',
                            labelStyle: const TextStyle(color: AppColors.purple200),
                            filled: true,
                            fillColor: AppColors.white10,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.white20)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.white20)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.pink400, width: 2)),
                          ),
                          style: const TextStyle(color: AppColors.white),
                          maxLines: 3,
                          validator: (value) => value == null || value.trim().isEmpty ? 'Address is required' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          decoration: InputDecoration(
                            labelText: 'New Password (optional)',
                            labelStyle: const TextStyle(color: AppColors.purple200),
                            hintText: 'Leave empty to keep current password',
                            hintStyle: const TextStyle(color: AppColors.white50),
                            filled: true,
                            fillColor: AppColors.white10,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.white20)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.white20)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.pink400, width: 2)),
                          ),
                          style: const TextStyle(color: AppColors.white),
                          obscureText: true,
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  setState(() {
                                    _isEditing = false;
                                    _fullNameEditController.text = _displayName;
                                    _addressController.text = _address ?? '';
                                    _passwordController.clear();
                                  });
                                },
                                style: OutlinedButton.styleFrom(foregroundColor: AppColors.white70, side: const BorderSide(color: AppColors.white20), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _saveProfile,
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.pink500, foregroundColor: AppColors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                child: const Text('Save'),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        // 1. Account Statistics
                        const Text('Account Statistics', style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _buildStatCard('Total Files', '$_totalFiles', Icons.folder, AppColors.pink400),
                            const SizedBox(width: 12),
                            _buildStatCard('Total Spent', '₹${_totalSpent.toStringAsFixed(0)}', Icons.attach_money, AppColors.green500),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Basic Info
                        const Text('Contact Information', style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        _buildInfoCard('Email', _email, Icons.email),
                        _buildInfoCard('Phone', _phone, Icons.phone),
                        _buildInfoCard('Address', _address, Icons.location_on),
                        _buildInfoCard('User ID', _id.toString(), Icons.badge),
                        const SizedBox(height: 24),

                        // 6. Quick Links
                        const Text('Quick Links', style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(color: AppColors.white10, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.white20)),
                          child: Column(
                            children: [
                              _buildMenuTile('How to Use', Icons.help_outline, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const HowToUseScreen()))),
                              const Divider(color: AppColors.white20, height: 1),
                              _buildMenuTile('Show dashboard tour again', Icons.tour, () async {
                                await DashboardTourOverlay.resetTour();
                                if (mounted) Navigator.pop(context, true);
                              }),
                              const Divider(color: AppColors.white20, height: 1),
                              _buildMenuTile('Wallet', Icons.account_balance_wallet, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const WalletScreen()))),
                              const Divider(color: AppColors.white20, height: 1),
                              _buildMenuTile('My Files', Icons.folder, () => _navigateToScreen(const FilesScreen())),
                              const Divider(color: AppColors.white20, height: 1),
                              _buildMenuTile('Expense Tracker', Icons.attach_money, () => _navigateToScreen(const ExpensesScreen())),
                              const Divider(color: AppColors.white20, height: 1),
                              _buildMenuTile('Favorite Shops', Icons.star, () => _navigateToScreen(const FavoritesScreen())),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // 2. Default Print Settings
                        const Text('Default Print Settings', style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(color: AppColors.white10, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.white20)),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Color Mode', style: TextStyle(color: AppColors.white)),
                                  DropdownButton<String>(
                                    value: _defaultColorMode,
                                    dropdownColor: AppColors.indigo900,
                                    style: const TextStyle(color: AppColors.white),
                                    items: const [
                                      DropdownMenuItem(value: 'bw', child: Text('Black & White', style: TextStyle(color: AppColors.white))),
                                      DropdownMenuItem(value: 'color', child: Text('Color', style: TextStyle(color: AppColors.white))),
                                    ],
                                    onChanged: (value) => setState(() => _defaultColorMode = value!),
                                  ),
                                ],
                              ),
                              const Divider(color: AppColors.white20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Print Mode', style: TextStyle(color: AppColors.white)),
                                  DropdownButton<String>(
                                    value: _defaultPrintMode,
                                    dropdownColor: AppColors.indigo900,
                                    style: const TextStyle(color: AppColors.white),
                                    items: const [
                                      DropdownMenuItem(value: 'single', child: Text('Single-sided', style: TextStyle(color: AppColors.white))),
                                      DropdownMenuItem(value: 'double', child: Text('Double-sided', style: TextStyle(color: AppColors.white))),
                                    ],
                                    onChanged: (value) => setState(() => _defaultPrintMode = value!),
                                  ),
                                ],
                              ),
                              const Divider(color: AppColors.white20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Paper Size', style: TextStyle(color: AppColors.white)),
                                  DropdownButton<String>(
                                    value: _defaultPaperSize,
                                    dropdownColor: AppColors.indigo900,
                                    style: const TextStyle(color: AppColors.white),
                                    items: const [
                                      DropdownMenuItem(value: 'A4', child: Text('A4', style: TextStyle(color: AppColors.white))),
                                    ],
                                    onChanged: (value) => setState(() => _defaultPaperSize = value!),
                                  ),
                                ],
                              ),
                              const Divider(color: AppColors.white20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Default Copies', style: TextStyle(color: AppColors.white)),
                                  DropdownButton<int>(
                                    value: _defaultCopies,
                                    dropdownColor: AppColors.indigo900,
                                    style: const TextStyle(color: AppColors.white),
                                    items: List.generate(10, (i) => i + 1).map((i) => DropdownMenuItem(value: i, child: Text('$i', style: const TextStyle(color: AppColors.white)))).toList(),
                                    onChanged: (value) => setState(() => _defaultCopies = value!),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _savePreferences,
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.pink500, foregroundColor: AppColors.white, minimumSize: const Size(double.infinity, 40)),
                                child: const Text('Save Preferences'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // 4. Payment Methods (Placeholder)
                        const Text('Payment & Billing', style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(color: AppColors.white10, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.white20)),
                          padding: const EdgeInsets.all(16),
                          child: const Column(
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.payment, color: AppColors.pink400),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      'Payment methods are managed through Razorpay during checkout.',
                                      style: TextStyle(color: AppColors.white70, fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // 9. Login History
                        if (_loginHistory.isNotEmpty) ...[
                          const Text('Recent Login History', style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(color: AppColors.white10, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.white20)),
                            child: Column(
                              children: _loginHistory.map((login) => ListTile(
                                leading: const Icon(Icons.access_time, color: AppColors.purple200, size: 20),
                                title: Text(login, style: const TextStyle(color: AppColors.white, fontSize: 14)),
                              )).toList(),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // App Info
                        const Text('App Information', style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(color: AppColors.white10, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.white20)),
                          padding: const EdgeInsets.all(16),
                            child: Column(
                            children: [
                              _buildInfoRow('App Version', '1.0.0', Icons.info_outline),
                              const Divider(color: AppColors.white20, height: 24),
                              _buildClickableRow('Terms & Conditions', Icons.description, () => _openUrl('https://www.qprint.co.in/terms')),
                              const Divider(color: AppColors.white20, height: 24),
                              _buildClickableRow('Privacy Policy', Icons.privacy_tip, () => _openUrl('https://www.qprint.co.in/privacy')),
                              const Divider(color: AppColors.white20, height: 24),
                              _buildClickableRow('Support & Help', Icons.help_outline, () => _openUrl('mailto:support@qprint.co.in?subject=Customer App Support Request')),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // 7. Account Deletion & 8. Data Export
                        const Text('Account Management', style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(color: AppColors.white10, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.white20)),
                          child: Column(
                            children: [
                              _buildMenuTile('Export My Data', Icons.download, _exportData, iconColor: AppColors.blue500),
                              const Divider(color: AppColors.white20, height: 1),
                              _buildMenuTile('Delete Account', Icons.delete_forever, _deleteAccount, iconColor: AppColors.red500),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

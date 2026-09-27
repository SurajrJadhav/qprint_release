import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/favorites_service.dart';
import '../services/security_service.dart';
import '../services/session_service.dart';
import '../utils/auth_prefs.dart';
import '../utils/shop_qr_parser.dart';
import 'upload_screen.dart';
import 'files_screen.dart';
import 'expenses_screen.dart';
import 'favorites_screen.dart';
import 'map_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'refer_and_earn_screen.dart';
import 'wallet_screen.dart';
import 'dashboard_tour_overlay.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.initialShopId,
    this.initialSharedFilePaths,
  });

  /// When app opened via shop QR link (e.g. qprint://shop/123), pre-select this shop on upload tab.
  final int? initialShopId;
  /// When app opened via Android Share with documents, pass initial file paths
  /// into the upload tab so flow matches manual upload.
  final List<String>? initialSharedFilePaths;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  String _displayName = 'Customer';
  double? _walletBalance;
  bool _walletBalanceLoading = false;
  Timer? _walletRefreshTimer;
  bool _showDashboardTour = false;
  int? _initialShopIdForUpload;
  List<String>? _initialSharedFilePathsForUpload;
  final GlobalKey _bottomNavKey = GlobalKey();
  final GlobalKey _appBarActionsKey = GlobalKey();
  final _apiService = ApiService();
  final _locationService = LocationService();
  final _favoritesService = FavoritesService();
  StreamSubscription<Uri>? _appLinkSubscription;

  @override
  void initState() {
    super.initState();
    _initialShopIdForUpload = widget.initialShopId;
    _initialSharedFilePathsForUpload = widget.initialSharedFilePaths;
    if (widget.initialShopId != null) _currentIndex = 0;
    _loadDisplayName();
    _loadWalletBalance();
    _maybeShowDashboardTour();
    _listenToAppLinks();
    // Keep wallet balance fresh even when actions happen in other tabs (IndexedStack keeps state).
    _walletRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadWalletBalance();
    });
    _checkJailbreak();
    _setupSessionTimeout();
  }

  void _listenToAppLinks() {
    _appLinkSubscription = AppLinks().uriLinkStream.listen((Uri uri) {
      final id = parseShopIdFromQrContent(uri.toString());
      if (id != null && mounted) {
        setState(() {
          _initialShopIdForUpload = id;
          _currentIndex = 0;
        });
      }
    });
  }

  Future<void> _loadWalletBalance() async {
    if (!mounted) return;
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

  @override
  void dispose() {
    _appLinkSubscription?.cancel();
    _walletRefreshTimer?.cancel();
    SessionService.instance.clear();
    super.dispose();
  }

  Future<void> _checkJailbreak() async {
    try {
      final risk = await SecurityService.hasElevatedRisk;
      if (risk && mounted) {
        await showDialog(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.indigo900,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.yellow500),
            ),
            title: const Text(
              'Security Notice',
              style: TextStyle(color: AppColors.yellow300),
            ),
            content: const Text(
              'Your device appears to be modified (rooted/jailbroken or developer mode). '
              'Using this app on modified devices may pose security risks. '
              'Use at your own discretion.',
              style: TextStyle(color: AppColors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(color: AppColors.pink400)),
              ),
            ],
          ),
        );
      }
    } catch (_) {}
  }

  void _setupSessionTimeout() {
    SessionService.instance.touch();
    SessionService.instance.setOnIdleTimeout(() {
      if (!mounted) return;
      SessionService.instance.clear();
      _apiService.logout();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    });
  }

  Future<void> _loadDisplayName() async {
    var name = await readCachedDisplayName();
    if (!mounted) return;
    setState(() => _displayName = name);
    try {
      final profile = await _apiService.getProfile();
      final fromApi = profile['display_name'] ?? profile['full_name'];
      if (fromApi != null && fromApi.toString().trim().isNotEmpty) {
        name = fromApi.toString().trim();
        await writeCachedDisplayName(name);
        if (mounted) setState(() => _displayName = name);
      }
    } catch (_) {}
  }

  Future<void> _maybeShowDashboardTour() async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    final show = await DashboardTourOverlay.shouldShowTour();
    if (mounted && show) {
      setState(() => _showDashboardTour = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_showDashboardTour) return;
        OverlayEntry? entry;
        entry = OverlayEntry(
          builder: (ctx) => Positioned.fill(
            child: DashboardTourOverlay(
              bottomNavKey: _bottomNavKey,
              appBarActionsKey: _appBarActionsKey,
              onComplete: () {
                entry?.remove();
                if (mounted) setState(() => _showDashboardTour = false);
              },
            ),
          ),
        );
        Overlay.of(context).insert(entry!);
      });
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.indigo900,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.white20, width: 1),
        ),
        title: const Text(
          'Logout',
          style: TextStyle(
            color: AppColors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'Are you sure you want to logout?',
          style: TextStyle(
            color: AppColors.white70,
            fontSize: 16,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.white70,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.red500,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'Logout',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _apiService.logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiService>.value(value: _apiService),
        Provider<LocationService>.value(value: _locationService),
        Provider<FavoritesService>.value(value: _favoritesService),
      ],
      child: Listener(
        onPointerDown: (_) => SessionService.instance.touch(),
        child: Scaffold(
          body: Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  gradient: AppColors.backgroundGradient,
                ),
                child: IndexedStack(
                  index: _currentIndex,
                  children: [
                    UploadScreen(
                      onUploadSuccess: _loadWalletBalance,
                      initialShopId: _initialShopIdForUpload,
                      initialSharedFilePaths: _initialSharedFilePathsForUpload,
                    ),
                    const FilesScreen(),
                    const FavoritesScreen(),
                    const ExpensesScreen(),
                    const MapScreen(),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: KeyedSubtree(
          key: _bottomNavKey,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.white10,
              border: Border(
                top: BorderSide(color: AppColors.white20),
              ),
            ),
            child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
              // Reload preferences when switching to upload screen
              if (index == 0) {
                // Trigger reload in upload screen by using a key or callback
                // Since IndexedStack keeps state, we'll handle this in upload screen's visibility
              }
            },
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedItemColor: AppColors.pink500,
            unselectedItemColor: AppColors.white50,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.upload),
                label: 'Upload',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.folder),
                label: 'My Files',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.star),
                label: 'Favorites',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.attach_money),
                label: 'Expenses',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.map),
                label: 'Map',
              ),
            ],
          ),
        ),
        ),
        appBar: AppBar(
          title: Row(
            children: [
              const Text(
                'Q',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppColors.white,
                ),
              ),
              const Text(
                'print',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppColors.pink400,
                ),
              ),
            ],
          ),
          actions: [
            KeyedSubtree(
              key: _appBarActionsKey,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
            // Wallet balance (tappable -> Wallet screen)
            GestureDetector(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const WalletScreen()),
                );
                if (mounted) _loadWalletBalance();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.white10,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.white20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.account_balance_wallet, size: 18, color: AppColors.pink400),
                        const SizedBox(width: 6),
                        Text(
                          _walletBalanceLoading
                              ? '…'
                              : '₹${(_walletBalance ?? 0).toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            PopupMenuButton<String>(
              color: Colors.white,
              icon: CircleAvatar(
                backgroundColor: AppColors.pink500,
                child: Text(
                  _displayName.isNotEmpty ? _displayName[0].toUpperCase() : '?',
                  style: const TextStyle(color: AppColors.white),
                ),
              ),
              onSelected: (value) async {
                if (value == 'profile') {
                  final showTour = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (context) => const ProfileScreen()),
                  );
                  if (showTour == true && mounted) _maybeShowDashboardTour();
                } else if (value == 'wallet') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const WalletScreen()),
                  );
                } else if (value == 'refer') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ReferAndEarnScreen()),
                  );
                } else if (value == 'logout') {
                  _handleLogout();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'profile',
                  child: Row(
                    children: [
                      const Icon(Icons.person, color: AppColors.pink600, size: 22),
                      const SizedBox(width: 12),
                      Text(
                        'Profile',
                        style: TextStyle(
                          color: Colors.grey.shade900,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'wallet',
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_wallet, color: AppColors.pink600, size: 22),
                      const SizedBox(width: 12),
                      Text(
                        'Wallet',
                        style: TextStyle(
                          color: Colors.grey.shade900,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'refer',
                  child: Row(
                    children: [
                      const Icon(Icons.card_giftcard, color: AppColors.pink600, size: 22),
                      const SizedBox(width: 12),
                      Text(
                        'Refer & Earn',
                        style: TextStyle(
                          color: Colors.grey.shade900,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      const Icon(Icons.logout, color: AppColors.red500, size: 22),
                      const SizedBox(width: 12),
                      Text(
                        'Logout',
                        style: TextStyle(
                          color: Colors.grey.shade900,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

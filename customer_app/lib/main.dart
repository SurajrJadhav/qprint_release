import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'theme/app_colors.dart';
import 'utils/referral_sanitizer.dart';
import 'utils/shop_qr_parser.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'services/share_intent_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Runs when app is in background or terminated. System shows the notification.
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await NotificationService.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Qprint Customer',
      theme: AppTheme.theme,
      debugShowCheckedModeBanner: false,
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  bool _isAuthenticated = false;
  String? _initialReferralCode;
  int? _initialShopId;
  List<String>? _initialSharedFilePaths;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkReferralLink() async {
    try {
      final appLinks = AppLinks();
      final uri = await appLinks.getInitialLink();
      if (uri == null) return;
      // qprint://r/CODE or qprint://r/CODE/ -> path is /CODE or /CODE (sanitized)
      if (uri.host == 'r' && uri.pathSegments.isNotEmpty) {
        final code = sanitizeReferralCode(uri.pathSegments.first);
        if (code != null && code.isNotEmpty && mounted) {
          setState(() => _initialReferralCode = code);
        }
      }
    } catch (_) {}
  }

  Future<void> _checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingCompleted = prefs.getBool('onboarding_completed') ?? false;
    
    // Show onboarding first if not completed
    if (!onboardingCompleted) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const OnboardingScreen()),
          );
        }
      }
      return;
    }

    // If onboarding completed, check auth (token in Secure Storage or prefs)
    String? token;
    try {
      token = await const FlutterSecureStorage().read(key: 'qprint_auth_token');
    } catch (_) {}
    if (token == null) {
      token = prefs.getString('token');
    }
    final role = prefs.getString('role');

    // Only treat as authenticated if we have token, role is customer, and server accepts token.
    // Set cached token so validateToken (and later getShops etc.) use it without a second
    // secure-storage read—avoids Play Store builds failing when that read is flaky.
    bool authenticated = false;
    if (token != null && role == 'customer') {
      ApiService.setCachedToken(token);
      authenticated = await ApiService().validateToken();
    }

    if (mounted && !authenticated) {
      await _checkReferralLink();
    }
    int? initialShopId;
    if (authenticated) {
      try {
        final appLinks = AppLinks();
        final uri = await appLinks.getInitialLink();
        if (uri != null) {
          initialShopId = parseShopIdFromQrContent(uri.toString());
        }
      } catch (_) {}
    }
    List<String>? sharedPaths;
    if (authenticated) {
      try {
        final files = await ShareIntentService.instance.getInitialSharedFiles();
        if (files.isNotEmpty) {
          sharedPaths = files.map((f) => f.path).toList();
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _isAuthenticated = authenticated;
        _isLoading = false;
        _initialShopId = initialShopId;
        _initialSharedFilePaths = sharedPaths;
      });
      if (authenticated) {
        NotificationService.requestPermission();
        NotificationService.registerTokenWithBackend();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: AppColors.backgroundGradient,
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Q',
                  style: TextStyle(
                    fontSize: 80,
                    fontWeight: FontWeight.w900,
                    color: AppColors.white,
                  ),
                ),
                Text(
                  'print',
                  style: TextStyle(
                    fontSize: 80,
                    fontWeight: FontWeight.w900,
                    color: AppColors.pink400,
                  ),
                ),
                const SizedBox(height: 32),
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.pink500),
                ),
                const SizedBox(height: 16),
                Text(
                  'Loading...',
                  style: TextStyle(
                    color: AppColors.purple200,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isAuthenticated) {
      return DashboardScreen(
        initialShopId: _initialShopId,
        initialSharedFilePaths: _initialSharedFilePaths,
      );
    }
    if (_initialReferralCode != null) {
      return RegisterScreen(initialReferralCode: _initialReferralCode);
    }
    return const LoginScreen();
  }
}

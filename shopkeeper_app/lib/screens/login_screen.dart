import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/google_desktop_auth.dart';
import '../utils/safe_error.dart';
import 'dashboard_screen.dart';
import 'register_screen.dart';
import 'printer_setup_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpCodeController = TextEditingController();
  final _apiService = ApiService();
  bool _isLoading = false;
  String? _errorMessage;
  bool _loginWithOtp = false;
  bool _otpSent = false;

  @override
  void initState() {
    super.initState();
    _restoreSessionIfPossible();
  }

  /// When the app restarts (e.g. after Windows screen lock/sleep), token may still be in storage.
  /// Navigate to post-login screen so the user is not shown login again.
  Future<void> _restoreSessionIfPossible() async {
    try {
      final token = await _apiService.getToken();
      if (!mounted) return;
      if (token != null && token.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _navigateAfterLogin();
        });
      }
    } catch (_) {
      // Ignore: no token or storage error, stay on login screen
    }
  }

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    _otpCodeController.dispose();
    super.dispose();
  }

  void _navigateAfterLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PrinterSetupScreen()),
    );
  }

  Future<void> _handleSendOtp() async {
    final login = _loginController.text.trim();
    if (login.isEmpty) {
      setState(() => _errorMessage = 'Enter your email');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await _apiService.loginRequestOtp(login);
      if (mounted) {
        setState(() { _otpSent = true; _isLoading = false; _otpCodeController.clear(); });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _isLoading = false; _errorMessage = getSafeErrorMessage(e, 'login'); });
      }
    }
  }

  Future<void> _handleVerifyOtp() async {
    final code = _otpCodeController.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'Enter the 6-digit code');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final result = await _apiService.loginVerifyOtp(_loginController.text.trim(), code);
      if (mounted) {
        setState(() => _isLoading = false);
        if (result['needs_signup'] == true) {
          final email = result['email'] as String?;
          final signupToken = result['signup_token'] as String?;
          if (email != null && signupToken != null) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => RegisterScreen(
                  initialEmail: email,
                  initialSignupToken: signupToken,
                ),
              ),
            );
            return;
          }
        }
        _navigateAfterLogin();
      }
    } catch (e) {
      if (mounted) {
        setState(() { _isLoading = false; _errorMessage = getSafeErrorMessage(e, 'login'); });
      }
    }
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _apiService.login(
        _loginController.text.trim(),
        _passwordController.text,
      );
      
      if (mounted) {
        setState(() => _isLoading = false);
        _navigateAfterLogin();
      }
    } catch (e) {
      setState(() {
        _errorMessage = getSafeErrorMessage(e, 'login');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    final clientId = AppConfig.googleDesktopClientId;
    if (clientId == null || clientId.isEmpty) {
      setState(() => _errorMessage = 'Google Sign-In is not configured for this build.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final idToken = await GoogleDesktopAuth(clientId: clientId).signIn();
      final result = await _apiService.loginWithGoogle(idToken);
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (result['needs_signup'] == true) {
        final email = result['email'] as String?;
        final signupToken = result['signup_token'] as String?;
        final fullName = result['full_name'] as String?;
        if (email != null && signupToken != null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => RegisterScreen(
                initialEmail: email,
                initialSignupToken: signupToken,
                initialFullName: fullName,
              ),
            ),
          );
          return;
        }
        setState(() => _errorMessage = 'Complete shop registration to continue.');
        return;
      }
      _navigateAfterLogin();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = getSafeErrorMessage(e, 'login');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF312E81), Color(0xFF581C87), Color(0xFF9D174D)],
          ),
        ),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 450),
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                Image.asset(
                  'assets/logo.png',
                  height: 88,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.pinkAccent.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.print_rounded,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                // Welcome Text
                const Text(
                  'Welcome Back!',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sign in to manage your shop queue',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 48),

                // Password vs OTP
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Password')),
                    ButtonSegment(value: true, label: Text('OTP')),
                  ],
                  selected: {_loginWithOtp},
                  onSelectionChanged: (v) {
                    setState(() { _loginWithOtp = v.first; _errorMessage = null; _otpSent = false; });
                  },
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) return Colors.pinkAccent;
                      return Colors.white.withOpacity(0.1);
                    }),
                  ),
                ),
                const SizedBox(height: 16),

                // Form
                if (!_loginWithOtp) ...[
                  TextField(
                    controller: _loginController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Email or mobile number',
                      labelStyle: const TextStyle(color: Colors.white70),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.pinkAccent),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.person, color: Colors.white70),
                      filled: true,
                      fillColor: Colors.black.withOpacity(0.1),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      labelStyle: const TextStyle(color: Colors.white70),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.pinkAccent),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.lock, color: Colors.white70),
                      filled: true,
                      fillColor: Colors.black.withOpacity(0.1),
                    ),
                    onSubmitted: (_) => _handleLogin(),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.pinkAccent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Login', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ] else if (!_otpSent) ...[
                  TextField(
                    controller: _loginController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Email',
                      labelStyle: const TextStyle(color: Colors.white70),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.pinkAccent),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.email, color: Colors.white70),
                      filled: true,
                      fillColor: Colors.black.withOpacity(0.1),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleSendOtp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.pinkAccent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Send OTP', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ] else ...[
                  Text(
                    'Code sent to ${_loginController.text.trim()}',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _otpCodeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: '6-digit code',
                      labelStyle: const TextStyle(color: Colors.white70),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.pinkAccent),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.pin, color: Colors.white70),
                      filled: true,
                      fillColor: Colors.black.withOpacity(0.1),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => setState(() { _otpSent = false; _errorMessage = null; }),
                        child: const Text('Change', style: TextStyle(color: Colors.pinkAccent)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 56,
                          child: ElevatedButton(
                            onPressed: (_isLoading || _otpCodeController.text.trim().length != 6) ? null : _handleVerifyOtp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.pinkAccent,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : const Text('Verify & Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                if (AppConfig.googleDesktopClientId != null) ...[
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.white.withOpacity(0.25))),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                      ),
                      Expanded(child: Divider(color: Colors.white.withOpacity(0.25))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _handleGoogleSignIn,
                      icon: const Icon(Icons.g_mobiledata, size: 28, color: Colors.white),
                      label: const Text(
                        'Continue with Google',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withOpacity(0.35)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],

                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                const SizedBox(height: 16),
                
                if (!_loginWithOtp)
                // Forgot Password Link
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                    );
                  },
                  child: const Text(
                    'Forgot Password?',
                    style: TextStyle(
                      color: Colors.pinkAccent,
                    ),
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Register Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Don't have a shop account? ",
                      style: TextStyle(color: Colors.white60),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const RegisterScreen()),
                        );
                      },
                      child: const Text(
                        'Register Now',
                        style: TextStyle(
                          color: Colors.pinkAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

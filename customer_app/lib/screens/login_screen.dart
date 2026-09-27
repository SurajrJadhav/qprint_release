import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../theme/app_colors.dart';
import '../utils/safe_error.dart';
import 'register_screen.dart';
import 'dashboard_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpCodeController = TextEditingController();
  final _apiService = ApiService();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _loginWithOtp = false;
  bool _otpSent = false;

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    _otpCodeController.dispose();
    super.dispose();
  }

  void _navigateAfterLogin(Map<String, dynamic> result) {
    if (result['role'] != 'customer') {
      setState(() => _errorMessage = 'This app is for customers only');
      return;
    }
    NotificationService.requestPermission();
    NotificationService.registerTokenWithBackend();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
    );
  }

  Future<void> _handleSendOtp() async {
    final login = _loginController.text.trim();
    if (login.isEmpty) {
      setState(() => _errorMessage = 'Enter your email');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _apiService.loginRequestOtp(login);
      if (mounted) {
        setState(() {
          _otpSent = true;
          _isLoading = false;
          _otpCodeController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = getSafeErrorMessage(e, 'login');
        });
      }
    }
  }

  Future<void> _handleVerifyOtp() async {
    final code = _otpCodeController.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'Enter the 6-digit code');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
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
        _navigateAfterLogin(result);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = getSafeErrorMessage(e, 'login');
        });
      }
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _apiService.login(
        _loginController.text.trim(),
        _passwordController.text,
      );

      // Save login to history (non-critical; don't fail login if this throws)
      if (result['role'] == 'customer') {
        try {
          final prefs = await SharedPreferences.getInstance();
          final now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
          final history = prefs.getStringList('login_history') ?? [];
          history.insert(0, now);
          if (history.length > 10) history.removeRange(10, history.length);
          await prefs.setStringList('login_history', history);
        } catch (_) {
          // Ignore; login history is non-critical
        }
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _navigateAfterLogin(result);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = getSafeErrorMessage(e, 'login');
        });
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    final serverClientId = AppConfig.googleServerClientId;
    if (serverClientId == null || serverClientId.isEmpty) {
      setState(() => _errorMessage = 'Google Sign-In is not configured for this build.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final googleSignIn = GoogleSignIn(
        scopes: const ['email', 'profile'],
        serverClientId: serverClientId,
      );
      final account = await googleSignIn.signIn();
      if (account == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception('Google did not return an ID token. Check GOOGLE_SERVER_CLIENT_ID.');
      }
      final result = await _apiService.loginWithGoogle(idToken);
      if (mounted) {
        setState(() => _isLoading = false);
        _navigateAfterLogin(result);
      }
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
          gradient: AppColors.backgroundGradient,
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo
                    Image.asset(
                      'assets/logo.png',
                      height: 88,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Q', style: TextStyle(fontSize: 64, fontWeight: FontWeight.w900, color: Colors.white)),
                          Text('print', style: TextStyle(fontSize: 64, fontWeight: FontWeight.w900, color: AppColors.pink400)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Sign in to your account',
                      style: TextStyle(
                        color: AppColors.purple200,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 48),

                    // Login Form
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.white10,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.white20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: SegmentedButton<bool>(
                                  segments: const [
                                    ButtonSegment(value: false, label: Text('Password')),
                                    ButtonSegment(value: true, label: Text('OTP')),
                                  ],
                                  selected: {_loginWithOtp},
                                  onSelectionChanged: (v) {
                                    setState(() {
                                      _loginWithOtp = v.first;
                                      _errorMessage = null;
                                      _otpSent = false;
                                    });
                                  },
                                  style: ButtonStyle(
                                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                                      if (states.contains(WidgetState.selected)) return AppColors.pink500;
                                      return AppColors.white10;
                                    }),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (!_loginWithOtp) ...[
                            TextFormField(
                              controller: _loginController,
                              decoration: const InputDecoration(
                                labelText: 'Email or mobile number',
                                prefixIcon: Icon(Icons.person),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your email or mobile number';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                    color: AppColors.white70,
                                  ),
                                  onPressed: () {
                                    setState(() => _obscurePassword = !_obscurePassword);
                                  },
                                ),
                              ),
                              obscureText: _obscurePassword,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your password';
                                }
                                return null;
                              },
                            ),
                          ] else if (!_otpSent) ...[
                            TextFormField(
                              controller: _loginController,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email),
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _isLoading ? null : _handleSendOtp,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ).copyWith(backgroundColor: WidgetStateProperty.all(AppColors.pink500)),
                              child: _isLoading
                                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Text('Send OTP', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                          ] else ...[
                            Text('Code sent to ${_loginController.text.trim()}', style: const TextStyle(color: AppColors.purple200, fontSize: 14)),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _otpCodeController,
                              decoration: const InputDecoration(
                                labelText: '6-digit code',
                                prefixIcon: Icon(Icons.pin),
                              ),
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                TextButton(
                                  onPressed: () => setState(() { _otpSent = false; _errorMessage = null; }),
                                  child: const Text('Change', style: TextStyle(color: AppColors.pink400)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: (_isLoading || _otpCodeController.text.trim().length != 6) ? null : _handleVerifyOtp,
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ).copyWith(backgroundColor: WidgetStateProperty.all(AppColors.pink500)),
                                    child: _isLoading
                                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                        : const Text('Verify & Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.red500.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(_errorMessage!, style: const TextStyle(color: AppColors.red300)),
                            ),
                          ],
                          if (!_loginWithOtp) ...[
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: _isLoading ? null : _handleLogin,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ).copyWith(backgroundColor: WidgetStateProperty.all(AppColors.pink500)),
                              child: _isLoading
                                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Text('Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                          ],
                          if (AppConfig.googleServerClientId != null) ...[
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                const Expanded(child: Divider(color: AppColors.white20)),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text('or', style: TextStyle(color: AppColors.purple200.withOpacity(0.9))),
                                ),
                                const Expanded(child: Divider(color: AppColors.white20)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: _isLoading ? null : _handleGoogleSignIn,
                              icon: const Icon(Icons.g_mobiledata, size: 28, color: Colors.white),
                              label: const Text(
                                'Continue with Google',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                side: const BorderSide(color: AppColors.white20),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    if (!_loginWithOtp)
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ForgotPasswordScreen(),
                            ),
                          );
                        },
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(color: AppColors.pink400),
                        ),
                      ),
                    if (_loginWithOtp) const SizedBox(height: 8),

                    const SizedBox(height: 8),

                    // Register Link
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const RegisterScreen(),
                          ),
                        );
                      },
                      child: const Text(
                        "Don't have an account? Register",
                        style: TextStyle(color: AppColors.pink400),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

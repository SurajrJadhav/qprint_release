import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../theme/app_colors.dart';
import '../utils/safe_error.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    this.initialReferralCode,
    this.initialEmail,
    this.initialSignupToken,
  });

  final String? initialReferralCode;
  /// Pre-verified email and signup token from login OTP (account not found) flow.
  final String? initialEmail;
  final String? initialSignupToken;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  late final TextEditingController _referralCodeController;
  final _apiService = ApiService();
  int _step = 1; // 1: email + send OTP, 2: verify OTP, 3: full form
  String? _signupToken;
  String? _verifiedEmail;
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _referralCodeController = TextEditingController(text: widget.initialReferralCode?.trim() ?? '');
    if (widget.initialEmail != null && widget.initialSignupToken != null) {
      _verifiedEmail = widget.initialEmail;
      _signupToken = widget.initialSignupToken;
      _emailController.text = widget.initialEmail!;
      _step = 3;
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _otpController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _referralCodeController.dispose();
    super.dispose();
  }

  Future<void> _handleSendOtp() async {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Please enter your email');
      return;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _errorMessage = 'Please enter a valid email');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _apiService.registerSendOtp(email: email);
      if (mounted) {
        setState(() {
          _step = 2;
          _isLoading = false;
          _otpController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = getSafeErrorMessage(e, 'register');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleVerifyOtp() async {
    final code = _otpController.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'Enter the 6-digit code');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final res = await _apiService.registerVerifyOtp(
        email: _emailController.text.trim(),
        code: code,
      );
      if (mounted) {
        _signupToken = res['signup_token'] as String?;
        _verifiedEmail = res['email'] as String?;
        if (_verifiedEmail != null) _emailController.text = _verifiedEmail!;
        setState(() {
          _step = 3;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = getSafeErrorMessage(e, 'register');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleRegister() async {
    if (_signupToken == null || _verifiedEmail == null) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final refCode = _referralCodeController.text.trim();
      final email = _verifiedEmail!;
      final phone = _phoneController.text.replaceAll(RegExp(r'\D'), '');
      final result = await _apiService.register(
        fullName: _fullNameController.text.trim(),
        email: email,
        phone: phone,
        password: _passwordController.text,
        referralCode: refCode.isEmpty ? null : refCode,
        signupToken: _signupToken!,
      );

      if (mounted) {
        if (result != null && result['token'] != null) {
          NotificationService.requestPermission();
          NotificationService.registerTokenWithBackend();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const DashboardScreen()),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Registration successful! Please login.'),
              backgroundColor: AppColors.green500,
            ),
          );
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = getSafeErrorMessage(e, 'register');
          _isLoading = false;
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
                      'Create your account',
                      style: TextStyle(
                        color: AppColors.purple200,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Register Form (step 1: email, step 2: OTP, step 3: full form)
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
                          // Step 1: Email + Send OTP (email only)
                          if (_step == 1) ...[
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Email *',
                                prefixIcon: Icon(Icons.email),
                              ),
                            ),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.red500.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(_errorMessage!, style: const TextStyle(color: AppColors.red300)),
                              ),
                            ],
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: _isLoading ? null : _handleSendOtp,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ).copyWith(backgroundColor: WidgetStateProperty.all(AppColors.pink500)),
                              child: _isLoading
                                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
                                  : const Text('Send verification code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                          ],
                          // Step 2: Verify OTP
                          if (_step == 2) ...[
                            Text(
                              'We sent a 6-digit code to ${_emailController.text.trim()}. Enter it below.',
                              style: const TextStyle(color: AppColors.purple200, fontSize: 14),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _otpController,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
                              maxLength: 6,
                              decoration: const InputDecoration(
                                labelText: 'Verification code',
                                hintText: '000000',
                                prefixIcon: Icon(Icons.pin),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.red500.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(_errorMessage!, style: const TextStyle(color: AppColors.red300)),
                              ),
                            ],
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: (_isLoading || _otpController.text.trim().length != 6) ? null : _handleVerifyOtp,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ).copyWith(backgroundColor: WidgetStateProperty.all(AppColors.pink500)),
                              child: _isLoading
                                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
                                  : const Text('Verify', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                            TextButton(
                              onPressed: () => setState(() { _step = 1; _errorMessage = null; _otpController.clear(); }),
                              child: const Text('Use a different email', style: TextStyle(color: AppColors.purple200)),
                            ),
                          ],
                          // Step 3: Full form
                          if (_step == 3) ...[
                            Text(
                              'Email verified: $_verifiedEmail',
                              style: const TextStyle(color: AppColors.purple200, fontSize: 12),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _fullNameController,
                              decoration: const InputDecoration(
                                labelText: 'Full Name *',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) return 'Please enter your full name';
                                if (value.length < 2 || value.length > 50) return 'Name must be between 2 and 50 characters';
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            // Email (read-only; verified in step 1)
                            TextFormField(
                              controller: _emailController,
                              readOnly: true,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Email (verified)',
                                prefixIcon: Icon(Icons.email),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Phone Number (10 digits) *',
                                prefixIcon: Icon(Icons.phone),
                              ),
                              maxLength: 10,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your phone number';
                                }
                                final cleanPhone = value.replaceAll(RegExp(r'\D'), '');
                                if (cleanPhone.length != 10) {
                                  return 'Phone number must be 10 digits';
                                }
                                return null;
                              },
                            ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              labelText: 'Password (min 8 characters) *',
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
                                return 'Please enter a password';
                              }
                              if (value.length < 8) {
                                return 'Password must be at least 8 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _confirmPasswordController,
                            decoration: const InputDecoration(
                              labelText: 'Confirm Password *',
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                            obscureText: true,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please confirm your password';
                              }
                              if (value != _passwordController.text) {
                                return 'Passwords do not match';
                              }
                              return null;
                            },
                          ),
                          if (widget.initialReferralCode != null && widget.initialReferralCode!.trim().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Referred by a friend',
                              style: TextStyle(color: AppColors.purple200, fontSize: 12),
                            ),
                          ],
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _referralCodeController,
                            decoration: const InputDecoration(
                              labelText: 'Referral code (optional)',
                              prefixIcon: Icon(Icons.card_giftcard),
                              hintText: 'Enter code if a friend referred you',
                            ),
                          ),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 16),
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
                          ],
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: _isLoading ? null : _handleRegister,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ).copyWith(
                              backgroundColor: WidgetStateProperty.all(
                                AppColors.pink500,
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.white,
                                    ),
                                  )
                                : const Text(
                                    'Create Account',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ],
                      ],
                    ),
                    ),

                    const SizedBox(height: 24),

                    // Login Link
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                        );
                      },
                      child: const Text(
                        'Already have an account? Sign In',
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

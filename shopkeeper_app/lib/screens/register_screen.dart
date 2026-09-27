import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../utils/safe_error.dart';
import 'location_picker_screen.dart';
import 'printer_setup_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    this.initialEmail,
    this.initialSignupToken,
    this.initialFullName,
  });

  /// Pre-verified email and signup token from login OTP / Google (account not found) flow.
  final String? initialEmail;
  final String? initialSignupToken;
  final String? initialFullName;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _shopNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _addressController = TextEditingController();
  final _latController = TextEditingController();
  final _longController = TextEditingController();
  final _apiService = ApiService();
  int _step = 1;
  String? _signupToken;
  String? _verifiedEmail;
  bool _isLoading = false;
  String? _errorMessage;
  double? _lat;
  double? _long;
  bool _locationLoading = false;
  bool _useManualEntry = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail != null && widget.initialSignupToken != null) {
      _verifiedEmail = widget.initialEmail;
      _signupToken = widget.initialSignupToken;
      _emailController.text = widget.initialEmail!;
      if (widget.initialFullName != null && widget.initialFullName!.trim().isNotEmpty) {
        _fullNameController.text = widget.initialFullName!.trim();
      }
      _step = 3;
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _shopNameController.dispose();
    _emailController.dispose();
    _otpController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _addressController.dispose();
    _latController.dispose();
    _longController.dispose();
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
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await _apiService.registerSendOtp(email: email);
      if (mounted) {
        setState(() { _step = 2; _isLoading = false; _otpController.clear(); });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _errorMessage = getSafeErrorMessage(e, 'register'); _isLoading = false; });
      }
    }
  }

  Future<void> _handleVerifyOtp() async {
    final code = _otpController.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'Enter the 6-digit code');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final res = await _apiService.registerVerifyOtp(
        email: _emailController.text.trim(),
        code: code,
      );
      if (mounted) {
        _signupToken = res['signup_token'] as String?;
        _verifiedEmail = res['email'] as String?;
        if (_verifiedEmail != null) _emailController.text = _verifiedEmail!;
        setState(() { _step = 3; _isLoading = false; });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _errorMessage = getSafeErrorMessage(e, 'register'); _isLoading = false; });
      }
    }
  }

  Future<void> _getLocation() async {
    setState(() {
      _locationLoading = true;
      _errorMessage = null;
    });

    try {
      final isWindows = Platform.isWindows;

      if (!isWindows) {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          setState(() {
            _errorMessage = 'Location services are disabled. Please enable them in your device settings.';
            _locationLoading = false;
          });
          return;
        }
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _errorMessage = 'Location permissions are denied. Please allow location access to register your shop.';
            _locationLoading = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _errorMessage = 'Location permissions are permanently denied. Please enable them in device settings.';
          _locationLoading = false;
        });
        return;
      }

      final accuracy = isWindows ? LocationAccuracy.medium : LocationAccuracy.high;
      Position? position;
      if (isWindows) {
        position = await Geolocator.getLastKnownPosition();
        if (position == null) {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: accuracy,
            timeLimit: const Duration(seconds: 15),
          );
        }
      } else {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: accuracy,
        );
      }

      if (mounted && position != null) {
        final p = position!;
        setState(() {
          _lat = p.latitude;
          _long = p.longitude;
          _locationLoading = false;
        });
      } else if (mounted) {
        setState(() {
          _errorMessage = 'Could not get location. Use "Set Location on Map" or enter coordinates manually.';
          _locationLoading = false;
          _useManualEntry = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not get location: ${e.toString()}. You can enter coordinates manually below.';
          _locationLoading = false;
          _useManualEntry = true;
        });
      }
    }
  }

  void _updateLocationFromManualEntry() {
    if (_latController.text.isNotEmpty && _longController.text.isNotEmpty) {
      final lat = double.tryParse(_latController.text.trim());
      final long = double.tryParse(_longController.text.trim());
      if (lat != null && long != null && lat != 0.0 && long != 0.0) {
        setState(() {
          _lat = lat;
          _long = long;
          _errorMessage = null;
        });
      }
    }
  }

  Future<void> _handleRegister() async {
    // Update location from manual entry if needed
    if (_useManualEntry && (_lat == null || _long == null)) {
      _updateLocationFromManualEntry();
    }

    if (!_formKey.currentState!.validate()) return;

    // Location is REQUIRED for shopkeeper registration
    if (_lat == null || _long == null) {
      setState(() {
        _errorMessage = 'Location is required. Please click "Get Shop Location" or enter coordinates manually.';
      });
      return;
    }

    // Validate location is not 0,0 (invalid/default location)
    if (_lat == 0.0 && _long == 0.0) {
      setState(() {
        _errorMessage = 'Invalid location. Please provide valid coordinates (not 0,0).';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    if (_signupToken == null || _verifiedEmail == null) {
      setState(() { _errorMessage = 'Please verify your email first.'; _isLoading = false; });
      return;
    }
    final email = _verifiedEmail!;
    final phone = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    try {
      final result = await _apiService.register(
        fullName: _fullNameController.text.trim(),
        email: email,
        phone: phone,
        password: _passwordController.text,
        shopName: _shopNameController.text.trim(),
        address: _addressController.text.trim(),
        lat: _lat!,
        long: _long!,
        signupToken: _signupToken!,
      );

      if (mounted) {
        if (result != null && result['token'] != null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const PrinterSetupScreen()),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Registration successful! Please login.'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = getSafeErrorMessage(e, 'register');
        _isLoading = false;
      });
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
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/logo.png',
                        height: 72,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Join Qprint',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Register New Shop',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 32),
                      if (_step == 1) ...[
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Email *',
                            labelStyle: const TextStyle(color: Colors.white70),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: Colors.pinkAccent),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                        ],
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _handleSendOtp,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.pinkAccent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _isLoading
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Send verification code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ],
                      if (_step == 2) ...[
                        Text(
                          'We sent a 6-digit code to ${_emailController.text.trim()}. Enter it below.',
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _otpController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Verification code',
                            hintText: '000000',
                            labelStyle: const TextStyle(color: Colors.white70),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: Colors.pinkAccent),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                        ],
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: (_isLoading || _otpController.text.trim().length != 6) ? null : _handleVerifyOtp,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.pinkAccent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _isLoading
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Verify', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        TextButton(
                          onPressed: () => setState(() { _step = 1; _errorMessage = null; _otpController.clear(); }),
                          child: const Text('Use a different email', style: TextStyle(color: Colors.white70)),
                        ),
                      ],
                      if (_step == 3) ...[
                      Text(
                        'Email verified: $_verifiedEmail',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _fullNameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Shopkeeper Name *',
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
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your name';
                          }
                          if (value.length < 2 || value.length > 50) {
                            return 'Name must be between 2 and 50 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _shopNameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Shop Name *',
                          labelStyle: const TextStyle(color: Colors.white70),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: Colors.pinkAccent),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.store, color: Colors.white70),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter shop name';
                          }
                          if (value.length < 2 || value.length > 100) {
                            return 'Shop name must be between 2 and 100 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailController,
                        readOnly: true,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Email (verified)',
                          labelStyle: TextStyle(color: Colors.white70),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24),
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.pinkAccent),
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                          ),
                          prefixIcon: Icon(Icons.email, color: Colors.white70),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Phone Number (10 digits) *',
                          labelStyle: const TextStyle(color: Colors.white70),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: Colors.pinkAccent),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.phone, color: Colors.white70),
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
                        obscureText: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Password (min 8 characters) *',
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
                        ),
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
                        obscureText: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Confirm Password *',
                          labelStyle: const TextStyle(color: Colors.white70),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: Colors.pinkAccent),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.lock_outline, color: Colors.white70),
                        ),
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
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _addressController,
                        style: const TextStyle(color: Colors.white),
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'Shop Address *',
                          labelStyle: const TextStyle(color: Colors.white70),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: Colors.pinkAccent),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.location_on, color: Colors.white70),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter shop address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      // Map-based location picker button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => LocationPickerScreen(
                                  initialLat: _lat,
                                  initialLong: _long,
                                ),
                              ),
                            );
                            if (result != null) {
                              setState(() {
                                _lat = result['lat'] as double;
                                _long = result['long'] as double;
                                if (result['address'] != null && result['address'].toString().isNotEmpty) {
                                  _addressController.text = result['address'].toString();
                                }
                                _errorMessage = null;
                              });
                            }
                          },
                          icon: const Icon(Icons.map, color: Colors.white),
                          label: const Text(
                            'Set Location on Map *',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.pinkAccent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Quick location button (fallback)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _locationLoading ? null : _getLocation,
                          icon: _locationLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white70,
                                  ),
                                )
                              : const Icon(Icons.my_location, color: Colors.white70),
                          label: Text(
                            _locationLoading
                                ? 'Getting location...'
                                : (_lat != null && _long != null)
                                    ? 'Location captured ✓'
                                    : 'Quick: Get Current Location',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.white.withOpacity(0.3)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      if (_lat != null && _long != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Coordinates: ${_lat!.toStringAsFixed(6)}, ${_long!.toStringAsFixed(6)}',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.redAccent),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                      if (_useManualEntry || (_errorMessage != null && _errorMessage!.contains('Could not get location'))) ...[
                        const SizedBox(height: 16),
                        const Divider(color: Colors.white24),
                        const SizedBox(height: 8),
                        Text(
                          'Enter Coordinates Manually',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'If location detection failed, enter your shop\'s latitude and longitude. You can find these using Google Maps - right-click your location and copy the coordinates.',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _latController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: 'Latitude *',
                                  hintText: 'e.g., 17.3850',
                                  labelStyle: const TextStyle(color: Colors.white70),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(color: Colors.pinkAccent),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  prefixIcon: const Icon(Icons.north, color: Colors.white70),
                                ),
                                onChanged: (_) => _updateLocationFromManualEntry(),
                                validator: (value) {
                                  if (_useManualEntry && (value == null || value.isEmpty)) {
                                    return 'Required if auto-location fails';
                                  }
                                  if (value != null && value.isNotEmpty) {
                                    final lat = double.tryParse(value.trim());
                                    if (lat == null) return 'Invalid number';
                                    if (lat == 0.0) return 'Cannot be 0';
                                    if (lat < -90 || lat > 90) return 'Must be -90 to 90';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _longController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: 'Longitude *',
                                  hintText: 'e.g., 78.4867',
                                  labelStyle: const TextStyle(color: Colors.white70),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(color: Colors.pinkAccent),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  prefixIcon: const Icon(Icons.east, color: Colors.white70),
                                ),
                                onChanged: (_) => _updateLocationFromManualEntry(),
                                validator: (value) {
                                  if (_useManualEntry && (value == null || value.isEmpty)) {
                                    return 'Required if auto-location fails';
                                  }
                                  if (value != null && value.isNotEmpty) {
                                    final long = double.tryParse(value.trim());
                                    if (long == null) return 'Invalid number';
                                    if (long == 0.0) return 'Cannot be 0';
                                    if (long < -180 || long > 180) return 'Must be -180 to 180';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _useManualEntry = !_useManualEntry;
                              if (!_useManualEntry) {
                                _latController.clear();
                                _longController.clear();
                              }
                            });
                          },
                          icon: Icon(
                            _useManualEntry ? Icons.visibility_off : Icons.visibility,
                            color: Colors.white70,
                            size: 18,
                          ),
                          label: Text(
                            _useManualEntry ? 'Hide manual entry' : 'Always show manual entry',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: (_isLoading || _lat == null || _long == null) ? null : _handleRegister,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: (_lat == null || _long == null) 
                                ? Colors.grey 
                                : Colors.pinkAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  (_lat == null || _long == null) 
                                      ? 'Location Required' 
                                      : 'Register Shop',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                      ],
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Already have an account? Login',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

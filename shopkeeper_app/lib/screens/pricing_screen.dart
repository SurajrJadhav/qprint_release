import 'package:flutter/material.dart';

import '../services/api_service.dart';

class PricingScreen extends StatefulWidget {
  const PricingScreen({super.key});

  @override
  State<PricingScreen> createState() => _PricingScreenState();
}

class _PricingScreenState extends State<PricingScreen> {
  final _apiService = ApiService();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  String? _successMessage;

  double? _platformBw;
  double? _platformColor;

  late final TextEditingController _priceBwController;
  late final TextEditingController _priceColorController;
  late final TextEditingController _doubleSidedFactorController;

  @override
  void initState() {
    super.initState();
    _priceBwController = TextEditingController();
    _priceColorController = TextEditingController();
    _doubleSidedFactorController = TextEditingController();
    _fetchPricing();
  }

  @override
  void dispose() {
    _priceBwController.dispose();
    _priceColorController.dispose();
    _doubleSidedFactorController.dispose();
    super.dispose();
  }

  Future<void> _fetchPricing() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });
    try {
      final profile = await _apiService.getProfile();
      final bw = profile['price_per_page_bw'];
      final color = profile['price_per_page_color'];
      final factor = profile['double_sided_factor'];
      final platformBw = profile['platform_price_per_page_bw'];
      final platformColor = profile['platform_price_per_page_color'];
      if (!mounted) return;
      setState(() {
        _platformBw = platformBw is num ? platformBw.toDouble() : null;
        _platformColor = platformColor is num ? platformColor.toDouble() : null;
        _priceBwController.text = bw != null ? (bw as num).toString() : '';
        _priceColorController.text = color != null ? (color as num).toString() : '';
        _doubleSidedFactorController.text = factor != null ? (factor as num).toString() : '';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _savePricing() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _successMessage = null;
    });
    try {
      double? bw = double.tryParse(_priceBwController.text.trim());
      double? color = double.tryParse(_priceColorController.text.trim());
      double? factor = double.tryParse(_doubleSidedFactorController.text.trim());
      if (_priceBwController.text.trim().isEmpty) bw = null;
      if (_priceColorController.text.trim().isEmpty) color = null;
      if (_doubleSidedFactorController.text.trim().isEmpty) factor = null;

      if (bw == null && color == null && factor == null) {
        setState(() {
          _errorMessage = 'Enter at least one value, or use -1 to clear to platform default.';
          _isSaving = false;
        });
        return;
      }

      await _apiService.updateShopPricing(
        pricePerPageBw: bw,
        pricePerPageColor: color,
        doubleSidedFactor: factor,
      );

      if (!mounted) return;
      setState(() {
        _successMessage = 'Pricing updated.';
        _isSaving = false;
      });
      await _fetchPricing();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isSaving = false;
      });
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? helperText,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.8)),
        helperText: helperText,
        helperStyle: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
        prefixIcon: Icon(icon, color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.08),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.pinkAccent, width: 2),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF312E81), Color(0xFF581C87), Color(0xFF9D174D)],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.currency_rupee, color: Colors.white),
                            const SizedBox(width: 10),
                            const Text(
                              'Pricing',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: _isSaving ? null : _fetchPricing,
                              tooltip: 'Refresh',
                              icon: const Icon(Icons.refresh, color: Colors.white70),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Customers will see these rates when they select your shop for queue printing.',
                          style: TextStyle(color: Colors.white.withOpacity(0.7)),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.15)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Platform default (used when you leave fields blank)',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'B&W: ₹${(_platformBw ?? 1).toStringAsFixed(2)}/page  •  Color: ₹${(_platformColor ?? 10).toStringAsFixed(2)}/page',
                                style: TextStyle(color: Colors.white.withOpacity(0.75)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_errorMessage != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red.withOpacity(0.4)),
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
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.green.withOpacity(0.4)),
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
                          controller: _priceBwController,
                          label: 'B&W price per page (₹) — leave blank for default',
                          icon: Icons.currency_rupee,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          helperText: 'Use -1 to clear back to default.',
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: _priceColorController,
                          label: 'Color price per page (₹) — leave blank for default',
                          icon: Icons.palette_outlined,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          helperText: 'Use -1 to clear back to default.',
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: _doubleSidedFactorController,
                          label: 'Double-sided factor (0 to 1) — leave blank for full price',
                          icon: Icons.flip_to_front,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          helperText: 'Example: 0.5 = half price for double-sided.',
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: _isSaving ? null : _savePricing,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.save),
                            label: Text(_isSaving ? 'Saving...' : 'Save pricing'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.pinkAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}


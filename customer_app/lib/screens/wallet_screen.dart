import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../theme/app_colors.dart';
import '../services/api_service.dart';
import '../services/razorpay_service.dart';
import '../utils/safe_error.dart';
import 'refer_and_earn_screen.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final _apiService = ApiService();
  final _razorpayService = RazorpayService();

  double _balance = 0;
  List<dynamic> _transactions = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isToppingUp = false;

  @override
  void initState() {
    super.initState();
    _razorpayService.init();
    _load();
  }

  @override
  void dispose() {
    _razorpayService.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final balance = await _apiService.getWalletBalance();
      final txData = await _apiService.getWalletTransactions(limit: 50, offset: 0);
      final list = txData['transactions'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _balance = balance;
          _transactions = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = getSafeErrorMessage(e, 'wallet');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _startTopup() async {
    final amount = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final controller = TextEditingController(text: '100');
        return AlertDialog(
          backgroundColor: AppColors.indigo900,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.white20)),
          title: const Text('Add money to wallet', style: TextStyle(color: AppColors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter amount (₹10 – ₹10,000)', style: TextStyle(color: AppColors.purple200)),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppColors.white),
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  prefixStyle: const TextStyle(color: AppColors.white70),
                  hintText: '100',
                  hintStyle: const TextStyle(color: AppColors.white50),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.white30)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [100, 500, 1000].map((a) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text('₹$a'),
                      onPressed: () {
                        controller.text = a.toString();
                      },
                      backgroundColor: AppColors.white10,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppColors.white70))),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(controller.text.replaceAll(RegExp(r'[^\d.]'), ''));
                if (v != null && v >= 10 && v <= 10000) {
                  Navigator.pop(ctx, v);
                } else {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Enter amount between ₹10 and ₹10,000')),
                  );
                }
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.pink500),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
    if (amount == null || !mounted) return;

    setState(() {
      _isToppingUp = true;
      _errorMessage = null;
    });

    try {
      final order = await _apiService.topupWallet(amount);
      final orderId = order['order_id'] as String?;
      final keyId = order['key_id'] as String?;
      if (orderId == null || keyId == null) {
        throw Exception('Invalid top-up response');
      }

      _razorpayService.openCheckout(
        keyId: keyId,
        amount: amount,
        orderId: orderId,
        name: 'Qprint',
        description: 'Add money to wallet',
        prefill: {},
        onSuccess: (PaymentSuccessResponse response) async {
          if (mounted) {
            setState(() => _isToppingUp = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Money added to wallet'), backgroundColor: AppColors.green500),
            );
            _load();
          }
        },
        onError: (PaymentFailureResponse response) {
          if (mounted) {
            setState(() {
              _isToppingUp = false;
              _errorMessage = response.message ?? 'Payment failed';
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isToppingUp = false;
          _errorMessage = getSafeErrorMessage(e, 'wallet');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppBar(
                title: const Text('Wallet', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold)),
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.pink500))
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppColors.pink500,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_errorMessage != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  margin: const EdgeInsets.only(bottom: 16),
                                  decoration: BoxDecoration(
                                    color: AppColors.red500.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppColors.red500.withOpacity(0.5)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.error_outline, color: AppColors.red300),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(_errorMessage!, style: const TextStyle(color: AppColors.red300))),
                                    ],
                                  ),
                                ),
                              ],
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: AppColors.white10,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: AppColors.white20),
                                ),
                                child: Column(
                                  children: [
                                    const Text('Available balance', style: TextStyle(color: AppColors.purple200, fontSize: 14)),
                                    const SizedBox(height: 8),
                                    Text(
                                      '₹${_balance.toStringAsFixed(2)}',
                                      style: const TextStyle(color: AppColors.white, fontSize: 36, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 20),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: _isToppingUp ? null : _startTopup,
                                        icon: _isToppingUp ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.add),
                                        label: Text(_isToppingUp ? 'Opening...' : 'Add money'),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: AppColors.pink500,
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              InkWell(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ReferAndEarnScreen())),
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: AppColors.purple600.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: AppColors.purple300.withOpacity(0.5)),
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(backgroundColor: AppColors.pink500.withOpacity(0.3), child: const Icon(Icons.card_giftcard, color: AppColors.pink400)),
                                      const SizedBox(width: 14),
                                      const Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Earn by referring friends', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w600)),
                                            Text('Share your code, get wallet credit when they print.', style: TextStyle(color: AppColors.purple200, fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right, color: AppColors.white50),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Text('Recent transactions', style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 12),
                              if (_transactions.isEmpty)
                                Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(color: AppColors.white10, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.white20)),
                                  child: const Center(
                                    child: Text('No transactions yet.\nAdd money or pay from wallet to see history.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.white50)),
                                  ),
                                )
                              else
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _transactions.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final t = _transactions[index] as Map<String, dynamic>;
                                    final type = t['transaction_type'] as String? ?? '';
                                    final amount = (t['amount'] as num?)?.toDouble() ?? 0;
                                    final createdAt = t['created_at'] != null ? DateTime.tryParse(t['created_at'].toString()) : null;
                                    final isCredit = type == 'topup' || type == 'refund' || type == 'referral_bonus' || type == 'referral_welcome';
                                    final typeLabel = type == 'topup' ? 'Added to wallet' : type == 'payment' ? 'Payment' : type == 'refund' ? 'Refund' : type == 'referral_bonus' ? 'Referral bonus' : type == 'referral_welcome' ? 'Welcome bonus' : type;
                                    return Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: AppColors.white10,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: AppColors.white20),
                                      ),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor: (isCredit ? AppColors.green500 : AppColors.pink500).withOpacity(0.3),
                                            child: Icon(isCredit ? Icons.arrow_downward : Icons.arrow_upward, color: isCredit ? AppColors.green300 : AppColors.pink400),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  typeLabel,
                                                  style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600),
                                                ),
                                                if (createdAt != null)
                                                  Text(DateFormat('MMM d, y · HH:mm').format(createdAt), style: const TextStyle(color: AppColors.white50, fontSize: 12)),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            '${isCredit ? '+' : '-'}₹${amount.toStringAsFixed(2)}',
                                            style: TextStyle(color: isCredit ? AppColors.green300 : AppColors.white, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_colors.dart';
import '../services/api_service.dart';
import '../utils/safe_error.dart';
import 'login_screen.dart';

class ReferAndEarnScreen extends StatefulWidget {
  const ReferAndEarnScreen({super.key});

  @override
  State<ReferAndEarnScreen> createState() => _ReferAndEarnScreenState();
}

class _ReferAndEarnScreenState extends State<ReferAndEarnScreen> {
  final _apiService = ApiService();

  String? _referralCode;
  String? _referralLink;
  int _totalReferred = 0;
  int _totalCredited = 0;
  double _totalEarnings = 0;
  int _pendingCount = 0;
  List<dynamic> _history = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _statsErrorMessage;
  final _inviteEmailController = TextEditingController();
  bool _inviteLoading = false;
  String? _inviteSuccess;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Load profile first so referral code/link are always shown (including for accounts created via referral).
  /// Then load summary and history; if they fail, show stats error but keep code/link visible.
  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statsErrorMessage = null;
    });
    try {
      final profile = await _apiService.getProfile();
      if (!mounted) return;
      setState(() {
        _referralCode = profile['referral_code']?.toString();
        _referralLink = profile['referral_link']?.toString();
      });
    } catch (e) {
      if (mounted) {
        final msg = getSafeErrorMessage(e, 'referral');
        setState(() {
          _errorMessage = msg;
          _isLoading = false;
        });
        // Session expired → go to login
        final s = e.toString();
        if (s.contains('Session expired') || s.contains('401')) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
      }
      return;
    }
    try {
      final summary = await _apiService.getReferralSummary();
      final historyData = await _apiService.getReferralHistory(limit: 30, offset: 0);
      if (!mounted) return;
      setState(() {
        _totalReferred = (summary['total_referred'] as num?)?.toInt() ?? 0;
        _totalCredited = (summary['total_credited'] as num?)?.toInt() ?? 0;
        _totalEarnings = (summary['total_earnings'] as num?)?.toDouble() ?? 0;
        _pendingCount = (summary['pending_count'] as num?)?.toInt() ?? 0;
        _history = historyData['referrals'] as List<dynamic>? ?? [];
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _statsErrorMessage = 'Stats temporarily unavailable.';
          _history = [];
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _copyCode() {
    final code = _referralCode;
    if (code == null || code.isEmpty) return;
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Referral code copied'),
        backgroundColor: AppColors.green500,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _share() {
    final link = _referralLink ?? (_referralCode != null ? 'https://qprint.co.in/r/$_referralCode' : null);
    if (link == null) return;
    Share.share(
      'Use my qprint referral link to sign up and get prints easily. You\'ll get a welcome bonus too!\n$link',
      subject: 'Join qprint with my referral',
    );
  }

  Future<void> _inviteByEmail() async {
    final email = _inviteEmailController.text.trim().toLowerCase();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an email address.'), backgroundColor: AppColors.red500),
      );
      return;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address.'), backgroundColor: AppColors.red500),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _inviteLoading = true;
      _inviteSuccess = null;
      _errorMessage = null;
    });
    try {
      await _apiService.inviteByEmail(email);
      if (!mounted) return;
      setState(() {
        _inviteLoading = false;
        _inviteSuccess = 'Invite sent to $email';
        _inviteEmailController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_inviteSuccess!),
          backgroundColor: AppColors.green500,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inviteLoading = false;
        _inviteSuccess = null;
        _errorMessage = getSafeErrorMessage(e, 'referral');
      });
    }
  }

  @override
  void dispose() {
    _inviteEmailController.dispose();
    super.dispose();
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
                title: const Text('Refer & Earn', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold)),
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
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.error_outline, color: AppColors.red300),
                                          const SizedBox(width: 8),
                                          Expanded(child: Text(_errorMessage!, style: const TextStyle(color: AppColors.red300))),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      FilledButton.icon(
                                        onPressed: _load,
                                        icon: const Icon(Icons.refresh, size: 18),
                                        label: const Text('Retry'),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: AppColors.white20,
                                          foregroundColor: AppColors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              // Referral code card
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: AppColors.white10,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: AppColors.white20),
                                ),
                                child: Column(
                                  children: [
                                    const Text('Your referral code', style: TextStyle(color: AppColors.purple200, fontSize: 14)),
                                    const SizedBox(height: 8),
                                    Text(
                                      _referralCode ?? '—',
                                      style: const TextStyle(color: AppColors.white, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 4),
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        FilledButton.icon(
                                          onPressed: (_referralCode != null && _referralCode!.isNotEmpty) ? _copyCode : null,
                                          icon: const Icon(Icons.copy, size: 20),
                                          label: const Text('Copy'),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: AppColors.white20,
                                            foregroundColor: AppColors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        FilledButton.icon(
                                          onPressed: (_referralLink != null || _referralCode != null) ? _share : null,
                                          icon: const Icon(Icons.share, size: 20),
                                          label: const Text('Share'),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: AppColors.pink500,
                                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              // Invite by email
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppColors.white10,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppColors.white20),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Invite by email', style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 6),
                                    const Text('We\'ll send your referral link to a friend.', style: TextStyle(color: AppColors.purple200, fontSize: 12)),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: _inviteEmailController,
                                            keyboardType: TextInputType.emailAddress,
                                            decoration: InputDecoration(
                                              hintText: 'Friend\'s email',
                                              hintStyle: TextStyle(color: AppColors.purple200),
                                              filled: true,
                                              fillColor: AppColors.white20,
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                            ),
                                            style: const TextStyle(color: AppColors.white),
                                            onSubmitted: (_) => _inviteByEmail(),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        FilledButton(
                                          onPressed: (_inviteLoading || _referralCode == null || _referralCode!.isEmpty) ? null : _inviteByEmail,
                                          style: FilledButton.styleFrom(
                                            backgroundColor: AppColors.pink500,
                                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                          ),
                                          child: Text(_inviteLoading ? 'Sending…' : 'Send invite'),
                                        ),
                                      ],
                                    ),
                                    if (_inviteSuccess != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(_inviteSuccess!, style: const TextStyle(color: AppColors.green300, fontSize: 13)),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              // Summary
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppColors.white10,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppColors.white20),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Your referral stats', style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                    if (_statsErrorMessage != null) ...[
                                      const SizedBox(height: 8),
                                      Text(_statsErrorMessage!, style: const TextStyle(color: AppColors.yellow300, fontSize: 13)),
                                    ],
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                                      children: [
                                        _statChip('Referred', '$_totalReferred'),
                                        _statChip('Completed', '$_totalCredited'),
                                        _statChip('Earned', '₹${_totalEarnings.toStringAsFixed(0)}'),
                                      ],
                                    ),
                                    if (_pendingCount > 0)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: Text(
                                          '$_pendingCount friend(s) signed up — complete their first print or top-up to earn bonus.',
                                          style: const TextStyle(color: AppColors.purple200, fontSize: 12),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Text('Recent referrals', style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 12),
                              if (_history.isEmpty)
                                Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: AppColors.white10,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppColors.white20),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'No referrals yet. Share your code with friends!',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: AppColors.white50),
                                    ),
                                  ),
                                )
                              else
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _history.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final r = _history[index] as Map<String, dynamic>;
                                    final status = r['status'] as String? ?? '';
                                    final amount = (r['amount'] as num?)?.toDouble() ?? 0;
                                    final creditedAt = r['credited_at'] != null ? DateTime.tryParse(r['credited_at'].toString()) : null;
                                    final createdAt = r['created_at'] != null ? DateTime.tryParse(r['created_at'].toString()) : null;
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
                                            backgroundColor: (status == 'credited' ? AppColors.green500 : AppColors.purple600).withOpacity(0.3),
                                            child: Icon(
                                              status == 'credited' ? Icons.check_circle : Icons.schedule,
                                              color: status == 'credited' ? AppColors.green300 : AppColors.purple300,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  status == 'credited' ? 'Bonus earned' : 'Pending',
                                                  style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600),
                                                ),
                                                if (createdAt != null)
                                                  Text(DateFormat('MMM d, y').format(createdAt), style: const TextStyle(color: AppColors.white50, fontSize: 12)),
                                              ],
                                            ),
                                          ),
                                          if (status == 'credited' && amount > 0)
                                            Text('+₹${amount.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.green300, fontWeight: FontWeight.bold)),
                                          if (creditedAt != null && status == 'credited')
                                            Text(DateFormat('MMM d').format(creditedAt), style: const TextStyle(color: AppColors.white50, fontSize: 11)),
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

  Widget _statChip(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: AppColors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: AppColors.purple200, fontSize: 12)),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class PayoutsScreen extends StatefulWidget {
  const PayoutsScreen({super.key});

  @override
  State<PayoutsScreen> createState() => _PayoutsScreenState();
}

class _PayoutsScreenState extends State<PayoutsScreen> {
  final _apiService = ApiService();
  List<dynamic> _payouts = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchPayouts();
  }

  Future<void> _fetchPayouts() async {
    try {
      final list = await _apiService.getPayouts();
      if (mounted) {
        setState(() {
          _payouts = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _payouts.where((p) => p['status'] == 'pending').toList();
    final settled = _payouts.where((p) => p['status'] == 'paid').toList();
    final pendingAmount = pending.fold<double>(
      0,
      (sum, p) => sum + ((p['amount'] is num) ? (p['amount'] as num).toDouble() : 0),
    );
    final settledAmount = settled.fold<double>(
      0,
      (sum, p) => sum + ((p['amount'] is num) ? (p['amount'] as num).toDouble() : 0),
    );

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Settled payments',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'View payouts: pending (not yet sent) and settled (paid to your account)',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 24),
          if (_isLoading)
            const Expanded(
              child: Center(child: CircularProgressIndicator(color: Colors.white)),
            )
          else if (_errorMessage != null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.redAccent),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _fetchPayouts,
                      child: const Text('Retry', style: TextStyle(color: Colors.pinkAccent)),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: Card(
                    color: Colors.yellow.withOpacity(0.15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.yellow.withOpacity(0.3)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pending',
                            style: TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₹${pendingAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${pending.length} payout(s)',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Card(
                    color: Colors.green.withOpacity(0.15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Settled',
                            style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₹${settledAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${settled.length} payout(s)',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _payouts.isEmpty
                  ? const Center(
                      child: Text(
                        'No payouts yet. Completed queue prints will appear here.',
                        style: TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchPayouts,
                      color: Colors.white,
                      backgroundColor: Colors.purple,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _payouts.length,
                        itemBuilder: (context, index) {
                          final p = _payouts[index];
                          final status = p['status']?.toString() ?? '';
                          final amount = (p['amount'] is num)
                              ? (p['amount'] as num).toDouble()
                              : 0.0;
                          final orderId = p['order_id']?.toString() ?? '';
                          final createdAt = p['created_at'] != null
                              ? DateTime.tryParse(p['created_at'].toString())
                              : null;
                          final paidAt = p['paid_at'] != null
                              ? DateTime.tryParse(p['paid_at'].toString())
                              : null;
                          final isSettled = status == 'paid';

                          return Card(
                            color: Colors.white.withOpacity(0.08),
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isSettled
                                    ? Colors.green.withOpacity(0.3)
                                    : Colors.white.withOpacity(0.1),
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: CircleAvatar(
                                backgroundColor: isSettled
                                    ? Colors.green.withOpacity(0.3)
                                    : Colors.yellow.withOpacity(0.3),
                                child: Icon(
                                  isSettled ? Icons.check_circle : Icons.schedule,
                                  color: isSettled ? Colors.greenAccent : Colors.yellowAccent,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    '₹${amount.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isSettled
                                          ? Colors.green.withOpacity(0.2)
                                          : Colors.yellow.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      isSettled ? 'Settled' : 'Pending',
                                      style: TextStyle(
                                        color: isSettled ? Colors.greenAccent : Colors.yellowAccent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (orderId.isNotEmpty)
                                    Text(
                                      'Order: $orderId',
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  Text(
                                    isSettled && paidAt != null
                                        ? 'Paid on ${DateFormat('MMM d, y').format(paidAt)}'
                                        : createdAt != null
                                            ? 'Created ${DateFormat('MMM d, y').format(createdAt)}'
                                            : '',
                                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                                  ),
                                  if (isSettled &&
                                      (p['payout_method'] != null || p['payout_reference'] != null))
                                    Text(
                                      [
                                        if (p['payout_method'] != null) p['payout_method'],
                                        if (p['payout_reference'] != null) p['payout_reference'],
                                      ].join(' · '),
                                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

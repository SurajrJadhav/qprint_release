import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _apiService = ApiService();
  List<dynamic> _history = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    try {
      final historyData = await _apiService.getHistory();
      if (mounted) {
        setState(() {
          _history = historyData;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Print History',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Completed prints by customer and file — pull down to refresh',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : _errorMessage != null
                    ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)))
                    : _history.isEmpty
                        ? const Center(
                            child: Text(
                              'No history found. Print some files first!',
                              style: TextStyle(color: Colors.white70, fontSize: 18),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _fetchHistory,
                            color: Colors.white,
                            backgroundColor: Colors.purple,
                            child: Card(
                              color: Colors.white.withOpacity(0.1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: Colors.white.withOpacity(0.1)),
                              ),
                              child: ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: _history.length,
                                separatorBuilder: (context, index) => Divider(color: Colors.white.withOpacity(0.1)),
                                itemBuilder: (context, index) {
                                  final item = _history[index];
                                  final date = DateTime.parse(item['date'].toString());
                                  final formattedDate = DateFormat('MMM d, y').format(date);
                                  final formattedTime = DateFormat('HH:mm').format(date);
                                  final isQueue = item['type'] == 'queue';
                                  final customerName = item['customer_name']?.toString()?.trim();
                                  final displayName = (customerName != null && customerName.isNotEmpty) ? customerName : 'Unknown customer';
                                  final filename = item['filename']?.toString() ?? item['code']?.toString() ?? '';
                                  final code = item['code']?.toString() ?? '';
                                  final paperSize = item['paper_size']?.toString();
                                  final colorMode = item['color_mode']?.toString();
                                  final payoutStatus = item['payout_status']?.toString() ?? '';
                                  final isSettled = payoutStatus == 'paid';
                                  final details = [
                                    '${item['pages']} pg',
                                    '${item['copies']} ${item['copies'] == 1 ? 'copy' : 'copies'}',
                                    if (paperSize != null && paperSize.isNotEmpty) paperSize,
                                    if (colorMode != null && colorMode.isNotEmpty && colorMode != 'bw') colorMode,
                                  ].join(' · ');

                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                                    leading: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: isQueue ? Colors.blue.withOpacity(0.2) : Colors.pink.withOpacity(0.2),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        isQueue ? Icons.list_alt : Icons.lock_outline,
                                        color: isQueue ? Colors.blueAccent : Colors.pinkAccent,
                                      ),
                                    ),
                                    title: Text(
                                      displayName,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (filename.isNotEmpty)
                                          Text(
                                            filename,
                                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        Text(
                                          '$formattedDate $formattedTime • $details',
                                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (code.isNotEmpty)
                                          Text(
                                            'Code: $code',
                                            style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
                                          ),
                                      ],
                                    ),
                                    trailing: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '₹${(item['cost'] is num) ? (item['cost'] as num).toStringAsFixed(2) : item['cost']}',
                                          style: const TextStyle(
                                            color: Colors.greenAccent,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (isSettled) ...[
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.green.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              'Settled',
                                              style: TextStyle(
                                                color: Colors.greenAccent,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

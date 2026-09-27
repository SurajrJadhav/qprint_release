import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';
import '../services/api_service.dart';
import '../utils/safe_error.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> with WidgetsBindingObserver {
  final _apiService = ApiService();
  List<dynamic> _orders = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  Timer? _refreshTimer;
  bool _hasInitialLoad = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadOrders(silent: true);
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadOrders(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && _hasInitialLoad) {
      // App returned from background - reload data silently
      setState(() {
        _isRefreshing = true;
      });
      _loadOrders(silent: true);
    }
  }

  Future<void> _loadOrders({bool silent = false}) async {
    if (!silent && !_hasInitialLoad) {
      setState(() => _isLoading = true);
    }
    try {
      final orders = await _apiService.getMyOrders();
      if (mounted) {
        setState(() {
          _orders = orders ?? [];
          _isLoading = false;
          _isRefreshing = false;
          _hasInitialLoad = true;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading orders: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
          _hasInitialLoad = true;
        });
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(getSafeErrorMessage(e, 'files')),
              backgroundColor: AppColors.red500,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  Future<void> _withdrawPrint(int fileId) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.indigo900,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.white20, width: 1),
        ),
        title: const Text(
          'Withdraw Print',
          style: TextStyle(
            color: AppColors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'Are you sure you want to withdraw this print?',
          style: TextStyle(
            color: AppColors.white70,
            fontSize: 16,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.white70,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.red500,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'Withdraw',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _apiService.withdrawPrint(fileId);
        _loadOrders(silent: false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Print withdrawn successfully'),
              backgroundColor: AppColors.green500,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(getSafeErrorMessage(e, 'withdraw')),
              backgroundColor: AppColors.red500,
            ),
          );
        }
      }
    }
  }

  Future<void> _withdrawOrder(Map<String, dynamic> order) async {
    final files = order['files'] as List? ?? [];
    final fileCount = files.length;
    final msg = fileCount > 1
        ? 'Withdraw this order ($fileCount files)? Refund will be processed.'
        : 'Are you sure you want to withdraw this print?';
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.indigo900,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.white20, width: 1),
        ),
        title: const Text(
          'Withdraw Print',
          style: TextStyle(color: AppColors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        content: Text(
          msg,
          style: const TextStyle(color: AppColors.white70, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: AppColors.white70),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red500),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      final firstId = files.isNotEmpty && files.first is Map
          ? (files.first as Map)['id']
          : order['id'];
      final fileId = firstId is int ? firstId : int.tryParse(firstId?.toString() ?? '0') ?? 0;
      if (fileId > 0) {
        await _apiService.withdrawPrint(fileId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order withdrawn successfully'),
            backgroundColor: AppColors.green500,
          ),
        );
      }
      _loadOrders(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(getSafeErrorMessage(e, 'withdraw')), backgroundColor: AppColors.red500),
        );
      }
    }
  }

  Future<void> _navigateToShop(double lat, double long) async {
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$long');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'downloaded':
        return AppColors.green500;
      case 'withdrawn':
        return AppColors.red500;
      case 'cancelled':
        return AppColors.orange500;
      case 'printing':
        return AppColors.blue500;
      default:
        return AppColors.yellow500;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'downloaded':
        return '✅ Printed';
      case 'withdrawn':
        return '🚫 Withdrawn';
      case 'cancelled':
        return '❌ Cancelled by shop';
      case 'printing':
        return '🖨️ Printing at shop...';
      default:
        return '⏳ Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.backgroundGradient,
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _orders.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.folder_open, size: 64, color: AppColors.white50),
                        const SizedBox(height: 16),
                        const Text(
                          'No print orders yet',
                          style: TextStyle(
                            color: AppColors.purple200,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      RefreshIndicator(
                        onRefresh: () => _loadOrders(silent: false),
                        child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _orders.length,
                      itemBuilder: (context, index) {
                        final order = _orders[index];
                        final status = order['status'] ?? 'uploaded';
                        final printType = order['print_type'] ?? 'private';
                        final canWithdraw = status != 'downloaded' && status != 'withdrawn' && status != 'cancelled' && status != 'printing';
                        final fileCount = order['file_count'] ?? (order['files'] as List?)?.length ?? 1;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.white10,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.white20),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    printType == 'private' ? Icons.lock : Icons.queue,
                                    color: AppColors.pink400,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    printType == 'private' ? 'Private Print' : 'Queue Print',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.white,
                                    ),
                                  ),
                                  if (fileCount > 1) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      '($fileCount files)',
                                      style: const TextStyle(color: AppColors.purple200, fontSize: 14),
                                    ),
                                  ],
                                  if (printType == 'private') ...[
                                    Builder(builder: (_) {
                                      final files = order['files'] as List?;
                                      final code = files != null && files.isNotEmpty
                                          ? ((files[0] as Map?)?['code']?.toString() ?? '')
                                          : '';
                                      if (code.isEmpty) return const SizedBox.shrink();
                                      return Padding(
                                        padding: const EdgeInsets.only(left: 8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: AppColors.pink500.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            code,
                                            style: const TextStyle(color: AppColors.pink400, fontFamily: 'monospace'),
                                          ),
                                        ),
                                      );
                                    }),
                                  ],
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _getStatusColor(status).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      _getStatusText(status),
                                      style: TextStyle(
                                        color: _getStatusColor(status),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 16,
                                runSpacing: 8,
                                children: [
                                  _buildInfoChip('Pages', '${order['num_pages'] ?? 0}'),
                                  _buildInfoChip('Copies', '${order['copies'] ?? 1}'),
                                  _buildInfoChip('Mode', order['print_mode'] ?? 'single'),
                                  _buildInfoChip('Cost', '₹${order['total_cost'] ?? 0}'),
                                ],
                              ),
                              if (status == 'cancelled' && order['cancel_reason'] != null && order['cancel_reason'].toString().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.orange500.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppColors.orange500.withOpacity(0.4)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.info_outline, color: AppColors.orange500, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Reason: ${order['cancel_reason']}',
                                          style: const TextStyle(color: AppColors.white, fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (order['shop_name'] != null) ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    const Text(
                                      'Shop: ',
                                      style: TextStyle(color: AppColors.purple200),
                                    ),
                                    Text(
                                      order['shop_name'].toString(),
                                      style: const TextStyle(color: AppColors.white),
                                    ),
                                    if (order['queue_position'] != null) ...[
                                      const SizedBox(width: 16),
                                      const Text(
                                        'Position: ',
                                        style: TextStyle(color: AppColors.purple200),
                                      ),
                                      Text(
                                        '#${order['queue_position']}',
                                        style: const TextStyle(
                                          color: AppColors.pink400,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                    if (order['shop_lat'] != null && order['shop_long'] != null) ...[
                                      const Spacer(),
                                      IconButton(
                                        icon: const Icon(Icons.navigation),
                                        color: AppColors.blue500,
                                        onPressed: () {
                                          _navigateToShop(
                                            (order['shop_lat'] as num).toDouble(),
                                            (order['shop_long'] as num).toDouble(),
                                          );
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                              if (canWithdraw) ...[
                                const SizedBox(height: 12),
                                ElevatedButton(
                                  onPressed: () => _withdrawOrder(order),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.red500.withOpacity(0.2),
                                    foregroundColor: AppColors.red300,
                                  ),
                                  child: const Text('Withdraw Print'),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                      if (_isRefreshing)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: LinearProgressIndicator(
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.pink500),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildInfoChip(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(color: AppColors.purple200, fontSize: 12),
        ),
        Text(
          value,
          style: const TextStyle(color: AppColors.white, fontSize: 12),
        ),
      ],
    );
  }
}

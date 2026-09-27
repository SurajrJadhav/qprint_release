import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';
import '../services/api_service.dart';
import 'dart:async';

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  final _apiService = ApiService();
  List<dynamic> _files = [];
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadFiles();
    // Auto-refresh every 5 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _loadFiles();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    try {
      final files = await _apiService.getMyFiles();
      if (mounted) {
        setState(() {
          _files = files;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _withdrawPrint(int fileId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.white10,
        title: const Text('Withdraw Print'),
        content: const Text('Are you sure you want to withdraw this print?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Withdraw',
              style: TextStyle(color: AppColors.red500),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _apiService.withdrawPrint(fileId);
        _loadFiles();
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
              content: Text('Error: ${e.toString()}'),
              backgroundColor: AppColors.red500,
            ),
          );
        }
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
      default:
        return AppColors.yellow500;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'downloaded':
        return '✅ Downloaded';
      case 'withdrawn':
        return '🚫 Withdrawn';
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
            : _files.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.folder_open, size: 64, color: AppColors.white50),
                        const SizedBox(height: 16),
                        const Text(
                          'No files uploaded yet',
                          style: TextStyle(
                            color: AppColors.purple200,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadFiles,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _files.length,
                      itemBuilder: (context, index) {
                        final file = _files[index];
                        final status = file['status'] ?? 'uploaded';
                        final printType = file['print_type'] ?? 'private';
                        final canWithdraw = status != 'downloaded' && status != 'withdrawn';

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
                                  if (printType == 'private' && file['code'] != null) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.pink500.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        file['code'],
                                        style: const TextStyle(
                                          color: AppColors.pink400,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
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
                                  _buildInfoChip('Pages', '${file['num_pages'] ?? 0}'),
                                  _buildInfoChip('Copies', '${file['copies'] ?? 1}'),
                                  _buildInfoChip('Mode', file['print_mode'] ?? 'single'),
                                  _buildInfoChip('Cost', '₹${file['total_cost'] ?? 0}'),
                                ],
                              ),
                              if (file['shop_name'] != null) ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    const Text(
                                      'Shop: ',
                                      style: TextStyle(color: AppColors.purple200),
                                    ),
                                    Text(
                                      file['shop_name'],
                                      style: const TextStyle(color: AppColors.white),
                                    ),
                                    if (file['queue_position'] != null) ...[
                                      const SizedBox(width: 16),
                                      const Text(
                                        'Position: ',
                                        style: TextStyle(color: AppColors.purple200),
                                      ),
                                      Text(
                                        '#${file['queue_position']}',
                                        style: const TextStyle(
                                          color: AppColors.pink400,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                    if (file['shop_lat'] != null && file['shop_long'] != null) ...[
                                      const Spacer(),
                                      IconButton(
                                        icon: const Icon(Icons.navigation),
                                        color: AppColors.blue500,
                                        onPressed: () {
                                          _navigateToShop(
                                            file['shop_lat'].toDouble(),
                                            file['shop_long'].toDouble(),
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
                                  onPressed: () => _withdrawPrint(file['id']),
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

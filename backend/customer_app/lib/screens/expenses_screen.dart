import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/api_service.dart';
import 'dart:async';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final _apiService = ApiService();
  List<dynamic> _files = [];
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadFiles();
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

  double _getTotalSpent() {
    return _files
        .where((f) => f['status'] == 'downloaded')
        .fold(0.0, (sum, f) => sum + (f['total_cost'] ?? 0.0));
  }

  double _getPendingCosts() {
    return _files
        .where((f) => f['status'] != 'downloaded' && f['status'] != 'withdrawn')
        .fold(0.0, (sum, f) => sum + (f['total_cost'] ?? 0.0));
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
            : RefreshIndicator(
                onRefresh: _loadFiles,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.attach_money, size: 32, color: AppColors.white),
                          SizedBox(width: 12),
                          Text(
                            'Expense Tracker',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatCard(
                              'Total Spent',
                              '₹${_getTotalSpent().toStringAsFixed(2)}',
                              AppColors.red500,
                              'Verified completed prints',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatCard(
                              'Pending Costs',
                              '₹${_getPendingCosts().toStringAsFixed(2)}',
                              AppColors.yellow500,
                              'Active queue/private prints',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildStatCard(
                        'Total Files',
                        '${_files.length}',
                        AppColors.blue500,
                        'Lifetime uploads',
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    Color color,
    String subtitle,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.2),
            color.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color.withOpacity(0.8),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: AppColors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: AppColors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

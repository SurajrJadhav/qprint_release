import 'package:flutter/material.dart';
import '../services/api_service.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final _apiService = ApiService();
  bool _isLoading = true;
  String? _errorMessage;
  
  double _totalEarnings = 0;
  double _todayEarnings = 0;
  int _totalPrints = 0;

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    try {
      final history = await _apiService.getHistory();
      
      double total = 0;
      double today = 0;
      final now = DateTime.now();

      for (var item in history) {
        final cost = (item['cost'] ?? 0).toDouble();
        final date = DateTime.parse(item['date']);
        
        total += cost;
        
        if (date.year == now.year && date.month == now.month && date.day == now.day) {
          today += cost;
        }
      }

      if (mounted) {
        setState(() {
          _totalEarnings = total;
          _todayEarnings = today;
          _totalPrints = history.length;
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
            'Earnings & Stats',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Overview of your shop\'s performance',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 32),
          
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else if (_errorMessage != null)
            Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)))
          else
            Row(
              children: [
                _buildStatCard(
                  'Total Earnings',
                  '₹${_totalEarnings.toStringAsFixed(2)}',
                  'All time revenue',
                  Colors.green,
                  Icons.attach_money,
                ),
                const SizedBox(width: 24),
                _buildStatCard(
                  'Today\'s Earnings',
                  '₹${_todayEarnings.toStringAsFixed(2)}',
                  'Revenue generated today',
                  Colors.blue,
                  Icons.today,
                ),
                const SizedBox(width: 24),
                _buildStatCard(
                  'Total Prints',
                  _totalPrints.toString(),
                  'Total files processed',
                  Colors.pink,
                  Icons.print,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, String subtitle, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(color: color.withOpacity(0.8), fontWeight: FontWeight.bold),
                ),
                Icon(icon, color: color.withOpacity(0.8)),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

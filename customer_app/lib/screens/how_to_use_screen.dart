import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class HowToUseScreen extends StatelessWidget {
  const HowToUseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'How to Use Qprint',
          style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.backgroundGradient,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome Section
              _buildSection(
                icon: Icons.print,
                title: 'Welcome to Qprint',
                description: 'Print your documents without standing in long queues. Choose between Queue Print or Private Print based on your needs.',
                color: AppColors.pink500,
              ),
              
              const SizedBox(height: 32),
              
              // Queue Print Section
              _buildSection(
                icon: Icons.queue,
                title: 'Queue Print',
                description: 'Perfect when you want to send your print to a specific shop and wait for it to be ready.',
                color: AppColors.blue500,
                steps: [
                  'Go to Upload tab and select "Queue Print"',
                  'Pick your PDF or image file',
                  'Choose your preferred shop from the list',
                  'Configure print settings (color, paper size, copies)',
                  'Submit and track your queue position',
                  'Get notified when your print is ready',
                  'Visit the shop to collect your prints',
                ],
              ),
              
              const SizedBox(height: 32),
              
              // Private Print Section
              _buildSection(
                icon: Icons.lock,
                title: 'Private Print',
                description: 'Upload your file, get a unique code, and collect from any registered shop at your convenience.',
                color: AppColors.purple600,
                steps: [
                  'Go to Upload tab and select "Private Print"',
                  'Pick your PDF or image file',
                  'Configure print settings',
                  'Submit and receive your unique OTP code',
                  'Open Map tab to view all registered shops',
                  'Visit any shop of your choice',
                  'Share your OTP code with the shopkeeper',
                  'Collect your prints instantly',
                ],
              ),
              
              const SizedBox(height: 32),
              
              // Tips Section
              _buildTipsSection(),
              
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    List<String>? steps,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white10,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.white20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            description,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.white70,
              height: 1.5,
            ),
          ),
          if (steps != null && steps.isNotEmpty) ...[
            const SizedBox(height: 20),
            ...steps.asMap().entries.map((entry) {
              final index = entry.key;
              final step = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        step,
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildTipsSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white10,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.white20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.green500.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.lightbulb,
                  color: AppColors.green500,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                'Tips & Recommendations',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTip(
            'Save your favorite shops for quick access',
            Icons.star,
          ),
          _buildTip(
            'Track your expenses in the Expenses tab',
            Icons.attach_money,
          ),
          _buildTip(
            'Set default print preferences in Profile',
            Icons.settings,
          ),
          _buildTip(
            'Check map view to find nearest shops',
            Icons.map,
          ),
          _buildTip(
            'Monitor your print status in My Files',
            Icons.folder,
          ),
        ],
      ),
    );
  }

  Widget _buildTip(String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: AppColors.green500, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.white70,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

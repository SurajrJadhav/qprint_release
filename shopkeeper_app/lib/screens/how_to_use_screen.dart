import 'package:flutter/material.dart';

class HowToUseScreen extends StatelessWidget {
  const HowToUseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'How to Use Qprint Shopkeeper',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF312E81),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF312E81), // indigo-900
              Color(0xFF581C87), // purple-900
              Color(0xFF9F1239), // pink-800
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome Section
              _buildSection(
                icon: Icons.store,
                title: 'Welcome to Qprint Shopkeeper',
                description: 'Manage customer prints efficiently with Queue Print and Private Print features. This guide will help you get started.',
                color: Colors.pinkAccent,
              ),
              
              const SizedBox(height: 32),
              
              // Printer Setup Section
              _buildSection(
                icon: Icons.print,
                title: '1. Printer Setup',
                description: 'Before you can print, you need to set up your printer.',
                color: Colors.blueAccent,
                steps: [
                  'Go to Dashboard and check the printer status at the top',
                  'If no printer is selected, click "Select Printer"',
                  'Choose your default printer from the list',
                  'The app will remember your printer selection',
                  'Printer status is checked every 10 seconds automatically',
                  'For Windows: Uses system print dialog',
                  'For Linux/Mac: Uses CUPS printing system',
                  'For Android/iOS: Uses native print dialog',
                ],
              ),
              
              const SizedBox(height: 32),
              
              // Queue Print Section
              _buildSection(
                icon: Icons.queue,
                title: '2. Managing Queue Prints',
                description: 'Queue prints are files sent by customers to your shop. They appear in your queue and are processed in order.',
                color: Colors.blueAccent,
                steps: [
                  'Queue automatically refreshes every 5 seconds',
                  'View queue on the Dashboard tab',
                  'Each queue item shows:',
                  '  • Queue position (#1, #2, etc.)',
                  '  • Customer name',
                  '  • File name',
                  '  • Page count',
                  '  • Print settings (copies, mode, color, paper size)',
                  '  • Total cost',
                  '  • Customer comments (if any)',
                  'Click "Print" button on any queue item',
                  'File downloads automatically',
                  'Print dialog opens with customer\'s settings',
                  'After printing, click "Confirm" to mark as complete',
                  'File is removed from queue after confirmation',
                ],
              ),
              
              const SizedBox(height: 32),
              
              // Private Print Section
              _buildSection(
                icon: Icons.lock,
                title: '3. Processing Private Prints',
                description: 'Private prints use a 6-character OTP code. Customers visit your shop and share this code to get their prints.',
                color: Colors.purpleAccent,
                steps: [
                  'Customer will provide you with a 6-character code',
                  'Enter the code in the "Private Print Code" field',
                  'Click "Download & Print" button',
                  'System verifies the code and downloads the file',
                  'Print dialog opens with customer\'s original settings',
                  'Print the document',
                  'After successful printing, click "Confirm"',
                  'File status is updated and removed from server',
                  'Only confirm if print was successful',
                ],
              ),
              
              const SizedBox(height: 32),
              
              // Shop Status Section
              _buildSection(
                icon: Icons.store_mall_directory,
                title: '4. Shop Status Management',
                description: 'Control your shop\'s availability to customers.',
                color: Colors.greenAccent,
                steps: [
                  'Find the shop status toggle on Dashboard',
                  'Green = Shop is OPEN (customers can send prints)',
                  'Red = Shop is CLOSED (customers cannot send prints)',
                  'Click the toggle to change status',
                  'Status updates in real-time',
                  'When closed, customers won\'t see your shop in queue options',
                  'Keep status updated to manage customer expectations',
                ],
              ),
              
              const SizedBox(height: 32),
              
              // History Section
              _buildSection(
                icon: Icons.history,
                title: '5. Viewing Print History',
                description: 'Track all completed prints in the History tab.',
                color: Colors.orangeAccent,
                steps: [
                  'Navigate to History tab in bottom navigation',
                  'View all completed prints (queue and private)',
                  'See print details:',
                  '  • Date and time',
                  '  • Print type (Queue/Private)',
                  '  • Pages printed',
                  '  • Number of copies',
                  '  • Total cost',
                  'Use history to track your business performance',
                ],
              ),
              
              const SizedBox(height: 32),
              
              // Stats Section
              _buildSection(
                icon: Icons.analytics,
                title: '6. Statistics & Earnings',
                description: 'Monitor your business performance with real-time statistics.',
                color: Colors.tealAccent,
                steps: [
                  'Go to Stats tab in bottom navigation',
                  'View Total Earnings (all-time)',
                  'View Today\'s Earnings',
                  'View Total Prints count',
                  'Use stats to track business growth',
                  'Stats update automatically after each print',
                ],
              ),
              
              const SizedBox(height: 32),
              
              // Profile Section
              _buildSection(
                icon: Icons.person,
                title: '7. Profile Management',
                description: 'Keep your shop information up to date.',
                color: Colors.cyanAccent,
                steps: [
                  'Navigate to Profile tab',
                  'Update Shop Name (visible to customers)',
                  'Update Address (used for customer location services)',
                  'Change Password (optional)',
                  'Click "Save Changes" to update',
                  'Keep information current for better customer experience',
                ],
              ),
              
              const SizedBox(height: 32),
              
              // Tips Section
              _buildTipsSection(),
              
              const SizedBox(height: 32),
              
              // Troubleshooting Section
              _buildTroubleshootingSection(),
              
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
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
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
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            description,
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withOpacity(0.8),
              height: 1.5,
            ),
          ),
          if (steps != null && steps.isNotEmpty) ...[
            const SizedBox(height: 20),
            ...steps.asMap().entries.map((entry) {
              final index = entry.key;
              final step = entry.value;
              final isSubItem = step.startsWith('  •');
              
              return Padding(
                padding: EdgeInsets.only(bottom: 12, left: isSubItem ? 24 : 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isSubItem)
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.3),
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
                      )
                    else
                      const SizedBox(width: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        step,
                        style: TextStyle(
                          color: Colors.white.withOpacity(isSubItem ? 0.7 : 0.9),
                          fontSize: 14,
                          height: 1.4,
                          fontStyle: isSubItem ? FontStyle.italic : FontStyle.normal,
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
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.lightbulb,
                  color: Colors.greenAccent,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                'Tips & Best Practices',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTip('Keep your printer ready and check status regularly', Icons.print),
          _buildTip('Only confirm prints after successful printing', Icons.check_circle),
          _buildTip('Update shop status when opening/closing', Icons.store),
          _buildTip('Monitor queue regularly during busy hours', Icons.queue),
          _buildTip('Verify OTP codes carefully for private prints', Icons.verified),
          _buildTip('Check printer status before peak hours', Icons.schedule),
          _buildTip('Keep your profile information updated', Icons.update),
        ],
      ),
    );
  }

  Widget _buildTip(String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.greenAccent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTroubleshootingSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.build,
                  color: Colors.orangeAccent,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                'Troubleshooting',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTroubleshootingItem(
            'Printer not detected',
            'Go to Printer Setup, ensure printer is connected and powered on, then select it from the list.',
          ),
          _buildTroubleshootingItem(
            'Files not downloading',
            'Check your internet connection. Queue prints require active connection to download files.',
          ),
          _buildTroubleshootingItem(
            'OTP code not working',
            'Verify the code is exactly 6 characters. Ask customer to check their code again.',
          ),
          _buildTroubleshootingItem(
            'Queue not updating',
            'Queue auto-refreshes every 5 seconds. If stuck, refresh the app or check internet connection.',
          ),
          _buildTroubleshootingItem(
            'Print dialog not opening',
            'Check printer is properly connected. On Windows, ensure printer drivers are installed.',
          ),
        ],
      ),
    );
  }

  Widget _buildTroubleshootingItem(String issue, String solution) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning, color: Colors.orangeAccent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  issue,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              solution,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

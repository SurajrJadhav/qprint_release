import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'services/queue_notification_plugin.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initQueueNotifications();

  // Ensure plugins are registered
  try {
    // This helps ensure native plugins are registered
    await SystemChannels.platform.invokeMethod('SystemChrome.setApplicationSwitcherDescription');
    
    // Initialize path_provider to ensure it's registered
    try {
      await getTemporaryDirectory();
      if (kDebugMode) print('✅ path_provider plugin initialized successfully');
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Warning: path_provider initialization check failed: $e');
        print('This may be normal during first run. Plugin will initialize during use.');
      }
    }
  } catch (e) {
    // Ignore if it fails, plugins will be registered during runApp
    if (kDebugMode) print('Plugin initialization check: $e');
  }
  
  runApp(const QPrintApp());
}

class QPrintApp extends StatelessWidget {
  const QPrintApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QPrint Shopkeeper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.pink,
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: 'Inter', // Ensure you have a nice font or remove this line
      ),
      home: const LoginScreen(),
    );
  }
}

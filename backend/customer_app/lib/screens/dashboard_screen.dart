import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/favorites_service.dart';
import 'upload_screen.dart';
import 'files_screen.dart';
import 'expenses_screen.dart';
import 'favorites_screen.dart';
import 'map_screen.dart';
import 'login_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  String _username = 'Customer';
  final _apiService = ApiService();
  final _locationService = LocationService();
  final _favoritesService = FavoritesService();

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _username = prefs.getString('username') ?? 'Customer';
    });
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.white10,
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout', style: TextStyle(color: AppColors.red500)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _apiService.logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiService>.value(value: _apiService),
        Provider<LocationService>.value(value: _locationService),
        Provider<FavoritesService>.value(value: _favoritesService),
      ],
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: AppColors.backgroundGradient,
          ),
          child: IndexedStack(
            index: _currentIndex,
            children: const [
              UploadScreen(),
              FilesScreen(),
              FavoritesScreen(),
              ExpensesScreen(),
              MapScreen(),
            ],
          ),
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: AppColors.white10,
            border: Border(
              top: BorderSide(color: AppColors.white20),
            ),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedItemColor: AppColors.pink500,
            unselectedItemColor: AppColors.white50,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.upload),
                label: 'Upload',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.folder),
                label: 'My Files',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.star),
                label: 'Favorites',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.attach_money),
                label: 'Expenses',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.map),
                label: 'Map',
              ),
            ],
          ),
        ),
        appBar: AppBar(
          title: Row(
            children: [
              const Text(
                'Q',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppColors.white,
                ),
              ),
              const Text(
                'print',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppColors.pink400,
                ),
              ),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              icon: CircleAvatar(
                backgroundColor: AppColors.pink500,
                child: Text(
                  _username[0].toUpperCase(),
                  style: const TextStyle(color: AppColors.white),
                ),
              ),
              onSelected: (value) {
                if (value == 'logout') {
                  _handleLogout();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'logout',
                  child: const Row(
                    children: [
                      Icon(Icons.logout, color: AppColors.red500),
                      SizedBox(width: 8),
                      Text('Logout'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

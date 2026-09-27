import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/favorites_service.dart';
import 'dart:async';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final _apiService = ApiService();
  final _locationService = LocationService();
  List<dynamic> _shops = [];
  List<int> _favorites = [];
  bool _isLoading = true;
  double? _userLat;
  double? _userLong;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _getUserLocation();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _loadShops();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _getUserLocation() async {
    try {
      final position = await _locationService.getCurrentPosition();
      setState(() {
        _userLat = position.latitude;
        _userLong = position.longitude;
      });
      _loadShops();
    } catch (e) {
      _loadShops();
    }
  }

  Future<void> _loadShops() async {
    if (_userLat == null || _userLong == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final shops = await _apiService.getShops(_userLat!, _userLong!);
      if (mounted) {
        final favoritesService = Provider.of<FavoritesService>(context, listen: false);
        final favorites = await favoritesService.getFavorites();
        setState(() {
          _shops = shops;
          _favorites = favorites;
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

  Future<void> _toggleFavorite(int shopId) async {
    final favoritesService = Provider.of<FavoritesService>(context, listen: false);
    await favoritesService.toggleFavorite(shopId);
    _loadShops();
  }

  Future<void> _navigateToShop(double lat, double long) async {
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$long');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  List<dynamic> _getFavoriteShops() {
    return _shops.where((shop) => _favorites.contains(shop['id'])).toList();
  }

  @override
  Widget build(BuildContext context) {
    final favoriteShops = _getFavoriteShops();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.backgroundGradient,
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadShops,
                child: favoriteShops.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.star_border, size: 64, color: AppColors.white50),
                            const SizedBox(height: 16),
                            const Text(
                              'No favorite shops yet',
                              style: TextStyle(
                                color: AppColors.purple200,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Go to Upload and add shops to your favorites!',
                              style: TextStyle(
                                color: AppColors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: favoriteShops.length,
                        itemBuilder: (context, index) {
                          final shop = favoriteShops[index];
                          final shopId = shop['id'] as int;
                          final isOpen = shop['is_open'] == true;
                          final distance = shop['distance'];
                          final lat = shop['lat'];
                          final long = shop['long'];

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
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            shop['shop_name'] ?? 'Unknown',
                                            style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.white,
                                            ),
                                          ),
                                          if (distance != null) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              '${distance.toStringAsFixed(2)} km away',
                                              style: const TextStyle(
                                                color: AppColors.purple200,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.star),
                                      color: AppColors.yellow300,
                                      onPressed: () => _toggleFavorite(shopId),
                                    ),
                                  ],
                                ),
                                if (shop['address'] != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '📍 ${shop['address']}',
                                    style: const TextStyle(
                                      color: AppColors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isOpen
                                            ? AppColors.green500.withOpacity(0.3)
                                            : AppColors.red500.withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        isOpen ? '🟢 Open' : '🔴 Closed',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isOpen
                                              ? AppColors.green300
                                              : AppColors.red300,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    if (lat != null && long != null)
                                      ElevatedButton.icon(
                                        onPressed: () {
                                          _navigateToShop(
                                            lat.toDouble(),
                                            long.toDouble(),
                                          );
                                        },
                                        icon: const Icon(Icons.navigation, size: 18),
                                        label: const Text('Navigate'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.blue500,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
      ),
    );
  }
}

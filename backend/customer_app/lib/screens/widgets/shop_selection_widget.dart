import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_colors.dart';
import '../../services/favorites_service.dart';
import '../../services/location_service.dart';

class ShopSelectionWidget extends StatefulWidget {
  final List<dynamic> shops;
  final int? selectedShopId;
  final Function(int?) onShopSelected;
  final VoidCallback onShopsUpdated;

  const ShopSelectionWidget({
    super.key,
    required this.shops,
    required this.selectedShopId,
    required this.onShopSelected,
    required this.onShopsUpdated,
  });

  @override
  State<ShopSelectionWidget> createState() => _ShopSelectionWidgetState();
}

class _ShopSelectionWidgetState extends State<ShopSelectionWidget> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final _locationService = LocationService();
  double? _userLat;
  double? _userLong;

  @override
  void initState() {
    super.initState();
    _getUserLocation();
  }

  Future<void> _getUserLocation() async {
    try {
      final position = await _locationService.getCurrentPosition();
      setState(() {
        _userLat = position.latitude;
        _userLong = position.longitude;
      });
    } catch (e) {
      // Location not available
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<dynamic> _getFilteredShops() {
    var shops = widget.shops;
    
    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      shops = shops.where((shop) {
        final name = shop['shop_name']?.toString().toLowerCase() ?? '';
        return name.contains(_searchQuery.toLowerCase());
      }).toList();
    }

    // Sort by distance if location available
    if (_userLat != null && _userLong != null) {
      shops.sort((a, b) {
        final distA = a['distance'] ?? double.infinity;
        final distB = b['distance'] ?? double.infinity;
        return distA.compareTo(distB);
      });
    }

    return shops;
  }

  Future<void> _toggleFavorite(int shopId, FavoritesService favoritesService) async {
    await favoritesService.toggleFavorite(shopId);
    widget.onShopsUpdated();
    setState(() {});
  }

  Future<void> _navigateToShop(double lat, double long) async {
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$long');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final favoritesService = Provider.of<FavoritesService>(context);
    final filteredShops = _getFilteredShops();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Select Shop',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.white,
          ),
        ),
        const SizedBox(height: 12),

        // Search Bar
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: '🔍 Search shops by name...',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
          ),
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
          },
        ),
        const SizedBox(height: 16),

        // Shop List
        SizedBox(
          height: 300,
          child: filteredShops.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.store, size: 48, color: AppColors.white50),
                      const SizedBox(height: 8),
                      const Text(
                        'No shops found',
                        style: TextStyle(color: AppColors.purple200),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: filteredShops.length,
                  itemBuilder: (context, index) {
                    final shop = filteredShops[index];
                    final shopId = shop['id'] as int;
                    final isSelected = widget.selectedShopId == shopId;
                    final isOpen = shop['is_open'] == true;
                    final distance = shop['distance'];
                    final lat = shop['lat'];
                    final long = shop['long'];

                    return FutureBuilder<bool>(
                      future: favoritesService.isFavorite(shopId),
                      builder: (context, snapshot) {
                        final isFavorite = snapshot.data ?? false;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.pink500.withOpacity(0.3)
                                : AppColors.white10,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.pink400
                                  : AppColors.white20,
                              width: 2,
                            ),
                          ),
                          child: InkWell(
                            onTap: () {
                              if (isOpen) {
                                widget.onShopSelected(shopId);
                              } else {
                                _showClosedShopDialog(shop, shopId);
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  shop['shop_name'] ?? 'Unknown',
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                    color: AppColors.white,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
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
                                              ],
                                            ),
                                            if (shop['address'] != null) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                '📍 ${shop['address']}',
                                                style: const TextStyle(
                                                  color: AppColors.white70,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          isFavorite ? Icons.star : Icons.star_border,
                                          color: isFavorite
                                              ? AppColors.yellow300
                                              : AppColors.white50,
                                        ),
                                        onPressed: () {
                                          _toggleFavorite(shopId, favoritesService);
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      if (distance != null)
                                        Text(
                                          '${distance.toStringAsFixed(2)} km away',
                                          style: const TextStyle(
                                            color: AppColors.purple200,
                                            fontSize: 12,
                                          ),
                                        ),
                                      const Spacer(),
                                      if (lat != null && long != null)
                                        IconButton(
                                          icon: const Icon(Icons.navigation),
                                          color: AppColors.blue500,
                                          onPressed: () {
                                            _navigateToShop(
                                              lat.toDouble(),
                                              long.toDouble(),
                                            );
                                          },
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showClosedShopDialog(dynamic shop, int shopId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.white10,
        title: const Row(
          children: [
            Icon(Icons.warning, color: AppColors.yellow500),
            SizedBox(width: 8),
            Text('Shop is Closed'),
          ],
        ),
        content: Text(
          '${shop['shop_name']} is currently closed. Do you still want to send your print to the queue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onShopSelected(shopId);
            },
            child: const Text(
              'Proceed Anyway',
              style: TextStyle(color: AppColors.pink500),
            ),
          ),
        ],
      ),
    );
  }
}

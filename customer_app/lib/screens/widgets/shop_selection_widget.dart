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
  final ScrollController? parentScrollController;

  const ShopSelectionWidget({
    super.key,
    required this.shops,
    required this.selectedShopId,
    required this.onShopSelected,
    required this.onShopsUpdated,
    this.parentScrollController,
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
  bool _isExpanded = false; // Start collapsed to show more content below

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

  String _formatShopPricing(dynamic shop) {
    final effBw = shop['effective_price_per_page_bw'] ?? shop['price_per_page_bw'];
    final effColor = shop['effective_price_per_page_color'] ?? shop['price_per_page_color'];
    final factor = shop['double_sided_factor'];
    final parts = <String>[];
    if (effBw != null) parts.add('B&W: ₹${(effBw as num).toStringAsFixed(2)}/page');
    if (effColor != null) parts.add('Color: ₹${(effColor as num).toStringAsFixed(2)}/page');
    parts.add(factor != null && (factor as num) < 1
        ? 'Double-sided: ${((factor as num) * 100).toStringAsFixed(0)}%'
        : 'Double-sided: full price');
    if (parts.isEmpty) return 'Default pricing · Double-sided: full price';
    return parts.join(' · ');
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

  void _onShopTapped(int shopId, bool isOpen, dynamic shop) {
    if (isOpen) {
      widget.onShopSelected(shopId);
      // Auto-scroll to show upload section after selection
      _scrollToUploadSection();
    } else {
      _showClosedShopDialog(shop, shopId);
    }
  }

  void _scrollToUploadSection() {
    // Delay to allow UI to update, then scroll parent
    Future.delayed(const Duration(milliseconds: 100), () {
      if (widget.parentScrollController != null && 
          widget.parentScrollController!.hasClients) {
        final currentPosition = widget.parentScrollController!.position.pixels;
        final maxScroll = widget.parentScrollController!.position.maxScrollExtent;
        // Scroll down by 150px to reveal upload section, but don't exceed max
        final targetPosition = (currentPosition + 150).clamp(0.0, maxScroll);
        widget.parentScrollController!.animateTo(
          targetPosition,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final favoritesService = Provider.of<FavoritesService>(context);
    final filteredShops = _getFilteredShops();
    
    // Calculate display height based on state
    // Collapsed: show ~2 shops (180px), Expanded: show more (280px)
    final listHeight = _isExpanded ? 280.0 : 180.0;
    final hasMoreShops = filteredShops.length > 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header with shop count
        Row(
          children: [
            const Text(
              'Shops',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.white,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.pink500.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${filteredShops.length} nearby',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.pink400,
                ),
              ),
            ),
            const Spacer(),
            // Selected shop indicator
            if (widget.selectedShopId != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.green500.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 14, color: AppColors.green300),
                    SizedBox(width: 4),
                    Text(
                      'Selected',
                      style: TextStyle(fontSize: 12, color: AppColors.green300),
                    ),
                  ],
                ),
              ),
          ],
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
        const SizedBox(height: 12),

        // Shop List with gradient fade hint
        Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: filteredShops.isEmpty ? 100 : listHeight,
              child: filteredShops.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.store, size: 48, color: AppColors.white50),
                          SizedBox(height: 8),
                          Text(
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
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.pink500.withOpacity(0.3)
                                    : AppColors.white10,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.pink400
                                      : AppColors.white20,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: InkWell(
                                onTap: () => _onShopTapped(shopId, isOpen, shop),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      // Shop info
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    shop['shop_name'] ?? 'Unknown',
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.bold,
                                                      color: AppColors.white,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: isOpen
                                                        ? AppColors.green500.withOpacity(0.3)
                                                        : AppColors.red500.withOpacity(0.3),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(
                                                    isOpen ? 'Open' : 'Closed',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: isOpen
                                                          ? AppColors.green300
                                                          : AppColors.red300,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                if (distance != null) ...[
                                                  const Icon(Icons.location_on, size: 12, color: AppColors.purple200),
                                                  const SizedBox(width: 2),
                                                  Text(
                                                    '${distance.toStringAsFixed(1)} km',
                                                    style: const TextStyle(
                                                      color: AppColors.purple200,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                                if (shop['address'] != null) ...[
                                                  const SizedBox(width: 8),
                                                  Flexible(
                                                    child: Text(
                                                      shop['address'],
                                                      style: const TextStyle(
                                                        color: AppColors.white50,
                                                        fontSize: 11,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _formatShopPricing(shop),
                                              style: const TextStyle(
                                                color: AppColors.purple200,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Action buttons
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (lat != null && long != null)
                                            IconButton(
                                              icon: const Icon(Icons.directions, size: 20),
                                              color: AppColors.blue500,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                              onPressed: () => _navigateToShop(lat.toDouble(), long.toDouble()),
                                              tooltip: 'Get directions',
                                            ),
                                          IconButton(
                                            icon: Icon(
                                              isFavorite ? Icons.star : Icons.star_border,
                                              size: 20,
                                            ),
                                            color: isFavorite ? AppColors.yellow300 : AppColors.white50,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                            onPressed: () => _toggleFavorite(shopId, favoritesService),
                                            tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
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
            // Gradient fade at bottom to hint more content
            if (filteredShops.isNotEmpty && !_isExpanded && hasMoreShops)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          AppColors.indigo900.withOpacity(0.9),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),

        // Expand/Collapse button (only if more than 2 shops)
        if (hasMoreShops)
          TextButton.icon(
            onPressed: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            icon: Icon(
              _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: AppColors.pink400,
              size: 20,
            ),
            label: Text(
              _isExpanded ? 'Show less' : 'Show ${filteredShops.length - 2} more shops',
              style: const TextStyle(
                color: AppColors.pink400,
                fontSize: 13,
              ),
            ),
          ),

        // Scroll hint when shop not selected
        if (widget.selectedShopId == null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.yellow500.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.yellow500.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.touch_app, size: 16, color: AppColors.yellow300),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tap a shop to select, then scroll down to see cost & upload',
                    style: TextStyle(
                      color: AppColors.yellow300,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
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

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  final _apiService = ApiService();
  final _locationService = LocationService();
  List<dynamic> _shops = [];
  double? _userLat;
  double? _userLong;
  bool _isLoading = true;

  Set<Marker> _markers = {};
  bool _shopLoadError = false;
  Timer? _shopRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _getUserLocation();
    _shopRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted && _userLat != null && _userLong != null) {
        _loadShops();
      }
    });
  }

  @override
  void dispose() {
    _shopRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed &&
        _userLat != null &&
        _userLong != null) {
      _loadShops();
    }
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
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadShops() async {
    // Backend returns shops even without location (distance may be null)
    final lat = _userLat ?? 0.0;
    final long = _userLong ?? 0.0;
    try {
      final shops = await _apiService.getShops(lat, long);
      if (mounted) {
        setState(() {
          _shops = shops is List ? shops : [];
          _shopLoadError = false;
          _isLoading = false;
        });
        _updateMarkers();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _shops = [];
          _shopLoadError = true;
          _isLoading = false;
        });
        _updateMarkers();
      }
    }
  }

  void _updateMarkers() {
    final newMarkers = <Marker>{};

    // Add user location marker
    if (_userLat != null && _userLong != null) {
      newMarkers.add(
        Marker(
          markerId: const MarkerId('user_location'),
          position: LatLng(_userLat!, _userLong!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Your Location'),
        ),
      );
    }

    // Add shop markers (green = open, red = closed)
    for (var shop in _shops) {
      if (shop['lat'] != null && shop['long'] != null) {
        final isOpen = shop['is_open'] == true;
        final statusText = isOpen ? 'Open' : 'Closed';
        newMarkers.add(
          Marker(
            markerId: MarkerId('shop_${shop['id']}'),
            position: LatLng(
              shop['lat'].toDouble(),
              shop['long'].toDouble(),
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              isOpen ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
            ),
            infoWindow: InfoWindow(
              title: shop['shop_name'] ?? 'Unknown Shop',
              snippet: '$statusText • ${shop['address'] ?? ''}',
            ),
            onTap: () => _showShopDetails(shop),
          ),
        );
      }
    }

    if (mounted) setState(() => _markers = newMarkers);
  }

  Future<void> _navigateToShop(double lat, double long) async {
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$long');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open Google Maps'),
            backgroundColor: AppColors.red500,
          ),
        );
      }
    }
  }

  String _formatShopPricing(dynamic shop) {
    final effBw = shop['effective_price_per_page_bw'] ?? shop['price_per_page_bw'];
    final effColor = shop['effective_price_per_page_color'] ?? shop['price_per_page_color'];
    final factor = shop['double_sided_factor'];
    final parts = <String>[];
    if (effBw != null) parts.add('B&W: ₹${(effBw as num).toStringAsFixed(2)}/page');
    if (effColor != null) parts.add('Color: ₹${(effColor as num).toStringAsFixed(2)}/page');
    parts.add(factor != null && (factor as num) < 1
        ? 'Double-sided: ${((factor as num) * 100).toStringAsFixed(0)}% of single'
        : 'Double-sided: full price');
    if (parts.isEmpty) return 'Default pricing · Double-sided: full price';
    return parts.join(' · ');
  }

  void _showShopDetails(dynamic shop) {
    final shopName = shop['shop_name'] ?? 'Unknown Shop';
    final address = shop['address'] ?? 'Address not available';
    final lat = shop['lat']?.toDouble();
    final long = shop['long']?.toDouble();
    final distance = shop['distance'];
    final isOpen = shop['is_open'] ?? false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black54,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppColors.indigo900,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: AppColors.white20, width: 1),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with close button
            Row(
              children: [
                Expanded(
                  child: Text(
                    shopName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.white,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isOpen ? AppColors.green500.withValues(alpha: 0.2) : AppColors.red500.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isOpen ? AppColors.green500 : AppColors.red500,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isOpen ? Icons.check_circle : Icons.cancel,
                    size: 16,
                    color: isOpen ? AppColors.green500 : AppColors.red500,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isOpen ? 'Open' : 'Closed',
                    style: TextStyle(
                      color: isOpen ? AppColors.green500 : AppColors.red500,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Address
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on, color: AppColors.purple200, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    address,
                    style: const TextStyle(
                      color: AppColors.white70,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Distance
            if (distance != null && _userLat != null && _userLong != null)
              Row(
                children: [
                  const Icon(Icons.straighten, color: AppColors.purple200, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '${distance.toStringAsFixed(2)} km away',
                    style: const TextStyle(
                      color: AppColors.purple200,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),

            // Pricing (visible to customer; double-sided set by shopkeeper)
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.print, color: AppColors.purple200, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _formatShopPricing(shop),
                    style: const TextStyle(
                      color: AppColors.purple200,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Navigate button
            if (lat != null && long != null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _navigateToShop(lat, long);
                  },
                  icon: const Icon(Icons.navigation, size: 20),
                  label: const Text(
                    'Navigate to Shop',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.blue500,
                    foregroundColor: AppColors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
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
            : _userLat == null || _userLong == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.location_off, size: 64, color: AppColors.white50),
                        const SizedBox(height: 16),
                        const Text(
                          'Location not available',
                          style: TextStyle(
                            color: AppColors.purple200,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: _getUserLocation,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: LatLng(_userLat!, _userLong!),
                          zoom: 13,
                        ),
                        markers: _markers,
                        myLocationEnabled: true,
                        myLocationButtonEnabled: true,
                      ),
                      if (_shopLoadError)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Material(
                            color: Colors.orange.withOpacity(0.9),
                            child: SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(
                                  children: [
                                    const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'Could not load shops. Tap refresh to retry.',
                                        style: TextStyle(color: Colors.white, fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadShops,
        backgroundColor: AppColors.pink500,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

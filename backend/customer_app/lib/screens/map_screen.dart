import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../theme/app_colors.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _apiService = ApiService();
  final _locationService = LocationService();
  List<dynamic> _shops = [];
  double? _userLat;
  double? _userLong;
  bool _isLoading = true;

  final Set<Marker> _markers = {};

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
      _loadShops();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
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
      setState(() {
        _shops = shops;
        _isLoading = false;
        _updateMarkers();
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _updateMarkers() {
    _markers.clear();

    // Add user location marker
    if (_userLat != null && _userLong != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('user_location'),
          position: LatLng(_userLat!, _userLong!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Your Location'),
        ),
      );
    }

    // Add shop markers
    for (var shop in _shops) {
      if (shop['lat'] != null && shop['long'] != null) {
        _markers.add(
          Marker(
            markerId: MarkerId('shop_${shop['id']}'),
            position: LatLng(
              shop['lat'].toDouble(),
              shop['long'].toDouble(),
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(
              title: shop['shop_name'] ?? 'Unknown Shop',
              snippet: shop['address'] ?? '',
            ),
          ),
        );
      }
    }

    setState(() {});
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
                : GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(_userLat!, _userLong!),
                      zoom: 13,
                    ),
                    markers: _markers,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
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

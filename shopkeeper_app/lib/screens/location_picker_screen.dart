import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class LocationPickerScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLong;

  const LocationPickerScreen({
    super.key,
    this.initialLat,
    this.initialLong,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  LatLng? _selectedLocation;
  String? _formattedAddress;
  bool _isLoadingAddress = false;
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchResults = [];
  double? _currentUserLat;
  double? _currentUserLong;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    if (widget.initialLat != null && widget.initialLong != null) {
      setState(() {
        _selectedLocation = LatLng(widget.initialLat!, widget.initialLong!);
      });
      _getAddressFromCoordinates(_selectedLocation!);
    } else {
      await _getCurrentLocation();
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      final isWindows = Platform.isWindows;

      if (!isWindows) {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          _showError('Location services are disabled. Please enable them in your device settings.');
          return;
        }
      }
      // On Windows, skip strict "service enabled" check — the API may still return
      // a position (e.g. via Wi‑Fi/IP) and the user may need to allow location in the system prompt.

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showError('Location permissions are denied.');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showError('Location permissions are permanently denied. Please enable them in device settings.');
        return;
      }

      // On Windows use medium accuracy (faster; uses Wi‑Fi/IP). On mobile use high.
      final accuracy = isWindows ? LocationAccuracy.medium : LocationAccuracy.high;

      Position? position;
      if (isWindows) {
        position = await Geolocator.getLastKnownPosition();
        if (position == null) {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: accuracy,
            timeLimit: const Duration(seconds: 15),
          );
        }
      } else {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: accuracy,
        );
      }

      if (position == null) {
        _showError('Could not get current location. Please pick a point on the map or search for an address.');
        return;
      }

      final lat = position.latitude;
      final lng = position.longitude;
      if (!mounted) return;
      setState(() {
        _currentUserLat = lat;
        _currentUserLong = lng;
        _selectedLocation = LatLng(lat, lng);
      });

      _mapController.move(_selectedLocation!, 15.0);
      _getAddressFromCoordinates(_selectedLocation!);
    } catch (e) {
      _showError('Could not get location: ${e.toString()}. Pick a point on the map or search for an address.');
    }
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      _selectedLocation = point;
    });
    _getAddressFromCoordinates(point);
  }

  Future<void> _getAddressFromCoordinates(LatLng location) async {
    setState(() {
      _isLoadingAddress = true;
    });

    try {
      // Use Nominatim reverse geocoding (free, OpenStreetMap)
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=${location.latitude}&lon=${location.longitude}&zoom=18&addressdetails=1',
      );

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'Qprint Shopkeeper App', // Required by Nominatim
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final address = data['display_name'] ?? 'Address not found';
        setState(() {
          _formattedAddress = address;
          _isLoadingAddress = false;
        });
      } else {
        setState(() {
          _formattedAddress = '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}';
          _isLoadingAddress = false;
        });
      }
    } catch (e) {
      setState(() {
        _formattedAddress = '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}';
        _isLoadingAddress = false;
      });
    }
  }

  Future<void> _searchAddress(String query) async {
    if (query.length < 3) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      // Use Nominatim search (free, OpenStreetMap)
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(query)}&limit=5&addressdetails=1',
      );

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'Qprint Shopkeeper App', // Required by Nominatim
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _searchResults = data.map((item) => {
            'display_name': item['display_name'],
            'lat': double.parse(item['lat']),
            'lon': double.parse(item['lon']),
          }).toList();
          _isSearching = false;
        });
      } else {
        setState(() {
          _isSearching = false;
        });
      }
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
    }
  }

  void _onSearchResultSelected(Map<String, dynamic> result) {
    final location = LatLng(result['lat'], result['lon']);
    setState(() {
      _selectedLocation = location;
      _searchController.text = result['display_name'];
      _searchResults = [];
      _searchFocusNode.unfocus();
    });
    _mapController.move(location, 15.0);
    _getAddressFromCoordinates(location);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _confirmLocation() {
    if (_selectedLocation != null) {
      Navigator.pop(context, {
        'lat': _selectedLocation!.latitude,
        'long': _selectedLocation!.longitude,
        'address': _formattedAddress ?? '',
      });
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selectedLocation ?? const LatLng(20.5937, 78.9629), // Default to India center
              initialZoom: _selectedLocation != null ? 15.0 : 5.0,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.qprint.shopkeeper',
              ),
              // Selected location marker
              if (_selectedLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selectedLocation!,
                      width: 50,
                      height: 50,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 50,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // Search bar at top
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Search input
                    TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      decoration: InputDecoration(
                        hintText: 'Search for address...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchResults = [];
                                  });
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: _searchAddress,
                    ),

                    // Search results dropdown
                    if (_searchResults.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final result = _searchResults[index];
                            return ListTile(
                              leading: const Icon(Icons.location_on, color: Colors.red),
                              title: Text(
                                result['display_name'],
                                style: const TextStyle(fontSize: 14),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _onSearchResultSelected(result),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Address card at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Selected Location:',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_isLoadingAddress)
                      const Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('Loading address...'),
                        ],
                      )
                    else
                      Text(
                        _formattedAddress ?? 'Tap on map to select location',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    if (_selectedLocation != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Coordinates: ${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: _selectedLocation != null ? _confirmLocation : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.pinkAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              disabledBackgroundColor: Colors.grey,
                            ),
                            child: const Text('Confirm Location'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Get current location FAB
          Positioned(
            bottom: 120,
            right: 16,
            child: FloatingActionButton(
              mini: true,
              onPressed: _getCurrentLocation,
              backgroundColor: Colors.white,
              child: const Icon(Icons.my_location, color: Colors.pinkAccent),
            ),
          ),
        ],
      ),
    );
  }
}

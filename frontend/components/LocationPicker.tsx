"use client";

import { useState, useEffect, useRef } from 'react';
import axios from 'axios';

// Dynamically import react-leaflet to avoid SSR issues
let MapContainer: any = null;
let TileLayer: any = null;
let Marker: any = null;
let useMapEvents: any = null;
let useMap: any = null;

// Function to load react-leaflet only on client side
function loadReactLeaflet() {
    if (typeof window !== 'undefined' && !MapContainer) {
        try {
            const ReactLeaflet = require('react-leaflet');
            MapContainer = ReactLeaflet.MapContainer;
            TileLayer = ReactLeaflet.TileLayer;
            Marker = ReactLeaflet.Marker;
            useMapEvents = ReactLeaflet.useMapEvents;
            useMap = ReactLeaflet.useMap;
        } catch (e) {
            console.error('Failed to load react-leaflet:', e);
        }
    }
}

// Initialize Leaflet icons only on client side
let defaultIcon: any = null;
let selectedIcon: any = null;
let LatLng: any = null;

if (typeof window !== 'undefined') {
    // Import Leaflet CSS only on client side
    require('leaflet/dist/leaflet.css');
    
    const L = require('leaflet');
    LatLng = L.LatLng;
    
    // Fix for default marker icons in Next.js
    const iconUrl = 'https://unpkg.com/leaflet@1.7.1/dist/images/marker-icon.png';
    const iconRetinaUrl = 'https://unpkg.com/leaflet@1.7.1/dist/images/marker-icon-2x.png';
    const shadowUrl = 'https://unpkg.com/leaflet@1.7.1/dist/images/marker-shadow.png';

    defaultIcon = L.icon({
        iconUrl,
        iconRetinaUrl,
        shadowUrl,
        iconSize: [25, 41],
        iconAnchor: [12, 41],
        popupAnchor: [1, -34],
        shadowSize: [41, 41]
    });

    L.Marker.prototype.options.icon = defaultIcon;

    // Custom red marker for selected location
    selectedIcon = L.icon({
        iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-red.png',
        shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png',
        iconSize: [25, 41],
        iconAnchor: [12, 41],
        popupAnchor: [1, -34],
        shadowSize: [41, 41]
    });
}

// Component to handle map clicks and center updates
function MapClickHandler({ onLocationSelect }: { onLocationSelect: (lat: number, lng: number) => void }) {
    if (!useMapEvents) return null;
    
    const mapEvents = useMapEvents({
        click(e: any) {
            onLocationSelect(e.latlng.lat, e.latlng.lng);
        },
    });
    return null;
}

// Component to update map center
function MapCenterUpdater({ center }: { center: any }) {
    if (!useMap) return null;
    
    const map = useMap();
    useEffect(() => {
        if (map && center) {
            map.setView(center, 15);
        }
    }, [center, map]);
    return null;
}

interface LocationPickerProps {
    initialLat?: number;
    initialLng?: number;
    onLocationSelect: (lat: number, lng: number, address: string) => void;
    onCancel: () => void;
}

export default function LocationPicker({ initialLat, initialLng, onLocationSelect, onCancel }: LocationPickerProps) {
    const [selectedLocation, setSelectedLocation] = useState<any>(null);
    const [isClient, setIsClient] = useState(false);
    
    // Initialize on client side only
    useEffect(() => {
        setIsClient(true);
        // Load react-leaflet on client side
        loadReactLeaflet();
        
        if (typeof window !== 'undefined' && LatLng) {
            if (initialLat && initialLng) {
                setSelectedLocation(new LatLng(initialLat, initialLng));
            }
        }
    }, [initialLat, initialLng]);
    const [address, setAddress] = useState<string>('');
    const [isLoadingAddress, setIsLoadingAddress] = useState(false);
    const [searchQuery, setSearchQuery] = useState('');
    const [searchResults, setSearchResults] = useState<any[]>([]);
    const [isSearching, setIsSearching] = useState(false);
    const searchTimeoutRef = useRef<NodeJS.Timeout | null>(null);

    // Get current location on mount if no initial location
    useEffect(() => {
        // Check if we're in browser environment
        if (typeof window === 'undefined') return;
        
        if (!selectedLocation && typeof navigator !== 'undefined' && navigator.geolocation) {
            navigator.geolocation.getCurrentPosition(
                (position) => {
                    const location = new LatLng(position.coords.latitude, position.coords.longitude);
                    setSelectedLocation(location);
                    getAddressFromCoordinates(location.lat, location.lng);
                },
                (error) => {
                    console.error('Geolocation error:', error);
                    // Default to India center if geolocation fails
                    if (LatLng) {
                        const defaultLocation = new LatLng(20.5937, 78.9629);
                        setSelectedLocation(defaultLocation);
                    }
                }
            );
        } else if (selectedLocation) {
            getAddressFromCoordinates(selectedLocation.lat, selectedLocation.lng);
        } else if (LatLng) {
            // Default to India center if no location and no geolocation
            const defaultLocation = new LatLng(20.5937, 78.9629);
            setSelectedLocation(defaultLocation);
        }
    }, []);

    const getAddressFromCoordinates = async (lat: number, lng: number) => {
        setIsLoadingAddress(true);
        try {
            // Use Nominatim reverse geocoding (free, OpenStreetMap)
            const response = await axios.get(
                `https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lng}&zoom=18&addressdetails=1`,
                {
                    headers: {
                        'User-Agent': 'Qprint Web App', // Required by Nominatim
                    },
                }
            );

            if (response.data && response.data.display_name) {
                setAddress(response.data.display_name);
            } else {
                setAddress(`${lat.toFixed(6)}, ${lng.toFixed(6)}`);
            }
        } catch (error) {
            console.error('Reverse geocoding error:', error);
            setAddress(`${lat.toFixed(6)}, ${lng.toFixed(6)}`);
        } finally {
            setIsLoadingAddress(false);
        }
    };

    const handleLocationSelect = (lat: number, lng: number) => {
        if (typeof window !== 'undefined' && LatLng) {
            const location = new LatLng(lat, lng);
            setSelectedLocation(location);
            getAddressFromCoordinates(lat, lng);
        }
    };

    const searchAddress = async (query: string) => {
        if (query.length < 3) {
            setSearchResults([]);
            return;
        }

        setIsSearching(true);

        // Clear previous timeout
        if (searchTimeoutRef.current) {
            clearTimeout(searchTimeoutRef.current);
        }

        // Debounce search
        searchTimeoutRef.current = setTimeout(async () => {
            try {
                const response = await axios.get(
                    `https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(query)}&limit=5&addressdetails=1`,
                    {
                        headers: {
                            'User-Agent': 'Qprint Web App',
                        },
                    }
                );

                if (response.data && Array.isArray(response.data)) {
                    setSearchResults(response.data);
                }
            } catch (error) {
                console.error('Search error:', error);
            } finally {
                setIsSearching(false);
            }
        }, 300);
    };

    const handleSearchResultClick = (result: any) => {
        const lat = parseFloat(result.lat);
        const lng = parseFloat(result.lon);
        handleLocationSelect(lat, lng);
        setSearchQuery(result.display_name);
        setSearchResults([]);
    };

    const handleConfirm = () => {
        if (selectedLocation) {
            onLocationSelect(selectedLocation.lat, selectedLocation.lng, address);
        }
    };

    const handleGetCurrentLocation = () => {
        if (typeof window !== 'undefined' && typeof navigator !== 'undefined' && navigator.geolocation) {
            navigator.geolocation.getCurrentPosition(
                (position) => {
                    handleLocationSelect(position.coords.latitude, position.coords.longitude);
                },
                (error) => {
                    console.error('Geolocation error:', error);
                    alert('Could not get your current location. Please select a location on the map.');
                }
            );
        }
    };

    return (
        <div className="fixed inset-0 z-50 bg-black bg-opacity-50 flex items-center justify-center p-4">
            <div className="bg-white rounded-2xl shadow-2xl w-full max-w-4xl h-[90vh] flex flex-col overflow-hidden">
                {/* Header */}
                <div className="p-4 border-b border-gray-200 flex items-center justify-between">
                    <h2 className="text-xl font-bold text-gray-800">Select Shop Location</h2>
                    <button
                        onClick={onCancel}
                        className="text-gray-500 hover:text-gray-700 text-2xl"
                    >
                        ×
                    </button>
                </div>

                {/* Search Bar */}
                <div className="p-4 border-b border-gray-200 relative">
                    <div className="relative">
                        <input
                            type="text"
                            value={searchQuery}
                            onChange={(e) => {
                                setSearchQuery(e.target.value);
                                searchAddress(e.target.value);
                            }}
                            placeholder="Search for address..."
                            className="w-full px-4 py-3 pl-10 pr-10 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-pink-500"
                        />
                        <div className="absolute left-3 top-1/2 transform -translate-y-1/2">
                            {isSearching ? (
                                <div className="animate-spin rounded-full h-5 w-5 border-b-2 border-pink-500"></div>
                            ) : (
                                <svg className="w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                                </svg>
                            )}
                        </div>
                        {searchQuery && (
                            <button
                                onClick={() => {
                                    setSearchQuery('');
                                    setSearchResults([]);
                                }}
                                className="absolute right-3 top-1/2 transform -translate-y-1/2 text-gray-400 hover:text-gray-600"
                            >
                                ×
                            </button>
                        )}
                    </div>

                    {/* Search Results Dropdown */}
                    {searchResults.length > 0 && (
                        <div className="absolute z-10 w-full mt-2 bg-white border border-gray-200 rounded-lg shadow-lg max-h-60 overflow-y-auto">
                            {searchResults.map((result, index) => (
                                <button
                                    key={index}
                                    onClick={() => handleSearchResultClick(result)}
                                    className="w-full px-4 py-3 text-left hover:bg-gray-100 flex items-start gap-3 border-b border-gray-100 last:border-b-0"
                                >
                                    <svg className="w-5 h-5 text-red-500 mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                                    </svg>
                                    <span className="text-sm text-gray-700 line-clamp-2">{result.display_name}</span>
                                </button>
                            ))}
                        </div>
                    )}
                </div>

                {/* Map Container */}
                <div className="flex-1 relative">
                    {isClient && selectedLocation && MapContainer && TileLayer && Marker ? (
                        <MapContainer
                            center={selectedLocation}
                            zoom={15}
                            scrollWheelZoom={true}
                            className="h-full w-full z-0"
                        >
                            <TileLayer
                                attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
                                url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                            />
                            <Marker position={selectedLocation} icon={selectedIcon}>
                            </Marker>
                            {useMapEvents && <MapClickHandler onLocationSelect={handleLocationSelect} />}
                            {useMap && <MapCenterUpdater center={selectedLocation} />}
                        </MapContainer>
                    ) : (
                        <div className="h-full w-full bg-gray-200 flex items-center justify-center">
                            <div className="text-center">
                                <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-pink-500 mx-auto mb-4"></div>
                                <p className="text-gray-600">Loading map...</p>
                            </div>
                        </div>
                    )}

                    {/* Get Current Location Button */}
                    <button
                        onClick={handleGetCurrentLocation}
                        className="absolute bottom-4 right-4 bg-white p-3 rounded-full shadow-lg hover:bg-gray-50 transition-colors z-[1000]"
                        title="Get Current Location"
                    >
                        <svg className="w-6 h-6 text-pink-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                        </svg>
                    </button>
                </div>

                {/* Address Display and Actions */}
                <div className="p-4 border-t border-gray-200 bg-gray-50">
                    <div className="mb-4">
                        <label className="block text-xs font-semibold text-gray-500 mb-2">Selected Location:</label>
                        {isLoadingAddress ? (
                            <div className="flex items-center gap-2">
                                <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-pink-500"></div>
                                <span className="text-sm text-gray-600">Loading address...</span>
                            </div>
                        ) : (
                            <p className="text-sm font-medium text-gray-800">{address || 'Tap on map to select location'}</p>
                        )}
                        {selectedLocation && (
                            <p className="text-xs text-gray-500 mt-1 font-mono">
                                {selectedLocation.lat.toFixed(6)}, {selectedLocation.lng.toFixed(6)}
                            </p>
                        )}
                    </div>
                    <div className="flex gap-3">
                        <button
                            onClick={onCancel}
                            className="flex-1 px-4 py-2 border border-gray-300 rounded-lg text-gray-700 hover:bg-gray-100 transition-colors font-medium"
                        >
                            Cancel
                        </button>
                        <button
                            onClick={handleConfirm}
                            disabled={!selectedLocation}
                            className="flex-1 px-4 py-2 bg-gradient-to-r from-pink-500 to-purple-600 text-white rounded-lg hover:from-pink-600 hover:to-purple-700 transition-all disabled:opacity-50 disabled:cursor-not-allowed font-medium"
                        >
                            Confirm Location
                        </button>
                    </div>
                </div>
            </div>
        </div>
    );
}

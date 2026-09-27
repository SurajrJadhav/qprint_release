"use client";

import { useEffect, useState } from 'react';
import { MapContainer, TileLayer, Marker, Popup } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import L from 'leaflet';

// Fix for default marker icons in Next.js
const iconUrl = 'https://unpkg.com/leaflet@1.7.1/dist/images/marker-icon.png';
const iconRetinaUrl = 'https://unpkg.com/leaflet@1.7.1/dist/images/marker-icon-2x.png';
const shadowUrl = 'https://unpkg.com/leaflet@1.7.1/dist/images/marker-shadow.png';

// Custom icons
const userIcon = new L.Icon({
    iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-blue.png',
    shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png',
    iconSize: [25, 41],
    iconAnchor: [12, 41],
    popupAnchor: [1, -34],
    shadowSize: [41, 41]
});

const shopIcon = new L.Icon({
    iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-red.png',
    shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png',
    iconSize: [25, 41],
    iconAnchor: [12, 41],
    popupAnchor: [1, -34],
    shadowSize: [41, 41]
});

interface Shop {
    id: number;
    shop_name: string;
    distance?: number | null; // Optional - null if user doesn't have location
    lat: number;
    long: number;
}

interface MapProps {
    userLat: number;
    userLong: number;
    shops: Shop[];
}

export default function MapComponent({ userLat, userLong, shops }: MapProps) {
    const [isMounted, setIsMounted] = useState(false);

    useEffect(() => {
        setIsMounted(true);
    }, []);

    // Validate coordinates
    if (!isMounted || typeof userLat !== 'number' || typeof userLong !== 'number') {
        return <div className="h-[400px] w-full bg-gray-200 animate-pulse rounded-xl"></div>;
    }

    // Filter shops with valid coordinates
    const validShops = shops.filter(shop =>
        typeof shop.lat === 'number' &&
        typeof shop.long === 'number' &&
        !isNaN(shop.lat) &&
        !isNaN(shop.long)
    );

    return (
        <MapContainer
            center={[userLat, userLong]}
            zoom={13}
            scrollWheelZoom={false}
            className="h-[400px] w-full rounded-xl z-0"
        >
            <TileLayer
                attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
                url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
            />

            {/* User Location */}
            <Marker position={[userLat, userLong]} icon={userIcon}>
                <Popup>
                    <div className="text-center">
                        <h3 className="font-bold">You are here</h3>
                    </div>
                </Popup>
            </Marker>

            {/* Shop Locations */}
            {validShops.map((shop) => (
                <Marker
                    key={shop.id}
                    position={[shop.lat, shop.long]}
                    icon={shopIcon}
                >
                    <Popup>
                        <div className="text-center">
                            <h3 className="font-bold text-lg">{shop.shop_name}</h3>
                            {shop.distance !== null && shop.distance !== undefined && (
                                <p className="text-sm text-gray-600">{shop.distance.toFixed(1)} km away</p>
                            )}
                            <a
                                href={`https://www.google.com/maps/dir/?api=1&destination=${shop.lat},${shop.long}`}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="block mt-2 bg-blue-500 text-white px-3 py-1 rounded text-sm hover:bg-blue-600"
                            >
                                Get Directions 🧭
                            </a>
                        </div>
                    </Popup>
                </Marker>
            ))}
        </MapContainer>
    );
}

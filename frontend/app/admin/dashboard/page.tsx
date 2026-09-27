"use client";

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import api, { logout } from '@/lib/api';
import Link from 'next/link';

interface DashboardStats {
    total_users: number;
    total_customers: number;
    total_shopkeepers: number;
    total_orders: number;
    total_revenue: number;
    pending_payouts: number;
    paid_payouts: number;
    active_orders: number;
    failed_orders: number;
}

export default function AdminDashboard() {
    const [stats, setStats] = useState<DashboardStats | null>(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');
    const router = useRouter();

    useEffect(() => {
        const token = localStorage.getItem('token') || sessionStorage.getItem('token');
        const role = localStorage.getItem('role');
        if ((!token && !role) || role !== 'admin') {
            router.push('/login');
            return;
        }

        fetchStats();
    }, []);

    const fetchStats = async () => {
        try {
            const res = await api.get('/admin/dashboard/stats');
            setStats(res.data);
            setLoading(false);
        } catch (err: any) {
            console.error('Failed to fetch stats:', err);
            setError('Failed to load dashboard statistics');
            setLoading(false);
        }
    };

    const handleLogout = async () => {
        await logout();
        router.push('/login');
    };

    if (loading) {
        return (
            <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800 flex items-center justify-center">
                <div className="text-white text-xl">Loading...</div>
            </div>
        );
    }

    if (error) {
        return (
            <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800 flex items-center justify-center">
                <div className="text-red-300 bg-red-500/20 p-4 rounded-lg">{error}</div>
            </div>
        );
    }

    return (
        <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800">
            <div className="container mx-auto px-4 py-8">
                {/* Header */}
                <div className="flex justify-between items-center mb-8">
                    <div>
                        <h1 className="text-4xl font-black text-white mb-2">
                            Admin <span className="text-pink-400">Dashboard</span>
                        </h1>
                        <p className="text-purple-200">Manage your platform</p>
                    </div>
                    <div className="flex gap-4">
                        <button
                            onClick={handleLogout}
                            className="bg-red-500/20 hover:bg-red-500/30 text-white px-4 py-2 rounded-lg border border-red-400/50"
                        >
                            Logout
                        </button>
                    </div>
                </div>

                {/* Navigation */}
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
                    <Link href="/admin/users" className="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20 hover:bg-white/20 transition-all">
                        <h3 className="text-xl font-bold text-white mb-2">👥 Users</h3>
                        <p className="text-purple-200">Manage customers and shopkeepers</p>
                    </Link>
                    <Link href="/admin/orders" className="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20 hover:bg-white/20 transition-all">
                        <h3 className="text-xl font-bold text-white mb-2">📦 Orders</h3>
                        <p className="text-purple-200">View and manage all orders</p>
                    </Link>
                    <Link href="/admin/payouts" className="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20 hover:bg-white/20 transition-all">
                        <h3 className="text-xl font-bold text-white mb-2">💰 Payouts</h3>
                        <p className="text-purple-200">Manage shopkeeper payouts</p>
                    </Link>
                    <Link href="/admin/payments" className="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20 hover:bg-white/20 transition-all">
                        <h3 className="text-xl font-bold text-white mb-2">🏪 Manage Payments</h3>
                        <p className="text-purple-200">Select a shop, view payout history, mark as done</p>
                    </Link>
                    <Link href="/admin/downloads" className="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20 hover:bg-white/20 transition-all">
                        <h3 className="text-xl font-bold text-white mb-2">📥 App Downloads</h3>
                        <p className="text-purple-200">Set download links for Windows, Android, and iOS apps</p>
                    </Link>
                </div>

                {/* Stats Grid */}
                {stats && (
                    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
                        <div className="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20">
                            <div className="text-purple-200 text-sm mb-2">Total Users</div>
                            <div className="text-3xl font-bold text-white">{stats.total_users}</div>
                            <div className="text-xs text-purple-300 mt-2">
                                {stats.total_customers} customers • {stats.total_shopkeepers} shopkeepers
                            </div>
                        </div>

                        <div className="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20">
                            <div className="text-purple-200 text-sm mb-2">Total Orders</div>
                            <div className="text-3xl font-bold text-white">{stats.total_orders}</div>
                            <div className="text-xs text-purple-300 mt-2">
                                {stats.active_orders} active • {stats.failed_orders} failed
                            </div>
                        </div>

                        <div className="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20">
                            <div className="text-purple-200 text-sm mb-2">Total Revenue</div>
                            <div className="text-3xl font-bold text-green-400">₹{stats.total_revenue.toFixed(2)}</div>
                            <div className="text-xs text-purple-300 mt-2">All time</div>
                        </div>

                        <div className="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20">
                            <div className="text-purple-200 text-sm mb-2">Pending Payouts</div>
                            <div className="text-3xl font-bold text-yellow-400">₹{stats.pending_payouts.toFixed(2)}</div>
                            <div className="text-xs text-purple-300 mt-2">
                                ₹{stats.paid_payouts.toFixed(2)} paid
                            </div>
                        </div>
                    </div>
                )}
            </div>
        </div>
    );
}

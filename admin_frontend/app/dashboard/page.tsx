"use client";

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import api from '@/lib/api';
import Link from 'next/link';
import { getAdminMe, updateAdminMe, fetchCsrfToken, type AdminMe } from '@/lib/api';

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
    const [adminMe, setAdminMe] = useState<AdminMe | null>(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');
    const [editingProfile, setEditingProfile] = useState(false);
    const [profileEmail, setProfileEmail] = useState('');
    const [profileFullName, setProfileFullName] = useState('');
    const [profileSaving, setProfileSaving] = useState(false);
    const [profileMessage, setProfileMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null);
    const router = useRouter();

    useEffect(() => {
        const token = localStorage.getItem('token');
        const role = localStorage.getItem('role');

        if (!token || role !== 'admin') {
            router.push('/login');
            return;
        }

        const fetchStats = async () => {
            try {
                await fetchCsrfToken();
                const [statsRes, meRes] = await Promise.all([
                    api.get('/admin/dashboard/stats'),
                    getAdminMe(),
                ]);
                setStats(statsRes.data);
                setAdminMe(meRes);
                setLoading(false);
            } catch (err: any) {
                console.error('Failed to fetch stats:', err);
                if (err.response) {
                    if (err.response.status === 401) {
                        setError('Session expired. Please login again.');
                        setTimeout(() => router.push('/login'), 2000);
                    } else if (err.response.status === 403) {
                        setError('Access denied. Admin account required.');
                        setTimeout(() => router.push('/login'), 2000);
                    } else {
                        setError(`Failed to load dashboard statistics: ${err.response.data || err.response.statusText}`);
                    }
                } else if (err.request) {
                    setError('Cannot connect to server. Please ensure backend is running on port 8080.');
                } else {
                    setError('Failed to load dashboard statistics: ' + err.message);
                }
                setLoading(false);
            }
        };

        fetchStats();
    }, [router]);

    const handleLogout = () => {
        localStorage.removeItem('token');
        localStorage.removeItem('role');
        localStorage.removeItem('display_name');
        localStorage.removeItem('username');
        router.push('/login');
    };

    const startEditProfile = () => {
        if (adminMe) {
            setProfileEmail(adminMe.email || '');
            setProfileFullName(adminMe.full_name || '');
            setEditingProfile(true);
            setProfileMessage(null);
        }
    };

    const cancelEditProfile = () => {
        setEditingProfile(false);
        setProfileMessage(null);
    };

    const handleSaveProfile = async (e: React.FormEvent) => {
        e.preventDefault();
        setProfileMessage(null);
        setProfileSaving(true);
        try {
            await updateAdminMe({ email: profileEmail.trim(), full_name: profileFullName.trim() });
            setProfileMessage({ type: 'success', text: 'Profile updated.' });
            const updated = await getAdminMe();
            setAdminMe(updated);
            setEditingProfile(false);
        } catch (err: any) {
            let text = 'Failed to update.';
            if (err.response) {
                const d = err.response.data;
                if (typeof d === 'string' && d.trim()) text = d.trim();
                else if (d?.message) text = d.message;
                else if (d?.error) text = d.error;
                else if (err.response.status) text = `Request failed (${err.response.status}). Try again or check the console.`;
            } else if (err.request) {
                text = 'No response from server. Check the API URL and network.';
            }
            setProfileMessage({ type: 'error', text });
        } finally {
            setProfileSaving(false);
        }
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

                {/* Admin account info */}
                {adminMe && (
                    <div className="bg-white/10 backdrop-blur-lg rounded-xl p-5 border border-white/20 mb-8">
                        <div className="flex justify-between items-center mb-3">
                            <h2 className="text-lg font-bold text-white">👤 Admin account</h2>
                            {!editingProfile ? (
                                <button type="button" onClick={startEditProfile} className="text-sm text-purple-200 hover:text-white underline">
                                    Update email / name
                                </button>
                            ) : null}
                        </div>
                        {profileMessage && (
                            <div className={`mb-3 p-3 rounded-lg text-sm ${profileMessage.type === 'success' ? 'bg-green-500/20 text-green-200' : 'bg-red-500/20 text-red-200'}`}>
                                {profileMessage.text}
                            </div>
                        )}
                        {editingProfile ? (
                            <form onSubmit={handleSaveProfile} className="space-y-4">
                                <div>
                                    <label className="block text-purple-200 text-sm mb-1">Email</label>
                                    <input
                                        type="email"
                                        value={profileEmail}
                                        onChange={(e) => setProfileEmail(e.target.value)}
                                        placeholder="admin@example.com"
                                        className="w-full max-w-md px-3 py-2 rounded-lg bg-white/10 border border-white/20 text-white placeholder-purple-300 focus:ring-2 focus:ring-pink-500"
                                    />
                                    <p className="text-purple-200/80 text-xs mt-1">Required for email 2FA and &quot;Sign in with email OTP&quot;</p>
                                </div>
                                <div>
                                    <label className="block text-purple-200 text-sm mb-1">Display name</label>
                                    <input
                                        type="text"
                                        value={profileFullName}
                                        onChange={(e) => setProfileFullName(e.target.value)}
                                        placeholder="Your name"
                                        className="w-full max-w-md px-3 py-2 rounded-lg bg-white/10 border border-white/20 text-white placeholder-purple-300 focus:ring-2 focus:ring-pink-500"
                                    />
                                </div>
                                <div className="flex gap-2">
                                    <button type="submit" disabled={profileSaving} className="px-4 py-2 bg-pink-500/80 hover:bg-pink-500 text-white rounded-lg text-sm font-medium disabled:opacity-50">
                                        {profileSaving ? 'Saving…' : 'Save'}
                                    </button>
                                    <button type="button" onClick={cancelEditProfile} className="px-4 py-2 bg-white/10 hover:bg-white/20 text-white rounded-lg text-sm">
                                        Cancel
                                    </button>
                                </div>
                            </form>
                        ) : (
                            <>
                                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 text-sm">
                                    <div>
                                        <span className="text-purple-200">Name</span>
                                        <p className="text-white font-medium">{adminMe.display_name || adminMe.full_name}</p>
                                    </div>
                                    <div>
                                        <span className="text-purple-200">Email</span>
                                        <p className="text-white font-medium">
                                            {adminMe.email ? adminMe.email : <span className="text-amber-300">Not set — required for 2FA & email login</span>}
                                        </p>
                                    </div>
                                    <div>
                                        <span className="text-purple-200">Name</span>
                                        <p className="text-white font-medium">{adminMe.full_name || '—'}</p>
                                    </div>
                                    <div>
                                        <span className="text-purple-200">Email 2FA</span>
                                        <p className="text-white font-medium">{adminMe.email_2fa_enabled ? 'Enabled' : 'Disabled'}</p>
                                    </div>
                                </div>
                                {!adminMe.email && (
                                    <p className="text-amber-200/90 text-xs mt-3">Click &quot;Update email / name&quot; above to set your email for 2FA and email login.</p>
                                )}
                            </>
                        )}
                    </div>
                )}

                {/* Navigation */}
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
                    <Link href="/shops" className="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20 hover:bg-white/20 transition-all">
                        <h3 className="text-xl font-bold text-white mb-2">🏪 Shops</h3>
                        <p className="text-purple-200">Browse shops, orders per shop, and payouts in one place</p>
                    </Link>
                    <Link href="/users" className="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20 hover:bg-white/20 transition-all">
                        <h3 className="text-xl font-bold text-white mb-2">👥 Users</h3>
                        <p className="text-purple-200">Manage customers and shopkeepers</p>
                    </Link>
                    <Link href="/orders" className="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20 hover:bg-white/20 transition-all">
                        <h3 className="text-xl font-bold text-white mb-2">📦 Orders</h3>
                        <p className="text-purple-200">View and manage all orders</p>
                    </Link>
                    <Link href="/payouts" className="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20 hover:bg-white/20 transition-all">
                        <h3 className="text-xl font-bold text-white mb-2">💰 Payouts</h3>
                        <p className="text-purple-200">Manage shopkeeper payouts</p>
                    </Link>
                    <Link href="/payments" className="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20 hover:bg-white/20 transition-all">
                        <h3 className="text-xl font-bold text-white mb-2">🏪 Manage Payments</h3>
                        <p className="text-purple-200">Select a shop, view payout history, mark as done</p>
                    </Link>
                    <Link href="/downloads" className="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20 hover:bg-white/20 transition-all">
                        <h3 className="text-xl font-bold text-white mb-2">📥 App Download Links</h3>
                        <p className="text-purple-200">Set download links for Windows, Android, and iOS apps (shown on Download Apps page)</p>
                    </Link>
                    <Link href="/notifications" className="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20 hover:bg-white/20 transition-all">
                        <h3 className="text-xl font-bold text-white mb-2">🔔 Send Notification</h3>
                        <p className="text-purple-200">Send push notification to all customer app users</p>
                    </Link>
                    <Link href="/2fa" className="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20 hover:bg-white/20 transition-all">
                        <h3 className="text-xl font-bold text-white mb-2">🔐 Two-Factor Auth</h3>
                        <p className="text-purple-200">Enable or disable 2FA for your admin account</p>
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

"use client";

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import api, { logout } from '@/lib/api';
import { getSafeErrorMessage } from '@/lib/safeError';
import Link from 'next/link';

interface User {
    id: number;
    full_name?: string;
    email?: string;
    phone?: string;
    shop_name?: string;
    role: string;
    created_at: string;
    total_orders: number;
    total_spent?: number;
    total_earned?: number;
}

interface UserListResponse {
    users: User[];
    total: number;
    page: number;
    page_size: number;
    total_pages: number;
}

export default function AdminUsers() {
    const [data, setData] = useState<UserListResponse | null>(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');
    const [page, setPage] = useState(1);
    const [roleFilter, setRoleFilter] = useState('');
    const [search, setSearch] = useState('');
    const router = useRouter();

    useEffect(() => {
        const token = localStorage.getItem('token') || sessionStorage.getItem('token');
        const role = localStorage.getItem('role');
        
        if ((!token && !role) || role !== 'admin') {
            router.push('/login');
            return;
        }

        fetchUsers();
    }, [page, roleFilter]);

    const fetchUsers = async () => {
        try {
            setLoading(true);
            const params = new URLSearchParams({
                page: page.toString(),
                page_size: '20',
            });
            if (roleFilter) params.append('role', roleFilter);
            if (search) params.append('search', search);

            const res = await api.get(`/admin/users?${params.toString()}`);
            setData(res.data);
            setLoading(false);
        } catch (err: any) {
            console.error('Failed to fetch users:', err);
            setError('Failed to load users');
            setLoading(false);
        }
    };

    const handleSearch = () => {
        setPage(1);
        fetchUsers();
    };

    const handleDelete = async (userId: number, label: string) => {
        if (!confirm(`Are you sure you want to delete user "${label}"? This action cannot be undone.`)) {
            return;
        }

        try {
            await api.post('/admin/users/delete', {
                user_id: userId
            });
            alert('User deleted successfully');
            fetchUsers();
        } catch (err: unknown) {
            console.error('Failed to delete user:', err);
            alert(getSafeErrorMessage(err, 'user'));
        }
    };

    const handleLogout = async () => {
        await logout();
        router.push('/login');
    };

    if (loading && !data) {
        return (
            <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800 flex items-center justify-center">
                <div className="text-white text-xl">Loading...</div>
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
                            User <span className="text-pink-400">Management</span>
                        </h1>
                        <p className="text-purple-200">Manage customers and shopkeepers</p>
                    </div>
                    <div className="flex gap-4">
                        <Link href="/admin/dashboard" className="bg-white/10 hover:bg-white/20 text-white px-4 py-2 rounded-lg border border-white/20">
                            Dashboard
                        </Link>
                        <button
                            onClick={handleLogout}
                            className="bg-red-500/20 hover:bg-red-500/30 text-white px-4 py-2 rounded-lg border border-red-400/50"
                        >
                            Logout
                        </button>
                    </div>
                </div>

                {/* Filters */}
                <div className="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20 mb-6">
                    <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                        <div>
                            <label className="block text-purple-200 text-sm mb-2">Search</label>
                            <input
                                type="text"
                                value={search}
                                onChange={(e) => setSearch(e.target.value)}
                                placeholder="Name, email, or phone"
                                className="w-full bg-white/20 border border-white/30 p-2 rounded-lg text-white placeholder-purple-200"
                            />
                        </div>
                        <div>
                            <label className="block text-purple-200 text-sm mb-2">Role</label>
                            <select
                                value={roleFilter}
                                onChange={(e) => setRoleFilter(e.target.value)}
                                className="w-full bg-white/20 border border-white/30 p-2 rounded-lg text-white"
                            >
                                <option value="">All</option>
                                <option value="customer">Customer</option>
                                <option value="shopkeeper">Shopkeeper</option>
                            </select>
                        </div>
                        <div className="flex items-end">
                            <button
                                onClick={handleSearch}
                                className="w-full bg-gradient-to-r from-pink-500 to-purple-600 text-white font-bold p-2 rounded-lg hover:from-pink-600 hover:to-purple-700"
                            >
                                Search
                            </button>
                        </div>
                    </div>
                </div>

                {/* Users Table */}
                <div className="bg-white/10 backdrop-blur-lg rounded-xl border border-white/20 overflow-hidden">
                    <div className="overflow-x-auto">
                        <table className="w-full">
                            <thead className="bg-white/10">
                                <tr>
                                    <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">ID</th>
                                    <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Name</th>
                                    <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Shop</th>
                                    <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Email</th>
                                    <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Phone</th>
                                    <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Role</th>
                                    <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Orders</th>
                                    <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Amount</th>
                                    <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Actions</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-white/10">
                                {data?.users.map((user) => (
                                    <tr key={user.id} className="hover:bg-white/5">
                                        <td className="px-6 py-4 whitespace-nowrap text-white">{user.id}</td>
                                        <td className="px-6 py-4 whitespace-nowrap text-white font-medium">{user.full_name || user.email || `User #${user.id}`}</td>
                                        <td className="px-6 py-4 whitespace-nowrap text-white">{user.shop_name || '-'}</td>
                                        <td className="px-6 py-4 whitespace-nowrap text-white">{user.email || '-'}</td>
                                        <td className="px-6 py-4 whitespace-nowrap text-white">{user.phone || '-'}</td>
                                        <td className="px-6 py-4 whitespace-nowrap">
                                            <span className={`px-2 py-1 rounded text-xs font-medium ${
                                                user.role === 'customer' ? 'bg-blue-500/20 text-blue-300' :
                                                user.role === 'shopkeeper' ? 'bg-green-500/20 text-green-300' :
                                                'bg-purple-500/20 text-purple-300'
                                            }`}>
                                                {user.role}
                                            </span>
                                        </td>
                                        <td className="px-6 py-4 whitespace-nowrap text-white">{user.total_orders}</td>
                                        <td className="px-6 py-4 whitespace-nowrap text-white">
                                            {user.role === 'customer' && user.total_spent !== undefined ? `₹${user.total_spent.toFixed(2)}` :
                                             user.role === 'shopkeeper' && user.total_earned !== undefined ? `₹${user.total_earned.toFixed(2)}` : '-'}
                                        </td>
                                        <td className="px-6 py-4 whitespace-nowrap">
                                            <button
                                                    onClick={() => handleDelete(user.id, user.full_name || user.email || `User #${user.id}`)}
                                                className="text-red-400 hover:text-red-300 font-medium"
                                            >
                                                Delete
                                            </button>
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>

                    {/* Pagination */}
                    {data && data.total_pages > 1 && (
                        <div className="px-6 py-4 flex justify-between items-center border-t border-white/10">
                            <div className="text-purple-200 text-sm">
                                Showing {((page - 1) * data.page_size) + 1} to {Math.min(page * data.page_size, data.total)} of {data.total} users
                            </div>
                            <div className="flex gap-2">
                                <button
                                    onClick={() => setPage(p => Math.max(1, p - 1))}
                                    disabled={page === 1}
                                    className="px-4 py-2 bg-white/10 hover:bg-white/20 text-white rounded-lg disabled:opacity-50 disabled:cursor-not-allowed"
                                >
                                    Previous
                                </button>
                                <button
                                    onClick={() => setPage(p => Math.min(data.total_pages, p + 1))}
                                    disabled={page === data.total_pages}
                                    className="px-4 py-2 bg-white/10 hover:bg-white/20 text-white rounded-lg disabled:opacity-50 disabled:cursor-not-allowed"
                                >
                                    Next
                                </button>
                            </div>
                        </div>
                    )}
                </div>
            </div>
        </div>
    );
}

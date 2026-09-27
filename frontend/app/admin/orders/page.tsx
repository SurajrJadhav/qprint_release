"use client";

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import api, { logout } from '@/lib/api';
import Link from 'next/link';

interface Order {
    id: number;
    user_id: number;
    customer_name: string;
    order_id: string;
    payment_id?: string;
    amount: number;
    status: string;
    shopkeeper_id?: number;
    shopkeeper_name?: string;
    platform_commission: number;
    shopkeeper_amount?: number;
    print_type: string;
    copies: number;
    print_mode: string;
    color_mode: string;
    paper_size: string;
    created_at: string;
    paid_at?: string;
}

interface OrderListResponse {
    orders: Order[];
    total: number;
    page: number;
    page_size: number;
    total_pages: number;
}

export default function AdminOrders() {
    const [data, setData] = useState<OrderListResponse | null>(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');
    const [page, setPage] = useState(1);
    const [statusFilter, setStatusFilter] = useState('');
    const router = useRouter();

    useEffect(() => {
        const token = localStorage.getItem('token') || sessionStorage.getItem('token');
        const role = localStorage.getItem('role');
        
        if ((!token && !role) || role !== 'admin') {
            router.push('/login');
            return;
        }

        fetchOrders();
    }, [page, statusFilter]);

    const fetchOrders = async () => {
        try {
            setLoading(true);
            const params = new URLSearchParams({
                page: page.toString(),
                page_size: '20',
            });
            if (statusFilter === 'pending_at_shop') {
                params.append('pending_at_shop', 'true');
            } else if (statusFilter) {
                params.append('status', statusFilter);
            }

            const res = await api.get(`/admin/orders?${params.toString()}`);
            setData(res.data);
            setLoading(false);
        } catch (err: any) {
            console.error('Failed to fetch orders:', err);
            setError('Failed to load orders');
            setLoading(false);
        }
    };

    const handleLogout = async () => {
        await logout();
        router.push('/login');
    };

    const getStatusColor = (status: string) => {
        switch (status) {
            case 'paid': return 'bg-green-500/20 text-green-300';
            case 'pending': return 'bg-yellow-500/20 text-yellow-300';
            case 'failed': return 'bg-red-500/20 text-red-300';
            case 'refunded': return 'bg-purple-500/20 text-purple-300';
            default: return 'bg-gray-500/20 text-gray-300';
        }
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
                            Order <span className="text-pink-400">Management</span>
                        </h1>
                        <p className="text-purple-200">View and manage all orders</p>
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
                    <div className="flex gap-4">
                        <div className="flex-1">
                            <label className="block text-purple-200 text-sm mb-2">Status</label>
                            <select
                                value={statusFilter}
                                onChange={(e) => { setStatusFilter(e.target.value); setPage(1); }}
                                className="w-full bg-white/20 border border-white/30 p-2 rounded-lg text-white"
                            >
                                <option value="">All</option>
                                <option value="pending_at_shop">Pending at shop</option>
                                <option value="pending">Pending (payment)</option>
                                <option value="paid">Paid</option>
                                <option value="failed">Failed</option>
                                <option value="refunded">Refunded</option>
                            </select>
                        </div>
                    </div>
                </div>

                {/* Orders Table */}
                <div className="bg-white/10 backdrop-blur-lg rounded-xl border border-white/20 overflow-hidden">
                    <div className="overflow-x-auto">
                        <table className="w-full">
                                    <thead className="bg-white/10">
                                        <tr>
                                            <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Order ID</th>
                                            <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Customer</th>
                                            <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Shop</th>
                                            <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Uploaded at</th>
                                            <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Amount</th>
                                            <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Status</th>
                                            <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Type</th>
                                        </tr>
                                    </thead>
                                    <tbody className="divide-y divide-white/10">
                                        {(data?.orders || []).map((order) => (
                                            <tr key={order.id} className="hover:bg-white/5">
                                                <td className="px-6 py-4 whitespace-nowrap text-white font-mono text-sm">{order.order_id}</td>
                                                <td className="px-6 py-4 whitespace-nowrap text-white">{order.customer_name}</td>
                                                <td className="px-6 py-4 whitespace-nowrap text-white">{order.shopkeeper_name || '-'}</td>
                                                <td className="px-6 py-4 whitespace-nowrap text-white text-sm" title={order.created_at}>
                                                    {new Date(order.created_at).toLocaleString(undefined, { dateStyle: 'short', timeStyle: 'short' })}
                                                </td>
                                                <td className="px-6 py-4 whitespace-nowrap text-white font-medium">₹{order.amount.toFixed(2)}</td>
                                                <td className="px-6 py-4 whitespace-nowrap">
                                                    <span className={`px-2 py-1 rounded text-xs font-medium ${getStatusColor(order.status)}`}>
                                                        {statusFilter === 'pending_at_shop' ? 'Pending at shop' : order.status}
                                                    </span>
                                                </td>
                                                <td className="px-6 py-4 whitespace-nowrap">
                                                    <span className="px-2 py-1 rounded text-xs font-medium bg-blue-500/20 text-blue-300">
                                                        {order.print_type}
                                                    </span>
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
                                Showing {((page - 1) * data.page_size) + 1} to {Math.min(page * data.page_size, data.total)} of {data.total} orders
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

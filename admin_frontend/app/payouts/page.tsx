"use client";

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import api from '@/lib/api';
import Link from 'next/link';

interface Payout {
    id: number;
    shopkeeper_id: number;
    shopkeeper_name: string;
    payment_order_id: number;
    order_id: string;
    amount: number;
    status: string;
    payout_method?: string;
    payout_reference?: string;
    created_at: string;
    paid_at?: string;
    failed_at?: string;
    failure_reason?: string;
}

interface PayoutSummary {
    total_pending_count: number;
    total_pending_amount: number;
    total_paid_count: number;
    total_paid_amount: number;
}

interface PayoutListResponse {
    payouts: Payout[];
    total: number;
    page: number;
    page_size: number;
    total_pages: number;
    summary?: PayoutSummary;
}

const PERIOD_OPTIONS = [
    { value: '', label: 'All time' },
    { value: 'this_week', label: 'This week' },
    { value: 'this_month', label: 'This month' },
    { value: 'last_week', label: 'Last week' },
    { value: 'last_month', label: 'Last month' },
];

export default function AdminPayouts() {
    const [data, setData] = useState<PayoutListResponse | null>(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');
    const [page, setPage] = useState(1);
    const [statusFilter, setStatusFilter] = useState('pending');
    const [period, setPeriod] = useState('');
    const [updating, setUpdating] = useState<number | null>(null);
    const [selectedIds, setSelectedIds] = useState<Set<number>>(new Set());
    const [bulkModalOpen, setBulkModalOpen] = useState(false);
    const [bulkMethod, setBulkMethod] = useState('');
    const [bulkReference, setBulkReference] = useState('');
    const [exporting, setExporting] = useState(false);
    const router = useRouter();

    useEffect(() => {
        const token = localStorage.getItem('token');
        const role = localStorage.getItem('role');

        if (!token || role !== 'admin') {
            router.push('/login');
            return;
        }

        fetchPayouts();
    }, [page, statusFilter, period]);

    const fetchPayouts = async () => {
        try {
            setLoading(true);
            const params = new URLSearchParams({
                page: page.toString(),
                page_size: '20',
            });
            if (statusFilter) params.append('status', statusFilter);
            if (period) params.append('period', period);

            const res = await api.get(`/admin/payouts?${params.toString()}`);
            setData(res.data);
            setError('');
        } catch (err: unknown) {
            console.error('Failed to fetch payouts:', err);
            setError('Failed to load payouts');
        } finally {
            setLoading(false);
        }
    };

    const handleUpdateStatus = async (payoutId: number, status: string) => {
        if (status === 'paid') {
            const method = prompt('Enter payout method (e.g., NEFT, UPI):');
            if (!method) return;
            const reference = prompt('Enter payout reference/transaction ID:');
            if (!reference) return;

            try {
                setUpdating(payoutId);
                await api.put('/admin/payouts/update', {
                    payout_id: payoutId,
                    status: 'paid',
                    payout_method: method,
                    payout_reference: reference,
                });
                alert('Payout updated successfully');
                fetchPayouts();
            } catch (err: unknown) {
                alert('Failed to update payout');
            } finally {
                setUpdating(null);
            }
        } else if (status === 'failed') {
            const reason = prompt('Reason for failure (optional):');
            try {
                setUpdating(payoutId);
                await api.put('/admin/payouts/update', {
                    payout_id: payoutId,
                    status: 'failed',
                    failure_reason: reason && (reason as string).trim() ? (reason as string).trim() : undefined,
                });
                alert('Payout marked as failed.');
                fetchPayouts();
            } catch (err: unknown) {
                alert('Failed to update payout');
            } finally {
                setUpdating(null);
            }
        }
    };

    const toggleSelect = (id: number) => {
        setSelectedIds((prev) => {
            const next = new Set(prev);
            if (next.has(id)) next.delete(id);
            else next.add(id);
            return next;
        });
    };

    const toggleSelectAll = () => {
        if (!data?.payouts?.length) return;
        const pendingOnPage = data.payouts.filter((p) => p.status === 'pending');
        if (selectedIds.size >= pendingOnPage.length) {
            setSelectedIds(new Set());
        } else {
            setSelectedIds(new Set(pendingOnPage.map((p) => p.id)));
        }
    };

    const handleBulkMarkPaid = async () => {
        if (selectedIds.size === 0 || !bulkMethod.trim() || !bulkReference.trim()) {
            alert('Please enter payout method and reference.');
            return;
        }
        try {
            await api.put('/admin/payouts/bulk-update', {
                payout_ids: Array.from(selectedIds),
                status: 'paid',
                payout_method: bulkMethod.trim(),
                payout_reference: bulkReference.trim(),
            });
            setBulkModalOpen(false);
            setBulkMethod('');
            setBulkReference('');
            setSelectedIds(new Set());
            alert(`Updated ${selectedIds.size} payout(s).`);
            fetchPayouts();
        } catch (err: unknown) {
            alert('Failed to update payouts');
        }
    };

    const handleExport = async () => {
        try {
            setExporting(true);
            const params = new URLSearchParams();
            if (statusFilter) params.append('status', statusFilter);
            if (period) params.append('period', period);
            const baseURL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8080';
            const url = `${baseURL}/admin/payouts/export?${params.toString()}`;
            const token = localStorage.getItem('token');
            const res = await fetch(url, {
                headers: { Authorization: `Bearer ${token}` },
                credentials: 'include',
            });
            if (!res.ok) throw new Error('Export failed');
            const blob = await res.blob();
            const a = document.createElement('a');
            a.href = URL.createObjectURL(blob);
            a.download = 'payouts.csv';
            a.click();
            URL.revokeObjectURL(a.href);
        } catch (err: unknown) {
            alert('Export failed');
        } finally {
            setExporting(false);
        }
    };

    const handleLogout = () => {
        localStorage.removeItem('token');
        localStorage.removeItem('role');
        localStorage.removeItem('display_name');
        localStorage.removeItem('username');
        router.push('/login');
    };

    const getStatusColor = (status: string) => {
        switch (status) {
            case 'paid': return 'bg-green-500/20 text-green-300';
            case 'pending': return 'bg-yellow-500/20 text-yellow-300';
            case 'failed': return 'bg-red-500/20 text-red-300';
            default: return 'bg-gray-500/20 text-gray-300';
        }
    };

    const pendingOnPage = data?.payouts?.filter((p) => p.status === 'pending') ?? [];
    const allPendingSelected = pendingOnPage.length > 0 && selectedIds.size === pendingOnPage.length;

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
                <div className="flex justify-between items-center mb-8">
                    <div>
                        <h1 className="text-4xl font-black text-white mb-2">
                            Payout <span className="text-pink-400">Management</span>
                        </h1>
                        <p className="text-purple-200">Manage shopkeeper payouts</p>
                    </div>
                    <div className="flex gap-4">
                        <Link href="/dashboard" className="bg-white/10 hover:bg-white/20 text-white px-4 py-2 rounded-lg border border-white/20">
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

                {data?.summary && (
                    <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
                        <div className="bg-yellow-500/20 border border-yellow-400/30 rounded-xl p-4">
                            <div className="text-yellow-200 text-sm">Pending (count)</div>
                            <div className="text-white text-2xl font-bold">{data.summary.total_pending_count}</div>
                        </div>
                        <div className="bg-yellow-500/20 border border-yellow-400/30 rounded-xl p-4">
                            <div className="text-yellow-200 text-sm">Pending (amount)</div>
                            <div className="text-white text-2xl font-bold">₹{data.summary.total_pending_amount.toFixed(2)}</div>
                        </div>
                        <div className="bg-green-500/20 border border-green-400/30 rounded-xl p-4">
                            <div className="text-green-200 text-sm">Paid (count)</div>
                            <div className="text-white text-2xl font-bold">{data.summary.total_paid_count}</div>
                        </div>
                        <div className="bg-green-500/20 border border-green-400/30 rounded-xl p-4">
                            <div className="text-green-200 text-sm">Paid (amount)</div>
                            <div className="text-white text-2xl font-bold">₹{data.summary.total_paid_amount.toFixed(2)}</div>
                        </div>
                    </div>
                )}

                <div className="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20 mb-6">
                    <div className="flex flex-wrap gap-4 items-end">
                        <div>
                            <label className="admin-label mb-2">Status</label>
                            <select
                                value={statusFilter}
                                onChange={(e) => { setStatusFilter(e.target.value); setPage(1); }}
                                className="admin-select min-w-[140px]"
                            >
                                <option value="">All</option>
                                <option value="pending">Pending</option>
                                <option value="paid">Paid</option>
                                <option value="failed">Failed</option>
                            </select>
                        </div>
                        <div>
                            <label className="admin-label mb-2">Period</label>
                            <select
                                value={period}
                                onChange={(e) => { setPeriod(e.target.value); setPage(1); }}
                                className="admin-select min-w-[180px]"
                            >
                                {PERIOD_OPTIONS.map((o) => (
                                    <option key={o.value || 'all'} value={o.value}>{o.label}</option>
                                ))}
                            </select>
                        </div>
                        <div className="flex gap-2">
                            {statusFilter === 'pending' && data?.payouts?.some((p) => p.status === 'pending') && (
                                <>
                                    <button
                                        onClick={toggleSelectAll}
                                        className="px-4 py-2 bg-white/10 hover:bg-white/20 text-white rounded-lg border border-white/20"
                                    >
                                        {allPendingSelected ? 'Deselect all' : 'Select all on page'}
                                    </button>
                                    <button
                                        onClick={() => setBulkModalOpen(true)}
                                        disabled={selectedIds.size === 0}
                                        className="px-4 py-2 bg-green-500/30 hover:bg-green-500/40 text-white rounded-lg border border-green-400/50 disabled:opacity-50 disabled:cursor-not-allowed"
                                    >
                                        Mark selected as paid ({selectedIds.size})
                                    </button>
                                </>
                            )}
                            <button
                                onClick={handleExport}
                                disabled={exporting || (data?.total === 0)}
                                className="px-4 py-2 bg-white/10 hover:bg-white/20 text-white rounded-lg border border-white/20 disabled:opacity-50"
                            >
                                {exporting ? 'Exporting...' : 'Export for bank'}
                            </button>
                        </div>
                    </div>
                </div>

                {bulkModalOpen && (
                    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 p-4">
                        <div className="bg-gray-800 rounded-xl border border-white/20 p-6 max-w-md w-full">
                            <h3 className="text-lg font-bold text-white mb-4">Mark selected as paid</h3>
                            <div className="space-y-4">
                                <div>
                                    <label className="admin-label mb-1">Payout method (e.g. NEFT)</label>
                                    <input
                                        value={bulkMethod}
                                        onChange={(e) => setBulkMethod(e.target.value)}
                                        className="w-full bg-white/10 border border-white/30 p-2 rounded text-white"
                                        placeholder="NEFT"
                                    />
                                </div>
                                <div>
                                    <label className="admin-label mb-1">Payout reference (e.g. UTR)</label>
                                    <input
                                        value={bulkReference}
                                        onChange={(e) => setBulkReference(e.target.value)}
                                        className="w-full bg-white/10 border border-white/30 p-2 rounded text-white"
                                        placeholder="BATCH-2026-W05"
                                    />
                                </div>
                            </div>
                            <div className="flex gap-2 mt-6">
                                <button
                                    onClick={handleBulkMarkPaid}
                                    className="flex-1 px-4 py-2 bg-green-500/30 text-white rounded-lg border border-green-400/50"
                                >
                                    Confirm
                                </button>
                                <button
                                    onClick={() => { setBulkModalOpen(false); setBulkMethod(''); setBulkReference(''); }}
                                    className="px-4 py-2 bg-white/10 text-white rounded-lg border border-white/20"
                                >
                                    Cancel
                                </button>
                            </div>
                        </div>
                    </div>
                )}

                <div className="bg-white/10 backdrop-blur-lg rounded-xl border border-white/20 overflow-hidden">
                    {error && (
                        <div className="p-4 bg-red-500/20 border-b border-red-400/30 text-red-300">{error}</div>
                    )}
                    {data?.payouts?.length === 0 ? (
                        <div className="p-12 text-center">
                            <div className="text-6xl mb-4">💰</div>
                            <h3 className="text-xl font-bold text-white mb-2">No Payouts Found</h3>
                            <p className="text-purple-200">No payouts match the current filters.</p>
                        </div>
                    ) : (
                        <>
                            <div className="overflow-x-auto">
                                <table className="w-full">
                                    <thead className="bg-white/10">
                                        <tr>
                                            {statusFilter === 'pending' && <th className="px-4 py-3 text-left"><input type="checkbox" checked={allPendingSelected} onChange={toggleSelectAll} className="rounded" /></th>}
                                            <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">ID</th>
                                            <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Shopkeeper</th>
                                            <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Order ID</th>
                                            <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Amount</th>
                                            <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Status</th>
                                            <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Method</th>
                                            <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Reference</th>
                                            <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Created at</th>
                                            <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Paid at</th>
                                            <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Actions</th>
                                        </tr>
                                    </thead>
                                    <tbody className="divide-y divide-white/10">
                                        {(data?.payouts ?? []).map((payout) => (
                                            <tr key={payout.id} className="hover:bg-white/5">
                                                {statusFilter === 'pending' && (
                                                    <td className="px-4 py-4">
                                                        {payout.status === 'pending' && (
                                                            <input
                                                                type="checkbox"
                                                                checked={selectedIds.has(payout.id)}
                                                                onChange={() => toggleSelect(payout.id)}
                                                                className="rounded"
                                                            />
                                                        )}
                                                    </td>
                                                )}
                                                <td className="px-6 py-4 whitespace-nowrap text-white">{payout.id}</td>
                                                <td className="px-6 py-4 whitespace-nowrap text-white">{payout.shopkeeper_name}</td>
                                                <td className="px-6 py-4 whitespace-nowrap text-white font-mono text-sm">{payout.order_id}</td>
                                                <td className="px-6 py-4 whitespace-nowrap text-white font-medium">₹{payout.amount.toFixed(2)}</td>
                                                <td className="px-6 py-4 whitespace-nowrap">
                                                    <span className={`px-2 py-1 rounded text-xs font-medium ${getStatusColor(payout.status)}`}>
                                                        {payout.status}
                                                    </span>
                                                </td>
                                                <td className="px-6 py-4 whitespace-nowrap text-white">{payout.payout_method || '-'}</td>
                                                <td className="px-6 py-4 whitespace-nowrap text-white font-mono text-xs">{payout.payout_reference || '-'}</td>
                                                <td className="px-6 py-4 whitespace-nowrap text-white text-sm">{new Date(payout.created_at).toLocaleDateString()}</td>
                                                <td className="px-6 py-4 whitespace-nowrap text-white text-sm">{payout.paid_at ? new Date(payout.paid_at).toLocaleDateString() : '-'}</td>
                                                <td className="px-6 py-4 whitespace-nowrap">
                                                    {(payout.status === 'pending' || payout.status === 'failed') && (
                                                        <div className="flex gap-2 flex-wrap">
                                                            <button
                                                                onClick={() => handleUpdateStatus(payout.id, 'paid')}
                                                                disabled={updating === payout.id}
                                                                className="text-green-400 hover:text-green-300 font-medium disabled:opacity-50"
                                                            >
                                                                {updating === payout.id ? 'Updating...' : 'Mark Paid'}
                                                            </button>
                                                            {payout.status === 'pending' && (
                                                                <button
                                                                    onClick={() => handleUpdateStatus(payout.id, 'failed')}
                                                                    disabled={updating === payout.id}
                                                                    className="text-red-400 hover:text-red-300 font-medium disabled:opacity-50"
                                                                >
                                                                    Mark Failed
                                                                </button>
                                                            )}
                                                        </div>
                                                    )}
                                                </td>
                                            </tr>
                                        ))}
                                    </tbody>
                                </table>
                            </div>
                            {data && data.total_pages > 1 && (
                                <div className="px-6 py-4 flex justify-between items-center border-t border-white/10">
                                    <div className="text-purple-200 text-sm">
                                        Showing {((page - 1) * data.page_size) + 1} to {Math.min(page * data.page_size, data.total)} of {data.total}
                                    </div>
                                    <div className="flex gap-2">
                                        <button
                                            onClick={() => setPage((p) => Math.max(1, p - 1))}
                                            disabled={page === 1}
                                            className="px-4 py-2 bg-white/10 hover:bg-white/20 text-white rounded-lg disabled:opacity-50"
                                        >
                                            Previous
                                        </button>
                                        <button
                                            onClick={() => setPage((p) => Math.min(data.total_pages, p + 1))}
                                            disabled={page === data.total_pages}
                                            className="px-4 py-2 bg-white/10 hover:bg-white/20 text-white rounded-lg disabled:opacity-50"
                                        >
                                            Next
                                        </button>
                                    </div>
                                </div>
                            )}
                        </>
                    )}
                </div>
            </div>
        </div>
    );
}

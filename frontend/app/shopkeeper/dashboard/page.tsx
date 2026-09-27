"use client";

import { useState, useEffect } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import api, { logout, deleteAccount, cancelQueueOrder } from '@/lib/api';
import { getSafeErrorMessage } from '@/lib/safeError';
import Footer from '@/components/Footer';
import DashboardHeader from '@/components/DashboardHeader';

export default function ShopkeeperPage() {
    const [code, setCode] = useState('');
    const [downloading, setDownloading] = useState(false);
    const [message, setMessage] = useState('');
    const [messageType, setMessageType] = useState<'success' | 'error' | ''>('');
    const [queue, setQueue] = useState<any[]>([]);
    const [displayName, setDisplayName] = useState('');

    const [view, setView] = useState<'dashboard' | 'history' | 'stats' | 'profile' | 'payouts'>('dashboard');
    const [history, setHistory] = useState<any[]>([]);
    const [payouts, setPayouts] = useState<any[]>([]);
    const [payoutsLoading, setPayoutsLoading] = useState(false);
    const [payoutsError, setPayoutsError] = useState('');
    const [profile, setProfile] = useState<{
        address: string; password: string; current_password: string;
        full_name?: string; email?: string; phone?: string; shop_name?: string;
        created_at?: string; role?: string; is_open?: boolean;
    }>({ address: '', password: '', current_password: '', shop_name: '' });
    const [profileError, setProfileError] = useState('');
    const [isOpen, setIsOpen] = useState(true);
    const [showProfileMenu, setShowProfileMenu] = useState(false);

    // New state for manual confirmation
    const [showConfirmModal, setShowConfirmModal] = useState(false);
    const [pendingPrint, setPendingPrint] = useState<{ code: string, isQueue: boolean, fileId?: number } | null>(null);
    
    // Delete account modal state
    const [showDeleteAccountModal, setShowDeleteAccountModal] = useState(false);
    const [deletePassword, setDeletePassword] = useState('');
    const [deletingAccount, setDeletingAccount] = useState(false);
    const [deleteError, setDeleteError] = useState('');

    // Cancel order modal (shopkeeper cancels queue order with reason)
    const [showCancelOrderModal, setShowCancelOrderModal] = useState(false);
    const [cancelOrderJob, setCancelOrderJob] = useState<any>(null);
    const [cancelReason, setCancelReason] = useState('');
    const [cancelError, setCancelError] = useState('');
    const [cancellingOrder, setCancellingOrder] = useState(false);

    const router = useRouter();
    const pathname = usePathname();
    
    // Check for view parameter in URL - listen to route changes
    useEffect(() => {
        const checkURL = () => {
            if (typeof window !== 'undefined') {
                const params = new URLSearchParams(window.location.search);
                const viewParam = params.get('view');
                if (viewParam && ['dashboard', 'history', 'stats', 'profile', 'payouts'].includes(viewParam)) {
                    const newView = viewParam as 'dashboard' | 'history' | 'stats' | 'profile' | 'payouts';
                    setView(newView);
                    if (newView === 'history' || newView === 'stats') {
                        fetchHistory();
                    }
                    if (newView === 'profile') {
                        fetchProfile();
                    }
                    if (newView === 'payouts') {
                        fetchPayouts();
                    }
                } else {
                    setView('dashboard');
                }
            }
        };
        
        // Check immediately
        checkURL();
        
        // Check periodically to catch URL changes from router.push (every 100ms)
        const interval = setInterval(checkURL, 100);
        
        // Also listen for popstate (browser back/forward)
        window.addEventListener('popstate', checkURL);
        
        return () => {
            clearInterval(interval);
            window.removeEventListener('popstate', checkURL);
        };
    }, [pathname]);

    useEffect(() => {
        const token = localStorage.getItem('token') || sessionStorage.getItem('token');
        const role = localStorage.getItem('role');
        if (!token && !role) {
            router.push('/login');
            return;
        }
        const storedName = (localStorage.getItem('display_name') || localStorage.getItem('username') || '').trim();
        const safeName = storedName && storedName.toLowerCase() !== 'undefined' && storedName.toLowerCase() !== 'null'
            ? storedName
            : 'Shopkeeper';
        setDisplayName(safeName);
        fetchQueue();
        // Refresh queue every 5 seconds
        const interval = setInterval(fetchQueue, 5000);
        return () => clearInterval(interval);
    }, []);

    const fetchQueue = async () => {
        try {
            const res = await api.get('/queue');
            setQueue(res.data.queue || []);
        } catch (err) {
            console.error('Error fetching queue:', err);
        }
    };


    const fetchHistory = async () => {
        try {
            const res = await api.get('/shop/history');
            setHistory(res.data.history || []);
        } catch (err) {
            console.error('Error fetching history:', err);
        }
    };

    const fetchPayouts = async () => {
        setPayoutsLoading(true);
        setPayoutsError('');
        try {
            const res = await api.get('/shopkeeper/payouts');
            setPayouts(res.data?.payouts ?? []);
        } catch (err) {
            console.error('Error fetching payouts:', err);
            setPayoutsError('Failed to load payouts');
            setPayouts([]);
        } finally {
            setPayoutsLoading(false);
        }
    };

    const fetchProfile = async () => {
        try {
            const res = await api.get('/profile');
            const d = res.data;
            setProfile({
                ...d,
                shop_name: d.shop_name ?? d.display_name ?? '',
                full_name: d.full_name ?? '',
                email: d.email ?? '',
                phone: d.phone ?? '',
                password: '',
                current_password: '',
            });
            setIsOpen(d.is_open ?? true);
            setProfileError('');
        } catch (err) {
            console.error('Error fetching profile:', err);
        }
    };

    const toggleShopStatus = async () => {
        try {
            const newState = !isOpen;
            await api.post('/shop/status', { is_open: newState });
            setIsOpen(newState);
            setMessage(newState ? '✅ Shop is now OPEN' : '🔴 Shop is now CLOSED');
            setMessageType(newState ? 'success' : 'error');
        } catch (err) {
            console.error('Error updating shop status:', err);
            setMessage('❌ Failed to update shop status');
            setMessageType('error');
        }
    };

    const handleUpdateProfile = async (e: React.FormEvent) => {
        e.preventDefault();
        setMessage('');
        setMessageType('');
        setProfileError('');
        const payload: Record<string, string> = {
            address: profile.address,
            full_name: profile.full_name ?? '',
            email: profile.email ?? '',
            phone: profile.phone ?? '',
            shop_name: profile.shop_name ?? '',
        };
        if (profile.password) {
            payload.password = profile.password;
            payload.current_password = profile.current_password;
        }
        try {
            await api.put('/profile', payload);
            setMessage('✅ Profile updated successfully!');
            setMessageType('success');
            const rawName = (profile.shop_name || profile.full_name || '').trim();
            const name = rawName && rawName.toLowerCase() !== 'undefined' && rawName.toLowerCase() !== 'null'
                ? rawName
                : 'Shopkeeper';
            setDisplayName(name);
            localStorage.setItem('display_name', name);
            localStorage.removeItem('username');
            setProfile(prev => ({ ...prev, password: '', current_password: '' }));
        } catch (err: any) {
            console.error('Error updating profile:', err);
            const msg = getSafeErrorMessage(err);
            setProfileError(msg || 'Failed to update profile.');
            setMessageType('error');
        }
    };

    const handlePrint = async (code: string, isQueue = false, fileId?: number, orderGroupId?: number | string, isBatchOrder?: boolean) => {
        if (!code && !isQueue) return;

        setDownloading(true);
        setMessage('');
        setMessageType('');

        try {
            let res;
            let actualFileId = fileId;
            
            if (isQueue) {
                console.log('Queue print - Debug info:', { fileId, orderGroupId, isBatchOrder });
                
                // For batch orders, get files first, then download the first file
                if (isBatchOrder && orderGroupId) {
                    console.log('Batch order detected, fetching files for order group:', orderGroupId);
                    try {
                        // Get all files for this order group
                        const filesRes = await api.get(`/queue/${orderGroupId}/files`);
                        const files = filesRes.data.files || [];
                        console.log('Files fetched:', files);
                        
                        if (files.length === 0) {
                            throw new Error('No files found for this order');
                        }
                        
                        // Use the first file's ID for download
                        actualFileId = files[0].id;
                        console.log('Using file ID from batch:', actualFileId);
                    } catch (fetchErr: any) {
                        console.error('Error fetching batch files:', fetchErr);
                        throw new Error(`Failed to fetch files: ${fetchErr.message || 'Unknown error'}`);
                    }
                } else if (!fileId && orderGroupId) {
                    // If no fileId but we have orderGroupId, try using it as fileId
                    // (for single file orders, order_group_id = file_id)
                    console.log('Single file order, using orderGroupId as fileId:', orderGroupId);
                    if (typeof orderGroupId === 'number') {
                        actualFileId = orderGroupId;
                    } else {
                        const parsed = parseInt(String(orderGroupId), 10);
                        if (!isNaN(parsed)) {
                            actualFileId = parsed;
                        }
                    }
                } else if (fileId) {
                    // Use provided fileId directly
                    actualFileId = fileId;
                    console.log('Using provided fileId:', actualFileId);
                }
                
                if (!actualFileId || isNaN(actualFileId)) {
                    throw new Error(`File ID or order group ID required for queue print. Got: fileId=${fileId}, orderGroupId=${orderGroupId}`);
                }
                
                console.log('Downloading file with ID:', actualFileId);
                res = await api.get(`/queue/download/${actualFileId}`, { responseType: 'blob' });
            } else {
                // Private print - unchanged, backward compatible
                res = await api.get(`/file/${code}`, { responseType: 'blob' });
            }

            // Detect file type from response or default to PDF
            // For PNG files, we'll use image/png, otherwise application/pdf
            const contentType = res.headers['content-type'] || 'application/pdf';
            const blobType = contentType.includes('image') ? contentType : 'application/pdf';
            const url = window.URL.createObjectURL(new Blob([res.data], { type: blobType }));

            // Create iframe (using opacity instead of off-screen to ensure render)
            const iframe = document.createElement('iframe');
            iframe.style.position = 'fixed';
            iframe.style.bottom = '0';
            iframe.style.right = '0';
            iframe.style.width = '100px';
            iframe.style.height = '100px';
            iframe.style.opacity = '0';
            iframe.style.pointerEvents = 'none';
            iframe.style.border = 'none';
            document.body.appendChild(iframe);

            console.log("Iframe attached to DOM, setting src...");

            iframe.onload = () => {
                console.log("Iframe loaded PDF");
                console.log("Focusing and printing...");
                try {
                    if (iframe.contentWindow) {
                        iframe.contentWindow.focus();
                        iframe.contentWindow.print();
                        // Show manual confirmation modal immediately
                        setPendingPrint({ code, isQueue, fileId: actualFileId });
                        setShowConfirmModal(true);
                    }
                } catch (e) {
                    console.error("Print call failed:", e);
                    setMessage('❌ Print failed to start.');
                    setMessageType('error');
                }
            };

            iframe.src = url;

        } catch (err: unknown) {
            console.error('Print error:', err);
            const status = (err as { response?: { status?: number } })?.response?.status;
            if (status === 410) {
                setMessage('⚠️ File already processed/deleted.');
            } else if (status === 404) {
                setMessage('❌ File not found.');
            } else {
                setMessage('❌ ' + getSafeErrorMessage(err, 'generic'));
            }
            setMessageType('error');
        } finally {
            setDownloading(false);
        }
    };

    const handleConfirmPrint = async () => {
        if (!pendingPrint) return;

        try {
            if (pendingPrint.isQueue && pendingPrint.fileId) {
                await api.post(`/queue/${pendingPrint.fileId}/confirm`);
                fetchQueue();
                setMessage('✅ Print confirmed! File deleted from server.');
            } else {
                await api.post(`/file/${pendingPrint.code}/confirm`);
                setMessage('✅ Print confirmed! File deleted from server.');
                setCode('');
            }
            setMessageType('success');
        } catch (err) {
            console.error('Confirm print error:', err);
            setMessage('❌ Failed to confirm print.');
            setMessageType('error');
        } finally {
            setShowConfirmModal(false);
            setPendingPrint(null);
        }
    };

    const handleCancelPrint = () => {
        setMessage('⚠️ Print cancelled. File is still available.');
        setMessageType('');
        setShowConfirmModal(false);
        setPendingPrint(null);
    };

    const openCancelOrderModal = (job: any) => {
        setCancelOrderJob(job);
        setCancelReason('');
        setCancelError('');
        setShowCancelOrderModal(true);
    };

    const closeCancelOrderModal = () => {
        setShowCancelOrderModal(false);
        setCancelOrderJob(null);
        setCancelReason('');
        setCancelError('');
    };

    const handleConfirmCancelOrder = async () => {
        const reason = cancelReason.trim();
        if (!reason || !cancelOrderJob) return;
        const fileId = cancelOrderJob.first_file_id ?? cancelOrderJob.id;
        if (!fileId) {
            setCancelError('Cannot cancel: missing order id.');
            return;
        }
        setCancellingOrder(true);
        setCancelError('');
        try {
            await cancelQueueOrder(Number(fileId), reason);
            setMessage('✅ Order cancelled. Customer will be notified and refunded.');
            setMessageType('success');
            closeCancelOrderModal();
            fetchQueue();
        } catch (err: any) {
            const msg = err.response?.data?.error || err.response?.data?.message || getSafeErrorMessage(err, 'generic');
            setCancelError(typeof msg === 'string' ? msg : 'Failed to cancel order.');
        } finally {
            setCancellingOrder(false);
        }
    };

    const handlePrivatePrintSubmit = (e: React.FormEvent) => {
        e.preventDefault();
        handlePrint(code);
    };

    const handleLogout = async () => {
        await logout();
        router.push('/');
    };

    const handleDeleteAccount = async () => {
        if (!deletePassword.trim()) {
            setDeleteError('Password is required');
            return;
        }
        
        setDeletingAccount(true);
        setDeleteError('');
        
        try {
            await deleteAccount(deletePassword);
            setShowDeleteAccountModal(false);
            router.push('/');
        } catch (err: any) {
            const message = err.response?.data || err.message || 'Failed to delete account';
            if (message.includes('Invalid password')) {
                setDeleteError('Invalid password');
            } else {
                setDeleteError(message);
            }
        } finally {
            setDeletingAccount(false);
        }
    };

    return (
        <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800">
            <DashboardHeader 
                displayName={displayName}
                role="shopkeeper"
                onLogout={handleLogout}
                onDeleteAccount={() => setShowDeleteAccountModal(true)}
                shopStatus={isOpen}
                onToggleShopStatus={toggleShopStatus}
            />
            
            <div className="p-6 pt-8">
                <div className="max-w-7xl mx-auto space-y-6">
                {/* Global Message */}
                {message && (
                    <div className={`p-4 rounded-lg ${messageType === 'success'
                        ? 'bg-green-500/20 border border-green-400/30 text-green-100'
                        : 'bg-red-500/20 border border-red-400/30 text-red-100'
                        }`}>
                        <p className="font-semibold">{message}</p>
                    </div>
                )}

                {view === 'stats' && (
                    <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-8 border border-white/20">
                        <div className="flex items-center gap-3 mb-8">
                            <div className="text-4xl">📊</div>
                            <div>
                                <h2 className="text-2xl font-bold text-white">Earnings & Stats</h2>
                                <p className="text-purple-200 text-sm">Overview of your shop's performance</p>
                            </div>
                            <button
                                onClick={() => setView('dashboard')}
                                className="ml-auto px-4 py-2 bg-white/10 text-white rounded-lg hover:bg-white/20 transition-all"
                            >
                                ← Back to Dashboard
                            </button>
                        </div>

                        {/* Stats Cards */}
                        <div className="grid md:grid-cols-3 gap-6 mb-8">
                            {/* Total Earnings */}
                            <div className="bg-gradient-to-br from-green-500/20 to-emerald-600/20 border border-green-500/30 rounded-xl p-6">
                                <p className="text-green-200 text-sm mb-1">Total Earnings</p>
                                <h3 className="text-4xl font-bold text-white">
                                    ₹{history.reduce((sum, item) => sum + item.cost, 0).toFixed(2)}
                                </h3>
                                <p className="text-white/60 text-xs mt-2">All time revenue</p>
                            </div>

                            {/* Today's Earnings */}
                            <div className="bg-gradient-to-br from-blue-500/20 to-cyan-600/20 border border-blue-500/30 rounded-xl p-6">
                                <p className="text-blue-200 text-sm mb-1">Today's Earnings</p>
                                <h3 className="text-4xl font-bold text-white">
                                    ₹{history
                                        .filter(item => new Date(item.date).toDateString() === new Date().toDateString())
                                        .reduce((sum, item) => sum + item.cost, 0)
                                        .toFixed(2)}
                                </h3>
                                <p className="text-white/60 text-xs mt-2">Revenue generated today</p>
                            </div>

                            {/* Total Prints */}
                            <div className="bg-gradient-to-br from-pink-500/20 to-purple-600/20 border border-pink-500/30 rounded-xl p-6">
                                <p className="text-pink-200 text-sm mb-1">Total Prints Solved</p>
                                <h3 className="text-4xl font-bold text-white">{history.length}</h3>
                                <p className="text-white/60 text-xs mt-2">Total files processed</p>
                            </div>
                        </div>

                        {/* Recent Activity Mini-Table */}
                        <div>
                            <h3 className="text-xl font-bold text-white mb-4">Recent Activity (Last 5)</h3>
                            <div className="overflow-x-auto">
                                <table className="w-full">
                                    <thead>
                                        <tr className="border-b border-white/20 bg-white/5">
                                            <th className="text-left text-purple-200 font-semibold p-3 rounded-tl-lg">Date</th>
                                            <th className="text-left text-purple-200 font-semibold p-3">Customer / File</th>
                                            <th className="text-left text-purple-200 font-semibold p-3">Type</th>
                                            <th className="text-left text-purple-200 font-semibold p-3 rounded-tr-lg">Amount</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {history.slice(0, 5).map((item) => (
                                            <tr key={item.id} className="border-b border-white/10 hover:bg-white/5">
                                                <td className="p-3 text-white text-sm whitespace-nowrap">
                                                    {new Date(item.date).toLocaleDateString(undefined, { month: 'short', day: '2-digit' })} {new Date(item.date).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                                                </td>
                                                <td className="p-3 text-white text-sm">
                                                    <span className="font-medium">{item.customer_name ?? '—'}</span>
                                                    <span className="text-white/70 block truncate max-w-[140px]" title={item.filename || item.code}>{item.filename || item.code}</span>
                                                </td>
                                                <td className="p-3">
                                                    <span className={`px-2 py-1 rounded text-xs font-bold ${item.type === 'queue' ? 'bg-blue-500/20 text-blue-300' : 'bg-pink-500/20 text-pink-300'}`}>
                                                        {item.type === 'queue' ? 'Queue' : 'Private'}
                                                    </span>
                                                </td>
                                                <td className="p-3 text-green-300 font-bold text-sm">₹{Number(item.cost).toFixed(2)}</td>
                                            </tr>
                                        ))}
                                    </tbody>
                                </table>
                            </div>
                        </div>
                    </div>
                )}

                <div className="grid lg:grid-cols-2 gap-6">
                    {view === 'payouts' ? (
                        <div className="col-span-2 bg-white/10 backdrop-blur-lg rounded-2xl p-8 border border-white/20">
                            <div className="flex items-center gap-3 mb-6">
                                <div className="text-4xl">💰</div>
                                <div>
                                    <h2 className="text-2xl font-bold text-white">Payouts / Settlements</h2>
                                    <p className="text-purple-200 text-sm">Amounts settled to your account</p>
                                </div>
                                <button
                                    onClick={() => setView('dashboard')}
                                    className="ml-auto px-4 py-2 bg-white/10 text-white rounded-lg hover:bg-white/20 transition-all"
                                >
                                    ← Back to Dashboard
                                </button>
                            </div>
                            {payoutsError && (
                                <div className="mb-4 p-4 bg-red-500/20 border border-red-400/30 rounded-lg text-red-200 text-sm">{payoutsError}</div>
                            )}
                            {payoutsLoading ? (
                                <div className="py-12 text-center text-purple-200">Loading payouts...</div>
                            ) : (
                                <>
                                    <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
                                        <div className="bg-yellow-500/20 border border-yellow-400/30 rounded-xl p-4">
                                            <p className="text-yellow-200 text-sm">Pending</p>
                                            <p className="text-white text-xl font-bold">
                                                ₹{payouts.filter((p: any) => p.status === 'pending').reduce((s: number, p: any) => s + (Number(p.amount) || 0), 0).toFixed(2)}
                                            </p>
                                            <p className="text-white/60 text-xs">{payouts.filter((p: any) => p.status === 'pending').length} payout(s)</p>
                                        </div>
                                        <div className="bg-green-500/20 border border-green-400/30 rounded-xl p-4">
                                            <p className="text-green-200 text-sm">Settled</p>
                                            <p className="text-white text-xl font-bold">
                                                ₹{payouts.filter((p: any) => p.status === 'paid').reduce((s: number, p: any) => s + (Number(p.amount) || 0), 0).toFixed(2)}
                                            </p>
                                            <p className="text-white/60 text-xs">{payouts.filter((p: any) => p.status === 'paid').length} payout(s)</p>
                                        </div>
                                    </div>
                                    <div className="overflow-x-auto">
                                        <table className="w-full">
                                            <thead>
                                                <tr className="border-b border-white/20">
                                                    <th className="text-left text-purple-200 font-semibold p-3">Order ID</th>
                                                    <th className="text-left text-purple-200 font-semibold p-3">Your amount</th>
                                                    <th className="text-left text-purple-200 font-semibold p-3">Status</th>
                                                    <th className="text-left text-purple-200 font-semibold p-3">Date</th>
                                                    <th className="text-left text-purple-200 font-semibold p-3">Method / Reference</th>
                                                </tr>
                                            </thead>
                                            <tbody>
                                                {payouts.length === 0 ? (
                                                    <tr>
                                                        <td colSpan={5} className="text-center py-8 text-purple-300">
                                                            No payouts yet. Completed queue prints will appear here.
                                                        </td>
                                                    </tr>
                                                ) : (
                                                    payouts.map((p: any) => (
                                                        <tr key={p.id} className="border-b border-white/10 hover:bg-white/5">
                                                            <td className="p-3 text-white font-mono text-sm">{p.order_id || '-'}</td>
                                                            <td className="p-3 text-white font-bold">₹{Number(p.amount || 0).toFixed(2)}</td>
                                                            <td className="p-3">
                                                                <span className={`px-2 py-1 rounded text-xs font-semibold ${
                                                                    p.status === 'paid' ? 'bg-green-500/20 text-green-300' : p.status === 'failed' ? 'bg-red-500/20 text-red-300' : 'bg-yellow-500/20 text-yellow-300'
                                                                }`}>
                                                                    {p.status === 'paid' ? 'Settled' : p.status === 'failed' ? 'Failed' : 'Pending'}
                                                                </span>
                                                            </td>
                                                            <td className="p-3 text-white text-sm">
                                                                {p.status === 'paid' && p.paid_at
                                                                    ? new Date(p.paid_at).toLocaleDateString(undefined, { day: '2-digit', month: 'short', year: 'numeric' })
                                                                    : p.created_at
                                                                        ? new Date(p.created_at).toLocaleDateString(undefined, { day: '2-digit', month: 'short', year: 'numeric' })
                                                                        : '-'}
                                                            </td>
                                                            <td className="p-3 text-white/80 text-sm">
                                                                {[p.payout_method, p.payout_reference].filter(Boolean).join(' · ') || '-'}
                                                            </td>
                                                        </tr>
                                                    ))
                                                )}
                                            </tbody>
                                        </table>
                                    </div>
                                </>
                            )}
                        </div>
                    ) : view === 'history' ? (
                        <div className="col-span-2 bg-white/10 backdrop-blur-lg rounded-2xl p-8 border border-white/20">
                            <div className="flex items-center gap-3 mb-6">
                                <div className="text-4xl">📜</div>
                                <div>
                                    <h2 className="text-2xl font-bold text-white">Print History</h2>
                                    <p className="text-purple-200 text-sm">Log of all completed prints</p>
                                </div>
                                <button
                                    onClick={() => setView('dashboard')}
                                    className="ml-auto px-4 py-2 bg-white/10 text-white rounded-lg hover:bg-white/20 transition-all"
                                >
                                    ← Back to Dashboard
                                </button>
                            </div>

                            <div className="overflow-x-auto">
                                <table className="w-full">
                                    <thead>
                                        <tr className="border-b border-white/20">
                                            <th className="text-left text-purple-200 font-semibold p-3">Date & time</th>
                                            <th className="text-left text-purple-200 font-semibold p-3">Customer</th>
                                            <th className="text-left text-purple-200 font-semibold p-3">File / Code</th>
                                            <th className="text-left text-purple-200 font-semibold p-3">Type</th>
                                            <th className="text-left text-purple-200 font-semibold p-3">Details</th>
                                            <th className="text-left text-purple-200 font-semibold p-3">Cost</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {history.length === 0 ? (
                                            <tr>
                                                <td colSpan={6} className="text-center py-8 text-purple-300">
                                                    No history found. Print some files first!
                                                </td>
                                            </tr>
                                        ) : (
                                            history.map((item) => (
                                                <tr key={item.id} className="border-b border-white/10 hover:bg-white/5">
                                                    <td className="p-3 text-white whitespace-nowrap">
                                                        {new Date(item.date).toLocaleDateString(undefined, { day: '2-digit', month: 'short', year: 'numeric' })}
                                                        <span className="text-white/70 block text-sm">{new Date(item.date).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</span>
                                                    </td>
                                                    <td className="p-3 text-white font-medium">{item.customer_name ?? '—'}</td>
                                                    <td className="p-3">
                                                        <span className="text-white block truncate max-w-[180px]" title={item.filename || item.code}>{item.filename || item.code}</span>
                                                        <span className="text-white/60 text-xs font-mono">{item.code}</span>
                                                    </td>
                                                    <td className="p-3">
                                                        <span className={`px-2 py-1 rounded text-xs font-bold ${item.type === 'queue' ? 'bg-blue-500/20 text-blue-300' : 'bg-pink-500/20 text-pink-300'}`}>
                                                            {item.type === 'queue' ? 'Queue' : 'Private'}
                                                        </span>
                                                    </td>
                                                    <td className="p-3 text-white text-sm">
                                                        {item.pages} pg · {item.copies} {item.copies === 1 ? 'copy' : 'copies'}
                                                        {item.paper_size && <span className="text-white/70"> · {item.paper_size}</span>}
                                                        {item.color_mode && item.color_mode !== 'bw' && <span className="text-white/70"> · {item.color_mode}</span>}
                                                    </td>
                                                    <td className="p-3 text-green-300 font-bold">₹{Number(item.cost).toFixed(2)}</td>
                                                </tr>
                                            ))
                                        )}
                                    </tbody>
                                </table>
                            </div>
                        </div>
                    ) : view === 'profile' ? (
                        <div className="col-span-2 space-y-6">
                            {/* Profile header */}
                            <div className="flex items-center gap-3">
                                <div className="text-4xl">👤</div>
                                <div>
                                    <h2 className="text-2xl font-bold text-white">Profile</h2>
                                    <p className="text-purple-200 text-sm">View and update your shop details</p>
                                </div>
                                <button
                                    onClick={() => setView('dashboard')}
                                    className="ml-auto px-4 py-2 bg-white/10 text-white rounded-lg hover:bg-white/20 transition-all"
                                >
                                    ← Back to Dashboard
                                </button>
                            </div>

                            {/* Read-only summary card */}
                            <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 border border-white/20">
                                <h3 className="text-lg font-bold text-white mb-4">Your shop</h3>
                                <div className="grid gap-3">
                                    <p className="text-white font-medium">{profile.shop_name || '—'}</p>
                                    <p className="text-purple-200 text-sm line-clamp-2">{profile.address || 'No address set'}</p>
                                    <div className="flex items-center gap-3 flex-wrap">
                                        <span className={`px-3 py-1 rounded-full text-sm font-semibold ${isOpen ? 'bg-green-500/20 text-green-300' : 'bg-red-500/20 text-red-300'}`}>
                                            {isOpen ? '● Open' : '● Closed'}
                                        </span>
                                        {profile.created_at && (
                                            <span className="text-white/60 text-sm">Member since {new Date(profile.created_at).toLocaleDateString(undefined, { month: 'long', year: 'numeric' })}</span>
                                        )}
                                    </div>
                                </div>
                            </div>

                            {/* Open/Closed toggle on profile */}
                            <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 border border-white/20">
                                <h3 className="text-lg font-bold text-white mb-3">Shop status</h3>
                                <div className="flex items-center gap-4">
                                    <span className="text-purple-200">Your shop is currently</span>
                                    <button
                                        type="button"
                                        onClick={toggleShopStatus}
                                        className={`px-4 py-2 rounded-lg font-semibold transition-all ${isOpen ? 'bg-green-500/20 text-green-300 hover:bg-green-500/30' : 'bg-red-500/20 text-red-300 hover:bg-red-500/30'}`}
                                    >
                                        {isOpen ? 'Open' : 'Closed'}
                                    </button>
                                    <span className="text-white/60 text-sm">— Toggle to change</span>
                                </div>
                            </div>

                            {/* Edit form */}
                            <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-8 border border-white/20">
                                <h3 className="text-lg font-bold text-white mb-6">Edit profile</h3>
                                {profileError && (
                                    <div className="mb-6 p-4 bg-red-500/20 border border-red-400/30 rounded-lg text-red-200 text-sm">{profileError}</div>
                                )}
                                <form onSubmit={handleUpdateProfile} className="max-w-xl space-y-6">
                                    <div>
                                        <label className="block text-white font-semibold mb-2">Shop name (also your login name)</label>
                                        <input
                                            type="text"
                                            value={profile.shop_name ?? ''}
                                            onChange={(e) => setProfile({ ...profile, shop_name: e.target.value })}
                                            className="w-full bg-white/10 border border-white/20 p-4 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-pink-500"
                                            required
                                        />
                                    </div>
                                    <div>
                                        <label className="block text-white font-semibold mb-2">Owner / contact name</label>
                                        <input
                                            type="text"
                                            value={profile.full_name ?? ''}
                                            onChange={(e) => setProfile({ ...profile, full_name: e.target.value })}
                                            placeholder="Optional"
                                            className="w-full bg-white/10 border border-white/20 p-4 rounded-lg text-white placeholder-white/40 focus:outline-none focus:ring-2 focus:ring-pink-500"
                                        />
                                    </div>
                                    <div>
                                        <label className="block text-white font-semibold mb-2">Address</label>
                                        <textarea
                                            value={profile.address}
                                            onChange={(e) => setProfile({ ...profile, address: e.target.value })}
                                            className="w-full bg-white/10 border border-white/20 p-4 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-pink-500 min-h-[100px]"
                                            placeholder="Full address shown to customers for directions"
                                            required
                                        />
                                    </div>
                                    <div className="grid sm:grid-cols-2 gap-4">
                                        <div>
                                            <label className="block text-white font-semibold mb-2">Email</label>
                                            <input
                                                type="email"
                                                value={profile.email ?? ''}
                                                onChange={(e) => setProfile({ ...profile, email: e.target.value })}
                                                placeholder="Optional"
                                                className="w-full bg-white/10 border border-white/20 p-4 rounded-lg text-white placeholder-white/40 focus:outline-none focus:ring-2 focus:ring-pink-500"
                                            />
                                        </div>
                                        <div>
                                            <label className="block text-white font-semibold mb-2">Phone</label>
                                            <input
                                                type="tel"
                                                value={profile.phone ?? ''}
                                                onChange={(e) => setProfile({ ...profile, phone: e.target.value })}
                                                placeholder="Optional"
                                                className="w-full bg-white/10 border border-white/20 p-4 rounded-lg text-white placeholder-white/40 focus:outline-none focus:ring-2 focus:ring-pink-500"
                                            />
                                        </div>
                                    </div>
                                    <div className="border-t border-white/20 pt-6">
                                        <p className="text-white font-semibold mb-2">Change password</p>
                                        <p className="text-purple-200 text-sm mb-3">Leave blank to keep your current password. To set a new password, enter your current password below.</p>
                                        <div className="space-y-4">
                                            <input
                                                type="password"
                                                value={profile.current_password}
                                                onChange={(e) => setProfile({ ...profile, current_password: e.target.value })}
                                                placeholder="Current password (required when changing)"
                                                className="w-full bg-white/10 border border-white/20 p-4 rounded-lg text-white placeholder-white/40 focus:outline-none focus:ring-2 focus:ring-pink-500"
                                            />
                                            <input
                                                type="password"
                                                value={profile.password}
                                                onChange={(e) => setProfile({ ...profile, password: e.target.value })}
                                                placeholder="New password"
                                                className="w-full bg-white/10 border border-white/20 p-4 rounded-lg text-white placeholder-white/40 focus:outline-none focus:ring-2 focus:ring-pink-500"
                                            />
                                        </div>
                                    </div>
                                    <button
                                        type="submit"
                                        className="w-full bg-gradient-to-r from-pink-500 to-purple-600 text-white font-bold py-4 rounded-lg hover:from-pink-600 hover:to-purple-700 transition-all shadow-lg"
                                    >
                                        Save changes
                                    </button>
                                </form>
                            </div>

                            {/* Security / Account */}
                            <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-8 border border-white/20">
                                <h3 className="text-lg font-bold text-white mb-2">Account</h3>
                                <p className="text-purple-200 text-sm mb-6">Log out or permanently delete your shop account.</p>
                                <div className="flex flex-wrap gap-4">
                                    <button
                                        type="button"
                                        onClick={handleLogout}
                                        className="px-6 py-3 bg-white/10 hover:bg-white/20 text-white rounded-lg font-semibold transition-all border border-white/20"
                                    >
                                        Log out
                                    </button>
                                    <button
                                        type="button"
                                        onClick={() => setShowDeleteAccountModal(true)}
                                        className="px-6 py-3 bg-red-500/20 hover:bg-red-500/30 text-red-300 rounded-lg font-semibold transition-all border border-red-400/30"
                                    >
                                        Delete account
                                    </button>
                                </div>
                            </div>
                        </div>
                    ) : (
                        <>
                            {/* Private Print Section */}
                            <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-8 border border-white/20">
                                <div className="text-center mb-8">
                                    <div className="text-6xl mb-4">🖨️</div>
                                    <h2 className="text-3xl font-bold text-white mb-2">Private Print</h2>
                                    <p className="text-purple-200">Print using unique code</p>
                                </div>

                                <form onSubmit={handlePrivatePrintSubmit} className="space-y-6">
                                    <div>
                                        <label className="block text-white font-semibold mb-2">Unique Code</label>
                                        <input
                                            type="text"
                                            value={code}
                                            onChange={(e) => setCode(e.target.value)}
                                            placeholder="Enter 6-character code"
                                            maxLength={6}
                                            autoComplete="off"
                                            spellCheck="false"
                                            className="w-full bg-white/20 border-2 border-white/30 p-4 rounded-lg text-white text-center text-2xl font-bold tracking-widest placeholder-purple-300 focus:outline-none focus:ring-2 focus:ring-pink-500"
                                            required
                                        />
                                    </div>

                                    <button
                                        type="submit"
                                        disabled={code.length !== 6 || downloading}
                                        className="w-full bg-gradient-to-r from-pink-500 to-purple-600 text-white font-bold py-4 rounded-lg hover:from-pink-600 hover:to-purple-700 transition-all duration-300 shadow-lg hover:shadow-xl disabled:opacity-50 disabled:cursor-not-allowed text-lg"
                                    >
                                        {downloading ? '⏳ Processing...' : '🖨️ Print Now'}
                                    </button>
                                </form>
                            </div>

                            {/* Queue Info */}
                            <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-8 border border-white/20">
                                <div className="text-center mb-8">
                                    <div className="text-6xl mb-4">📋</div>
                                    <h2 className="text-3xl font-bold text-white mb-2">Print Queue</h2>
                                    <p className="text-purple-200">Files waiting in your queue</p>
                                </div>

                                <div className="space-y-4">
                                    <div className="bg-white/10 rounded-lg p-4">
                                        <div className="flex items-center justify-between">
                                            <div>
                                                <p className="text-purple-200 text-sm">Total in Queue</p>
                                                <p className="text-white font-bold text-3xl">{queue.length}</p>
                                            </div>
                                            <div className="text-4xl">📊</div>
                                        </div>
                                    </div>

                                    <div className="bg-gradient-to-r from-pink-500/20 to-purple-600/20 border border-pink-400/30 rounded-lg p-4">
                                        <p className="text-white font-semibold mb-2">💡 Queue Tips</p>
                                        <ul className="text-purple-200 text-sm space-y-1">
                                            <li>• Files are shown in order (FIFO)</li>
                                            <li>• Print dialog will appear when you click Print</li>
                                            <li>• Confirm completion after printing</li>
                                            <li>• Queue refreshes every 5 seconds</li>
                                        </ul>
                                    </div>
                                </div>
                            </div>
                        </>
                    )}
                </div>

                {/* Queue Table - Only show in Dashboard view */}
                {view === 'dashboard' && (
                    <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-8 border border-white/20">
                        <div className="flex items-center gap-3 mb-6">
                            <div className="text-4xl">📋</div>
                            <h2 className="text-2xl font-bold text-white">Queue Files</h2>
                            <span className="ml-auto bg-pink-500/30 text-pink-200 px-3 py-1 rounded-full text-sm font-semibold">
                                {queue.length} files
                            </span>
                        </div>

                        <div className="overflow-x-auto">
                            {queue.length === 0 ? (
                                <div className="text-center py-12 text-purple-200">
                                    <div className="text-5xl mb-4">📭</div>
                                    <p>No files in queue</p>
                                </div>
                            ) : (
                                <table className="w-full">
                                    <thead>
                                        <tr className="border-b border-white/20">
                                            <th className="text-left text-purple-200 font-semibold p-3">#</th>
                                            <th className="text-left text-purple-200 font-semibold p-3">Customer</th>
                                            <th className="text-left text-purple-200 font-semibold p-3">File</th>
                                            <th className="text-left text-purple-200 font-semibold p-3">Settings</th>
                                            <th className="text-left text-purple-200 font-semibold p-3">Cost</th>
                                            <th className="text-left text-purple-200 font-semibold p-3">Action</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {queue.map((job, index) => {
                                            const orderGroupId = job.order_group_id || job.id;
                                            const isBatch = job.file_count && job.file_count > 1;
                                            return (
                                                <tr key={orderGroupId || index} className="border-b border-white/10 hover:bg-white/5">
                                                    <td className="p-3">
                                                        <span className="text-pink-400 font-bold text-lg">#{job.queue_position}</span>
                                                    </td>
                                                    <td className="p-3">
                                                        <p className="text-white font-semibold">{job.customer_name}</p>
                                                        <p className="text-purple-300 text-xs">
                                                            {new Date(job.created_at).toLocaleString()}
                                                        </p>
                                                    </td>
                                                    <td className="p-3">
                                                        <p className="text-white text-sm">
                                                            {isBatch ? `${job.file_count} file(s)` : (job.filename || 'File')}
                                                        </p>
                                                        <p className="text-purple-300 text-xs">
                                                            {job.total_pages || job.num_pages} pages
                                                        </p>
                                                    </td>
                                                    <td className="p-3">
                                                        <div className="text-white text-sm space-y-1">
                                                            <div>📄 {job.copies} copies</div>
                                                            <div>🔄 {job.print_mode}</div>
                                                            <div>🎨 {job.color_mode}</div>
                                                            <div>📏 {job.paper_size}</div>
                                                            {job.comment && (
                                                                <div className="mt-2 pt-2 border-t border-white/10">
                                                                    <div className="text-yellow-300 text-xs font-semibold mb-1">💬 Comment:</div>
                                                                    <div className="text-purple-200 text-xs italic">{job.comment}</div>
                                                                </div>
                                                            )}
                                                        </div>
                                                    </td>
                                                    <td className="p-3">
                                                        <p className="text-white font-bold text-lg">₹{job.total_cost}</p>
                                                    </td>
                                                    <td className="p-3">
                                                        <div className="flex items-center gap-2 flex-wrap">
                                                            <button
                                                                onClick={() => openCancelOrderModal(job)}
                                                                className="px-3 py-2 bg-orange-500/20 text-orange-300 border border-orange-400/30 rounded-lg hover:bg-orange-500/30 transition-all font-semibold text-sm"
                                                            >
                                                                Cancel order
                                                            </button>
                                                            <button
                                                                onClick={() => handlePrint('', true, undefined, orderGroupId, isBatch)}
                                                                className="px-4 py-2 bg-gradient-to-r from-pink-500 to-purple-600 text-white font-semibold rounded-lg hover:from-pink-600 hover:to-purple-700 transition-all"
                                                            >
                                                                🖨️ Print
                                                            </button>
                                                        </div>
                                                    </td>
                                                </tr>
                                            );
                                        })}
                                    </tbody>
                                </table>
                            )}
                        </div>
                    </div>
                )}
            </div>

            {/* Print Confirmation Modal */}
            {
                showConfirmModal && (
                    <div className="fixed inset-0 bg-black/80 backdrop-blur-sm flex items-center justify-center z-50">
                        <div className="bg-white/10 backdrop-blur-xl border border-white/20 p-8 rounded-2xl max-w-md w-full text-center shadow-2xl animate-in fade-in zoom-in duration-300">
                            <div className="text-6xl mb-6">🖨️</div>
                            <h3 className="text-2xl font-bold text-white mb-4">Printing in Progress...</h3>
                            <p className="text-purple-200 mb-8">
                                Please check the print dialog. Once the document is printed successfully, click Confirm below.
                            </p>

                            <div className="flex gap-4">
                                <button
                                    onClick={handleCancelPrint}
                                    className="flex-1 px-6 py-3 bg-red-500/20 text-red-300 border border-red-500/30 rounded-xl hover:bg-red-500/30 transition-all font-semibold"
                                >
                                    ❌ Cancel
                                </button>
                                <button
                                    onClick={handleConfirmPrint}
                                    className="flex-1 px-6 py-3 bg-green-500/20 text-green-300 border border-green-500/30 rounded-xl hover:bg-green-500/30 transition-all font-bold"
                                >
                                    ✅ Confirm Print
                                </button>
                            </div>
                        </div>
                    </div>
                )
            }

            {/* Cancel Order Modal (shopkeeper cancels queue order with reason) */}
            {showCancelOrderModal && cancelOrderJob && (
                <div className="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-4">
                    <div className="bg-gradient-to-br from-indigo-900/95 via-purple-900/95 to-pink-900/95 backdrop-blur-xl rounded-2xl border-2 border-orange-400/50 shadow-2xl max-w-md w-full p-6">
                        <div className="flex items-center gap-3 mb-4">
                            <div className="text-4xl">⚠️</div>
                            <div>
                                <h3 className="text-xl font-bold text-white">Cancel order</h3>
                                <p className="text-orange-200 text-sm">Customer will be notified and refunded</p>
                            </div>
                        </div>
                        <p className="text-purple-200 text-sm mb-3">Reason (required):</p>
                        <textarea
                            value={cancelReason}
                            onChange={(e) => { setCancelReason(e.target.value); setCancelError(''); }}
                            placeholder="e.g. Printer out of order, paper not available"
                            maxLength={500}
                            rows={3}
                            className="w-full bg-white/10 border border-white/20 p-3 rounded-lg text-white placeholder-white/40 focus:outline-none focus:ring-2 focus:ring-orange-500 resize-none"
                        />
                        {cancelError && (
                            <p className="mt-2 text-red-400 text-sm">{cancelError}</p>
                        )}
                        <div className="flex gap-3 mt-4">
                            <button
                                type="button"
                                onClick={closeCancelOrderModal}
                                disabled={cancellingOrder}
                                className="flex-1 px-4 py-3 bg-white/10 hover:bg-white/20 text-white rounded-lg font-semibold border border-white/20 disabled:opacity-50"
                            >
                                Back
                            </button>
                            <button
                                type="button"
                                onClick={handleConfirmCancelOrder}
                                disabled={!cancelReason.trim() || cancellingOrder}
                                className="flex-1 px-4 py-3 bg-orange-500 hover:bg-orange-600 text-white rounded-lg font-bold disabled:opacity-50 disabled:cursor-not-allowed"
                            >
                                {cancellingOrder ? 'Cancelling...' : 'Cancel order'}
                            </button>
                        </div>
                    </div>
                </div>
            )}

            {/* Delete Account Modal */}
            {showDeleteAccountModal && (
                <div className="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-4">
                    <div className="bg-gradient-to-br from-red-900/95 via-purple-900/95 to-pink-900/95 backdrop-blur-xl rounded-2xl border-2 border-red-400/50 shadow-2xl max-w-md w-full p-6 animate-in fade-in zoom-in duration-300">
                        {/* Header */}
                        <div className="flex items-center gap-3 mb-4">
                            <div className="text-4xl">⚠️</div>
                            <div>
                                <h3 className="text-2xl font-bold text-red-300">Delete Account</h3>
                                <p className="text-red-200 text-sm">This action cannot be undone</p>
                            </div>
                        </div>

                        {/* Warning Message */}
                        <div className="bg-red-500/20 border border-red-400/30 rounded-xl p-4 mb-6">
                            <p className="text-red-200 text-sm leading-relaxed">
                                ⚠️ <strong>Warning:</strong> This will permanently delete your shop account and all associated data including print history, earnings records, and customer orders.
                            </p>
                        </div>

                        {/* Password Input */}
                        <div className="mb-6">
                            <label className="block text-white/80 text-sm font-semibold mb-2">
                                Enter your password to confirm:
                            </label>
                            <input
                                type="password"
                                value={deletePassword}
                                onChange={(e) => {
                                    setDeletePassword(e.target.value);
                                    setDeleteError('');
                                }}
                                placeholder="Password"
                                className="w-full bg-white/10 border border-white/30 p-3 rounded-lg text-white placeholder-white/50 focus:outline-none focus:ring-2 focus:ring-red-500"
                            />
                            {deleteError && (
                                <p className="text-red-400 text-sm mt-2">{deleteError}</p>
                            )}
                        </div>

                        {/* Action Buttons */}
                        <div className="flex gap-3">
                            <button
                                onClick={() => {
                                    setShowDeleteAccountModal(false);
                                    setDeletePassword('');
                                    setDeleteError('');
                                }}
                                className="flex-1 px-4 py-3 bg-white/10 hover:bg-white/20 text-white rounded-lg font-semibold transition-all border border-white/20"
                            >
                                Cancel
                            </button>
                            <button
                                onClick={handleDeleteAccount}
                                disabled={deletingAccount}
                                className="flex-1 px-4 py-3 bg-gradient-to-r from-red-500 to-red-700 hover:from-red-600 hover:to-red-800 text-white rounded-lg font-bold transition-all shadow-lg disabled:opacity-50 disabled:cursor-not-allowed"
                            >
                                {deletingAccount ? 'Deleting...' : 'Delete My Account'}
                            </button>
                        </div>
                    </div>
                </div>
            )}
            </div>
            <Footer />
        </div>
    );
}

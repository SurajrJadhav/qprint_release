"use client";

import { useState, useEffect } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import dynamic from 'next/dynamic';
import api, { calculateCost, calculateCostFromPages, createPaymentOrder, uploadFile, getPaymentStatus, getWalletBalance, getShopById, logout, deleteAccount } from '@/lib/api';
import { getSafeErrorMessage } from '@/lib/safeError';
import { openRazorpayCheckout } from '@/lib/razorpay';
import Footer from '@/components/Footer';
import DashboardHeader from '@/components/DashboardHeader';

// Dynamically import MapComponent to avoid SSR issues
const MapComponent = dynamic(() => import('@/components/MapComponent'), {
    ssr: false,
    loading: () => <div className="h-[400px] w-full bg-gray-200 animate-pulse rounded-xl"></div>
});

export default function DashboardPage() {
    const [files, setFiles] = useState<File[]>([]);
    const [fileInputKey, setFileInputKey] = useState(0); // Key to force file input reset
    const [uniqueCode, setUniqueCode] = useState('');
    const [shops, setShops] = useState<any[]>([]);
    const [myOrders, setMyOrders] = useState<any[]>([]);
    const [uploading, setUploading] = useState(false);
    const [processingPayment, setProcessingPayment] = useState(false);
    const [copied, setCopied] = useState(false);
    const [view, setView] = useState<'dashboard' | 'expenses' | 'history' | 'favorites'>('dashboard');
    const [favorites, setFavorites] = useState<number[]>([]);
    const [shopSearchQuery, setShopSearchQuery] = useState('');
    const [shopCodeInput, setShopCodeInput] = useState('');
    const [shopCodeError, setShopCodeError] = useState('');
    const [shopCodeLoading, setShopCodeLoading] = useState(false);
    const [showClosedShopModal, setShowClosedShopModal] = useState(false);
    const [closedShopData, setClosedShopData] = useState<any>(null);
    const [pendingUploadData, setPendingUploadData] = useState<{
        paymentOrderId: number;
        razorpayOrderId: string;
        keyId: string;
        totalCost: number;
        skipPayment: boolean;
        razorpayAmount?: number;
    } | null>(null);
    
    // Delete account modal state
    const [showDeleteAccountModal, setShowDeleteAccountModal] = useState(false);
    const [deletePassword, setDeletePassword] = useState('');
    const [deletingAccount, setDeletingAccount] = useState(false);
    const [deleteError, setDeleteError] = useState('');

    useEffect(() => {
        // Load favorites
        const saved = localStorage.getItem('favorites');
        if (saved) {
            try {
                setFavorites(JSON.parse(saved));
            } catch (e) {
                console.error("Failed to parse favorites", e);
            }
        }
    }, []);

    const toggleFavorite = (shopId: number) => {
        const newFavs = favorites.includes(shopId)
            ? favorites.filter(id => id !== shopId)
            : [...favorites, shopId];
        setFavorites(newFavs);
        localStorage.setItem('favorites', JSON.stringify(newFavs));
    };

    // Print settings
    const [copies, setCopies] = useState(1);
    const [printMode, setPrintMode] = useState('single');
    const [colorMode, setColorMode] = useState('bw');
    const [paperSize, setPaperSize] = useState('A4');
    const [printType, setPrintType] = useState<'private' | 'queue'>('private');
    const [selectedShop, setSelectedShop] = useState('');
    const [comment, setComment] = useState('');
    const [displayName, setDisplayName] = useState('');

    // User location
    const [userLat, setUserLat] = useState<number | null>(null);
    const [userLong, setUserLong] = useState<number | null>(null);

    // Upload response
    const [numPages, setNumPages] = useState(0);
    const [totalCost, setTotalCost] = useState(0);
    const [queuePosition, setQueuePosition] = useState<number | null>(null);
    
    // Estimated cost before upload
    const [estimatedCost, setEstimatedCost] = useState<number | null>(null);
    const [estimatedPages, setEstimatedPages] = useState<number | null>(null);
    const [isCalculatingCost, setIsCalculatingCost] = useState(false);
    /** Cached page count per file (same order as files). Used to avoid re-uploading when only shop/print type changes. */
    const [pagesPerFile, setPagesPerFile] = useState<number[]>([]);
    /** Filename from backend when cost calc fails (e.g. page count not available); mark in list so user can remove it. */
    const [costErrorFileName, setCostErrorFileName] = useState<string | null>(null);
    // Wallet: balance and payment method choice
    const [walletBalance, setWalletBalance] = useState<number | null>(null);
    const [walletBalanceLoading, setWalletBalanceLoading] = useState(false);
    const [showPaymentMethodModal, setShowPaymentMethodModal] = useState(false);
    const [pendingPaymentParams, setPendingPaymentParams] = useState<{
        totalCost: number;
        shopkeeper_id?: number;
        copies: number;
        print_mode: string;
        color_mode: string;
        paper_size: string;
        print_type: 'private' | 'queue';
        comment?: string;
    } | null>(null);

    const router = useRouter();
    const pathname = usePathname();
    
    // Check for view parameter in URL - listen to route changes
    useEffect(() => {
        const checkURL = () => {
            if (typeof window !== 'undefined') {
                const params = new URLSearchParams(window.location.search);
                const viewParam = params.get('view');
                if (viewParam && ['dashboard', 'expenses', 'history', 'favorites'].includes(viewParam)) {
                    setView(viewParam as 'dashboard' | 'expenses' | 'history' | 'favorites');
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
            : 'Customer';
        setDisplayName(safeName);

        // Get user location
        if (navigator.geolocation) {
            navigator.geolocation.getCurrentPosition((position) => {
                setUserLat(position.coords.latitude);
                setUserLong(position.coords.longitude);
                fetchShops();
            }, (error) => {
                console.error('Error getting location:', error);
                // Fallback to showing shops anyway
                fetchShops();
            });
        } else {
            fetchShops();
        }

        fetchMyOrders();

        // Refresh orders every 5 seconds to update status
        const filesInterval = setInterval(fetchMyOrders, 5000);
        
        // Refresh shops every 3 seconds to update status (open/closed)
        const shopsInterval = setInterval(fetchShops, 3000);
        
        return () => {
            clearInterval(filesInterval);
            clearInterval(shopsInterval);
        };
    }, []);

    const handleShopCodeSubmit = async () => {
        const raw = shopCodeInput.trim();
        if (!raw) return;
        const id = /^\d{1,9}$/.test(raw) ? parseInt(raw, 10) : null;
        if (id == null || id <= 0) {
            setShopCodeError('Enter a valid shop number');
            return;
        }
        setShopCodeError('');
        setShopCodeLoading(true);
        try {
            const shop = await getShopById(id);
            setSelectedShop(shop.id.toString());
            setPrintType('queue');
            const inList = shops.some((s: any) => s.id === shop.id);
            if (!inList) setShops((prev: any[]) => [...prev, shop]);
            setShopCodeInput('');
        } catch (err: any) {
            setShopCodeError(err.response?.status === 404 ? 'Shop not found' : getSafeErrorMessage(err, 'shop'));
        } finally {
            setShopCodeLoading(false);
        }
    };

    const fetchShops = async () => {
        try {
            const res = await api.get('/shops');
            console.log('Shops API Response:', res.data);
            console.log('Number of shops:', res.data?.length || 0);
            setShops(res.data || []);
            
            // Log if shops array is empty
            if (!res.data || res.data.length === 0) {
                console.warn('No shops returned from API. This could mean:');
                console.warn('1. No shopkeepers registered in the system');
                console.warn('2. User location not set in database (check backend logs)');
            }
        } catch (err: any) {
            console.error('Error fetching shops:', err);
            // Show error to user if it's a critical error
            if (err.response?.status === 401) {
                // Unauthorized - token expired or invalid
                localStorage.removeItem('token');
                router.push('/login');
            } else if (err.response?.status === 404) {
                // 404 may indicate user location not in DB or no shops
                console.warn('Shops fetch returned 404. User location may not be set.');
            } else if (err.response) {
                // API error (log only; do not expose response body)
                console.error('API Error:', err.response.status);
            } else if (err.request) {
                // Network error - API not reachable
                console.error('Network Error: Cannot reach API. Check NEXT_PUBLIC_API_URL:', process.env.NEXT_PUBLIC_API_URL);
            }
        }
    };

    const fetchMyOrders = async () => {
        try {
            const res = await api.get('/my-orders');
            setMyOrders(res.data.orders || []);
        } catch (err) {
            console.error('Error fetching orders:', err);
        }
    };

    const doCreatePaymentAndUpload = async (
        params: { totalCost: number; shopkeeper_id?: number; copies: number; print_mode: string; color_mode: string; paper_size: string; print_type: 'private' | 'queue'; comment?: string },
        useWallet: boolean,
        walletAmount?: number
    ) => {
        setProcessingPayment(true);
        try {
            const paymentOrder = await createPaymentOrder({
                amount: params.totalCost,
                shopkeeper_id: params.shopkeeper_id,
                copies: params.copies,
                print_mode: params.print_mode,
                color_mode: params.color_mode,
                paper_size: params.paper_size,
                print_type: params.print_type,
                comment: params.comment,
                use_wallet: useWallet,
                wallet_amount: walletAmount,
            });

            const paymentOrderId = paymentOrder.id;
            const razorpayOrderId = paymentOrder.order_id;
            const keyId = paymentOrder.key_id ?? '';
            const skipPayment = paymentOrder.skip_payment === true || paymentOrder.test_mode === true;
            const razorpayAmount = (paymentOrder.razorpay_amount ?? params.totalCost) as number;

            if (printType === 'queue' && selectedShop) {
                try {
                    const res = await api.get('/shops');
                    const latestShops = res.data || [];
                    const selectedShopData = latestShops.find((s: any) => s.id.toString() === selectedShop);
                    if (selectedShopData && !selectedShopData.is_open) {
                        setClosedShopData(selectedShopData);
                        setPendingUploadData({ paymentOrderId, razorpayOrderId, keyId, totalCost: params.totalCost, skipPayment, razorpayAmount });
                        setShowClosedShopModal(true);
                        setProcessingPayment(false);
                        return;
                    }
                } catch (err) {
                    console.error('Error checking shop status:', err);
                }
            }

            if (skipPayment) {
                await proceedWithUpload(paymentOrderId);
                setProcessingPayment(false);
                return;
            }

            await openRazorpayCheckout({
                key: keyId,
                amount: razorpayAmount * 100,
                order_id: razorpayOrderId,
                name: 'Qprint',
                description: 'Print Service Payment',
                handler: async () => {
                    let attempts = 0;
                    const maxAttempts = 10;
                    let paymentStatus = 'pending';
                    while (attempts < maxAttempts && paymentStatus !== 'paid') {
                        await new Promise(resolve => setTimeout(resolve, 500));
                        attempts++;
                        try {
                            const statusData = await getPaymentStatus(razorpayOrderId);
                            paymentStatus = statusData.status;
                            if (paymentStatus === 'paid') break;
                        } catch (err) {
                            console.error('Error checking payment status:', err);
                        }
                    }
                    if (paymentStatus === 'paid') {
                        await proceedWithUpload(paymentOrderId);
                    } else {
                        setProcessingPayment(false);
                        alert('Payment was successful but webhook is delayed. Please wait a moment and try uploading again, or contact support.');
                    }
                },
                onError: (error: unknown) => {
                    setProcessingPayment(false);
                    alert(getSafeErrorMessage(error, 'payment'));
                },
            });
        } catch (err: unknown) {
            setProcessingPayment(false);
            alert(getSafeErrorMessage(err, 'payment'));
        }
    };

    const handleUpload = async (e: React.FormEvent) => {
        e.preventDefault();
        if (files.length === 0) {
            alert('Please select at least one file');
            return;
        }
        if (printType === 'queue' && !selectedShop) {
            alert('Please select a shop for queue print');
            return;
        }
        const hasPpt = files.some((f) => /\.pptx?$/i.test(f.name));
        if (hasPpt && !confirm('Your order includes PowerPoint (.ppt/.pptx) file(s). They will be printed in landscape mode. Do you want to continue?')) {
            return;
        }

        setProcessingPayment(true);

        try {
            const shopId = printType === 'queue' && selectedShop ? parseInt(selectedShop, 10) : undefined;
            let totalCost: number;
            if (pagesPerFile.length === files.length && pagesPerFile.length > 0) {
                const totalPages = pagesPerFile.reduce((a, b) => a + b, 0);
                const costData = await calculateCostFromPages(totalPages, copies, printMode, colorMode, shopId);
                totalCost = costData.total_cost;
            } else {
                const costData = await calculateCost(
                    files,
                    copies,
                    printMode,
                    colorMode,
                    paperSize,
                    shopId
                );
                totalCost = costData.total_cost;
            }

            const params = {
                totalCost,
                shopkeeper_id: printType === 'queue' && selectedShop ? parseInt(selectedShop, 10) : undefined,
                copies,
                print_mode: printMode,
                color_mode: colorMode,
                paper_size: paperSize,
                print_type: printType,
                comment: comment.trim() || undefined,
            };

            if ((walletBalance ?? 0) > 0) {
                setPendingPaymentParams(params);
                setShowPaymentMethodModal(true);
                setProcessingPayment(false);
                return;
            }

            await doCreatePaymentAndUpload(params, false);
        } catch (err: unknown) {
            setProcessingPayment(false);
            alert(getSafeErrorMessage(err, 'payment'));
        }
    };

    const handlePaymentMethodChoice = (method: 'full_wallet' | 'razorpay_only' | 'hybrid') => {
        const params = pendingPaymentParams;
        setShowPaymentMethodModal(false);
        if (!params) return;
        const useWallet = method !== 'razorpay_only';
        const walletAmount = method === 'hybrid' && walletBalance != null
            ? Math.min(walletBalance, params.totalCost)
            : undefined;
        doCreatePaymentAndUpload(params, useWallet, walletAmount);
        setPendingPaymentParams(null);
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

    const handleCopy = async () => {
        try {
            await navigator.clipboard.writeText(uniqueCode);
            setCopied(true);
            setTimeout(() => setCopied(false), 2000);
        } catch (err) {
            console.error('Failed to copy:', err);
        }
    };

    // Calculate estimated cost when files or settings change.
    // Full calculateCost only when file list changes; cost-only when only shop/print type/options change.
    useEffect(() => {
        const calculateEstimatedCost = async () => {
            if (files.length === 0) {
                setEstimatedCost(null);
                setEstimatedPages(null);
                setPagesPerFile([]);
                setCostErrorFileName(null);
                return;
            }

            const shopId = printType === 'queue' && selectedShop ? parseInt(selectedShop, 10) : undefined;
            const useCostOnly = files.length === pagesPerFile.length && pagesPerFile.length > 0;

            setIsCalculatingCost(true);
            try {
                if (useCostOnly) {
                    const totalPages = pagesPerFile.reduce((a, b) => a + b, 0);
                    const costData = await calculateCostFromPages(totalPages, copies, printMode, colorMode, shopId);
                    setEstimatedCost(costData.total_cost);
                    setEstimatedPages(costData.total_pages ?? costData.num_pages ?? totalPages);
                    setCostErrorFileName(null);
                } else {
                    const costData = await calculateCost(
                        files,
                        copies,
                        printMode,
                        colorMode,
                        paperSize,
                        shopId
                    );
                    const perFile = (costData.files as { pages?: number }[] | undefined)?.map((f) => f.pages ?? 0) ?? [];
                    setPagesPerFile(perFile);
                    setEstimatedCost(costData.total_cost);
                    setEstimatedPages(costData.total_pages ?? costData.num_pages ?? 0);
                    setCostErrorFileName(null);
                }
            } catch (err: any) {
                console.error('Error calculating cost:', err);
                setEstimatedCost(null);
                setEstimatedPages(null);
                if (!useCostOnly) setPagesPerFile([]);
                const msg = typeof err?.response?.data === 'string' ? err.response.data : (err?.response?.data?.message ?? err?.message ?? '');
                const match = String(msg).match(/File '([^']+)'/);
                setCostErrorFileName(match ? match[1] : null);
            } finally {
                setIsCalculatingCost(false);
            }
        };

        const timeoutId = setTimeout(calculateEstimatedCost, 500);
        return () => clearTimeout(timeoutId);
    }, [files, copies, printMode, colorMode, paperSize, printType, selectedShop]);

    // Fetch wallet balance when we have an estimated cost (so payment method choice can be shown)
    useEffect(() => {
        if (files.length === 0 || estimatedCost == null) {
            setWalletBalance(null);
            return;
        }
        let cancelled = false;
        setWalletBalanceLoading(true);
        getWalletBalance()
            .then((data) => { if (!cancelled) setWalletBalance(data.balance ?? 0); })
            .catch(() => { if (!cancelled) setWalletBalance(0); })
            .finally(() => { if (!cancelled) setWalletBalanceLoading(false); });
        return () => { cancelled = true; };
    }, [files.length, estimatedCost]);

    const handleReset = () => {
        setUniqueCode('');
        setQueuePosition(null);
        setFiles([]);
        setFileInputKey(prev => prev + 1); // Force file input reset
        setNumPages(0);
        setTotalCost(0);
        setEstimatedCost(null);
        setEstimatedPages(null);
        setPagesPerFile([]);
        setCostErrorFileName(null);
        // Reset form options
        setCopies(1);
        setPrintMode('single');
        setColorMode('bw');
        setPaperSize('A4');
        setPrintType('private');
        setSelectedShop('');
        setShopSearchQuery('');
        setComment('');
    };

    const proceedWithUpload = async (paymentOrderId: number) => {
        if (files.length === 0) return;
        
        setProcessingPayment(false);
        setUploading(true);
        try {
            const res = await uploadFile(
                files,
                paymentOrderId,
                copies,
                printMode,
                colorMode,
                paperSize,
                printType,
                printType === 'queue' ? selectedShop : undefined,
                comment.trim() || undefined
            );
            
            // Handle batch response
            const totalPages = res.total_pages || res.num_pages || (res.files || []).reduce((sum: number, f: any) => sum + (f.num_pages || 0), 0);
            const totalCost = res.total_cost || (res.files || []).reduce((sum: number, f: any) => sum + (f.total_cost || 0), 0);
            
            setNumPages(totalPages);
            setTotalCost(totalCost);
            if (printType === 'private' && res.code) {
                setUniqueCode(res.code);
            } else {
                setQueuePosition(res.queue_position);
            }
            fetchMyOrders();
            
            // Reset form after successful upload
            setFiles([]);
            setPagesPerFile([]);
            setFileInputKey(prev => prev + 1); // Force file input reset
            setCopies(1);
            setPrintMode('single');
            setColorMode('bw');
            setPaperSize('A4');
            setPrintType('private');
            setSelectedShop('');
            setShopSearchQuery('');
            setComment('');
            
            // Close modal if open
            setShowClosedShopModal(false);
            setClosedShopData(null);
            setPendingUploadData(null);
        } catch (err: unknown) {
            alert(getSafeErrorMessage(err, 'upload'));
        } finally {
            setUploading(false);
        }
    };

    const handleConfirmClosedShopUpload = async () => {
        if (pendingUploadData && pendingUploadData.paymentOrderId) {
            // Skip Razorpay checkout if TEST_MODE is enabled
            if (pendingUploadData.skipPayment) {
                console.log('TEST_MODE: Skipping Razorpay checkout, proceeding directly to upload');
                await proceedWithUpload(pendingUploadData.paymentOrderId);
                setShowClosedShopModal(false);
                setPendingUploadData(null);
                return;
            }

            try {
                const amountPaise = (pendingUploadData.razorpayAmount ?? pendingUploadData.totalCost) * 100;
                await openRazorpayCheckout({
                    key: pendingUploadData.keyId,
                    amount: amountPaise,
                    order_id: pendingUploadData.razorpayOrderId,
                    name: 'Qprint',
                    description: 'Print Service Payment',
                    handler: async (response: any) => {
                        // Poll payment status
                        let attempts = 0;
                        const maxAttempts = 10;
                        let paymentStatus = 'pending';
                        
                        while (attempts < maxAttempts && paymentStatus !== 'paid') {
                            await new Promise(resolve => setTimeout(resolve, 500));
                            attempts++;
                            
                            try {
                                const statusData = await getPaymentStatus(pendingUploadData.razorpayOrderId);
                                paymentStatus = statusData.status;
                                
                                if (paymentStatus === 'paid') {
                                    break;
                                }
                            } catch (err) {
                                console.error('Error checking payment status:', err);
                            }
                        }
                        
                        if (paymentStatus === 'paid') {
                            await proceedWithUpload(pendingUploadData.paymentOrderId);
                        } else {
                            setProcessingPayment(false);
                            alert('Payment was successful but webhook is delayed. Please wait a moment and try uploading again.');
                        }
                    },
                    onError: (error: unknown) => {
                        setProcessingPayment(false);
                        alert(getSafeErrorMessage(error, 'payment'));
                    },
                });
            } catch (err: unknown) {
                alert(getSafeErrorMessage(err, 'payment'));
            }
        }
    };

    const handleCancelClosedShopUpload = () => {
        setShowClosedShopModal(false);
        setClosedShopData(null);
        setPendingUploadData(null);
    };

    const handleWithdrawPrint = async (fileId: number) => {
        if (!confirm('Are you sure you want to withdraw this print job? This action cannot be undone.')) {
            return;
        }

        try {
            await api.post(`/withdraw/${fileId}`);
            alert('Print job withdrawn successfully!');
            fetchMyOrders();
        } catch (err: unknown) {
            alert(getSafeErrorMessage(err, 'upload'));
        }
    };

    const handleWithdrawOrder = async (order: any) => {
        const fileCount = order.file_count ?? order.files?.length ?? 1;
        const msg = fileCount > 1
            ? `Withdraw this order (${fileCount} files)? Refund will be processed. This cannot be undone.`
            : 'Are you sure you want to withdraw this print job? This action cannot be undone.';
        if (!confirm(msg)) return;

        const firstFileId = order.files?.[0]?.id ?? order.id;
        try {
            await api.post(`/withdraw/${firstFileId}`);
            alert('Order withdrawn successfully!' + (fileCount > 1 ? ' Refund has been processed for the order.' : ''));
            fetchMyOrders();
        } catch (err: unknown) {
            alert(getSafeErrorMessage(err, 'upload'));
        }
    };

    return (
        <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800">
            <DashboardHeader 
                displayName={displayName}
                role="customer"
                onLogout={handleLogout}
                onDeleteAccount={() => setShowDeleteAccountModal(true)}
            />
            
            <div className="p-6 pt-8">
                <div className="max-w-7xl mx-auto space-y-6">
                {/* Upload Section */}
                {view === 'dashboard' && (
                    <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-8 border border-white/20">
                        <div className="flex items-center gap-3 mb-6">
                            <div className="text-4xl">📤</div>
                            <h2 className="text-2xl font-bold text-white">Upload Document</h2>
                        </div>

                        <form onSubmit={handleUpload} className="space-y-6">
                            {/* File Input */}
                            <div>
                                <label className="block text-white font-semibold mb-2">
                                    Select Files (PDF, images, Word, or PowerPoint) - Max 100MB total
                                </label>
                                <input
                                    key={fileInputKey} // Force reset by changing key
                                    type="file"
                                    accept=".pdf,.png,.jpg,.jpeg,.doc,.docx,.ppt,.pptx"
                                    multiple
                                    onChange={async (e) => {
                                        const selectedFiles = Array.from(e.target.files || []);
                                        if (selectedFiles.length === 0) { e.target.value = ''; return; }
                                        const maxFileSize = 20 * 1024 * 1024; // 20MB per file
                                        const maxGroupSize = 100 * 1024 * 1024; // 100MB total
                                        const allowedExtensions = ['.pdf', '.png', '.jpg', '.jpeg', '.doc', '.docx', '.ppt', '.pptx'];
                                        const supportedMsg = 'Supported: PDF, images (PNG/JPG/JPEG), Word (DOC/DOCX), PowerPoint (PPT/PPTX)';
                                        const pdfMagic = [0x25, 0x50, 0x44, 0x46, 0x2D]; // %PDF-
                                        const pngMagic = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]; // PNG
                                        const jpegMagic = [0xff, 0xd8, 0xff]; // JPEG

                                        let totalSize = files.reduce((sum, f) => sum + f.size, 0);
                                        const newFiles: File[] = [];

                                        for (const file of selectedFiles) {
                                            const fileName = file.name.toLowerCase();

                                            if (!allowedExtensions.some(ext => fileName.endsWith(ext))) {
                                                alert(`File '${file.name}': ${supportedMsg}`);
                                                continue;
                                            }

                                            if (file.size > maxFileSize) {
                                                alert(`File '${file.name}' exceeds maximum limit of 20MB per file. Size: ${(file.size / (1024 * 1024)).toFixed(2)}MB`);
                                                continue;
                                            }

                                            if (totalSize + file.size > maxGroupSize) {
                                                alert(`Adding '${file.name}' would exceed the 100MB total limit. Current total: ${(totalSize / (1024 * 1024)).toFixed(2)}MB`);
                                                continue;
                                            }

                                            // Magic-bytes check: reject renamed or wrong-type files early
                                            try {
                                                if (fileName.endsWith('.pdf')) {
                                                    const buf = await file.slice(0, 5).arrayBuffer();
                                                    const arr = new Uint8Array(buf);
                                                    if (arr.length < 5 || !pdfMagic.every((b, i) => arr[i] === b)) {
                                                        alert(`File '${file.name}' does not appear to be a valid PDF. Please choose a valid PDF file.`);
                                                        continue;
                                                    }
                                                } else if (fileName.endsWith('.png')) {
                                                    const buf = await file.slice(0, 8).arrayBuffer();
                                                    const arr = new Uint8Array(buf);
                                                    if (arr.length < 8 || !pngMagic.every((b, i) => arr[i] === b)) {
                                                        alert(`File '${file.name}' does not appear to be a valid PNG. Please choose a valid image file.`);
                                                        continue;
                                                    }
                                                } else if (fileName.endsWith('.jpg') || fileName.endsWith('.jpeg')) {
                                                    const buf = await file.slice(0, 3).arrayBuffer();
                                                    const arr = new Uint8Array(buf);
                                                    if (arr.length < 3 || !jpegMagic.every((b, i) => arr[i] === b)) {
                                                        alert(`File '${file.name}' does not appear to be a valid JPEG. Please choose a valid image file.`);
                                                        continue;
                                                    }
                                                } else if (fileName.endsWith('.docx') || fileName.endsWith('.pptx')) {
                                                    const buf = await file.slice(0, 4).arrayBuffer();
                                                    const arr = new Uint8Array(buf);
                                                    if (arr.length < 4 || arr[0] !== 0x50 || arr[1] !== 0x4b) {
                                                        alert(`File '${file.name}' does not appear to be a valid Word/PowerPoint file.`);
                                                        continue;
                                                    }
                                                } else if (fileName.endsWith('.doc') || fileName.endsWith('.ppt')) {
                                                    const buf = await file.slice(0, 4).arrayBuffer();
                                                    const arr = new Uint8Array(buf);
                                                    const oleMagic = [0xD0, 0xCF, 0x11, 0xE0];
                                                    if (arr.length < 4 || !oleMagic.every((b, i) => arr[i] === b)) {
                                                        alert(`File '${file.name}' does not appear to be a valid Word/PowerPoint file.`);
                                                        continue;
                                                    }
                                                }
                                            } catch {
                                                alert(`File '${file.name}' could not be read. Please try again.`);
                                                continue;
                                            }

                                            newFiles.push(file);
                                            totalSize += file.size;
                                        }

                                        if (newFiles.length > 0) setFiles([...files, ...newFiles]);
                                        e.target.value = '';
                                    }}
                                    className="w-full bg-white/20 border-2 border-dashed border-white/30 p-6 rounded-lg text-white file:mr-4 file:py-2 file:px-4 file:rounded-full file:border-0 file:bg-pink-500 file:text-white file:font-semibold hover:file:bg-pink-600 cursor-pointer"
                                />
                                
                                {/* File List */}
                                {files.length > 0 && (
                                    <div className="mt-4 space-y-2">
                                        <div className="text-white text-sm mb-2">
                                            Selected: {files.length} file(s) - Total: {(files.reduce((sum, f) => sum + f.size, 0) / (1024 * 1024)).toFixed(2)}MB
                                        </div>
                                        <div className="max-h-40 overflow-y-auto space-y-1">
                                            {files.map((file, index) => {
                                                const isProblemFile = costErrorFileName != null && (file.name === costErrorFileName || file.name.includes(costErrorFileName) || costErrorFileName.includes(file.name));
                                                return (
                                                    <div
                                                        key={index}
                                                        className={`flex flex-col gap-1 p-2 rounded text-white text-sm ${isProblemFile ? 'bg-amber-500/20 border border-amber-400/60' : 'bg-white/10'}`}
                                                    >
                                                        <div className="flex items-center justify-between">
                                                            <span className="truncate flex-1">{file.name} ({(file.size / (1024 * 1024)).toFixed(2)}MB)</span>
                                                            <button
                                                                type="button"
                                                                onClick={() => {
                                                                    const newFiles = files.filter((_, i) => i !== index);
                                                                    setFiles(newFiles);
                                                                }}
                                                                className="ml-2 text-red-400 hover:text-red-300 font-bold"
                                                            >
                                                                ×
                                                            </button>
                                                        </div>
                                                        {isProblemFile && (
                                                            <p className="text-amber-200 text-xs flex items-center gap-1">
                                                                <span aria-hidden>⚠</span>
                                                                Page count not available. Remove this file to continue.
                                                            </p>
                                                        )}
                                                    </div>
                                                );
                                            })}
                                        </div>
                                    </div>
                                )}
                            </div>

                            {/* Print Settings */}
                            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                                <div>
                                    <label className="block text-white font-semibold mb-2">Copies</label>
                                    <input
                                        type="number"
                                        min="1"
                                        max="100"
                                        value={copies}
                                        onChange={(e) => setCopies(parseInt(e.target.value))}
                                        className="w-full bg-white/20 border border-white/30 p-3 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-pink-500"
                                    />
                                </div>

                                <div>
                                    <label className="block text-white font-semibold mb-2">Print Mode</label>
                                    <select
                                        value={printMode}
                                        onChange={(e) => setPrintMode(e.target.value)}
                                        className="w-full bg-white/20 border border-white/30 p-3 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-pink-500"
                                    >
                                        <option value="single" className="text-black">Single-sided</option>
                                        <option value="double" className="text-black">Double-sided</option>
                                    </select>
                                </div>

                                <div>
                                    <label className="block text-white font-semibold mb-2">Color</label>
                                    <select
                                        value={colorMode}
                                        onChange={(e) => setColorMode(e.target.value)}
                                        className="w-full bg-white/20 border border-white/30 p-3 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-pink-500"
                                    >
                                        <option value="bw" className="text-black">Black & White</option>
                                        <option value="color" className="text-black">Color</option>
                                    </select>
                                </div>

                                <div>
                                    <label className="block text-white font-semibold mb-2">Paper Size</label>
                                    <select
                                        value={paperSize}
                                        onChange={(e) => setPaperSize(e.target.value)}
                                        className="w-full bg-white/20 border border-white/30 p-3 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-pink-500"
                                    >
                                        <option value="A4" className="text-black">A4</option>
                                    </select>
                                </div>
                            </div>

                            {/* Print Type Selection */}
                            <div>
                                <label className="block text-white font-semibold mb-3">Print Type</label>
                                <div className="grid grid-cols-2 gap-4">
                                    <button
                                        type="button"
                                        onClick={() => setPrintType('private')}
                                        className={`p-4 rounded-lg border-2 transition-all ${printType === 'private'
                                            ? 'bg-pink-500/30 border-pink-400'
                                            : 'bg-white/10 border-white/20 hover:bg-white/20'
                                            }`}
                                    >
                                        <div className="text-3xl mb-2">🔒</div>
                                        <div className="text-white font-bold">Private Print</div>
                                        <div className="text-purple-200 text-sm">Get unique code</div>
                                    </button>

                                    <button
                                        type="button"
                                        onClick={() => setPrintType('queue')}
                                        className={`p-4 rounded-lg border-2 transition-all ${printType === 'queue'
                                            ? 'bg-pink-500/30 border-pink-400'
                                            : 'bg-white/10 border-white/20 hover:bg-white/20'
                                            }`}
                                    >
                                        <div className="text-3xl mb-2">📋</div>
                                        <div className="text-white font-bold">Queue Print</div>
                                        <div className="text-purple-200 text-sm">Send to shop queue</div>
                                    </button>
                                </div>
                                {printType === 'private' && (
                                    <p className="text-purple-200 text-sm mt-2">
                                        Pricing: platform default (B&W and color per page set by platform). Double-sided: full price.
                                    </p>
                                )}
                            </div>

                            {/* Comment Field */}
                            <div>
                                <label className="block text-white font-semibold mb-2">
                                    Comment (Optional)
                                    <span className="text-purple-200 text-sm font-normal ml-2">- Visible to shopkeeper</span>
                                </label>
                                <textarea
                                    value={comment}
                                    onChange={(e) => setComment(e.target.value)}
                                    placeholder="Add any special instructions or notes for the shopkeeper..."
                                    maxLength={500}
                                    rows={3}
                                    className="w-full bg-white/20 border border-white/30 p-3 rounded-lg text-white placeholder-white/50 focus:outline-none focus:ring-2 focus:ring-pink-500 resize-none"
                                />
                                <p className="text-purple-200 text-xs mt-1 text-right">
                                    {comment.length}/500 characters
                                </p>
                            </div>

                            {/* Shop Selector (for queue prints) - Card-based UI */}
                            {printType === 'queue' && (
                                <div>
                                    <label className="block text-white font-semibold mb-3 text-lg">
                                        Select Shop
                                    </label>

                                    {/* At a shop? Enter code */}
                                    <div className="mb-4 p-3 rounded-xl bg-pink-500/15 border border-pink-400/50">
                                        <p className="text-white/90 text-sm font-medium mb-2">At a shop? Enter shop code</p>
                                        <div className="flex gap-2">
                                            <input
                                                type="text"
                                                placeholder="Shop code or number"
                                                value={shopCodeInput}
                                                onChange={(e) => { setShopCodeInput(e.target.value); setShopCodeError(''); }}
                                                onKeyDown={(e) => e.key === 'Enter' && (e.preventDefault(), handleShopCodeSubmit())}
                                                className="flex-1 bg-white/20 border border-white/30 px-3 py-2 rounded-lg text-white placeholder-white/50 focus:outline-none focus:ring-2 focus:ring-pink-500"
                                            />
                                            <button
                                                type="button"
                                                onClick={handleShopCodeSubmit}
                                                disabled={shopCodeLoading || !shopCodeInput.trim()}
                                                className="px-4 py-2 bg-pink-500 hover:bg-pink-600 disabled:opacity-50 text-white font-semibold rounded-lg"
                                            >
                                                {shopCodeLoading ? '...' : 'Go'}
                                            </button>
                                        </div>
                                        {shopCodeError && <p className="text-red-300 text-xs mt-1">{shopCodeError}</p>}
                                    </div>
                                    
                                    {/* Search Bar */}
                                    <div className="mb-4">
                                        <div className="relative">
                                            <input
                                                type="text"
                                                placeholder="🔍 Search shops by name..."
                                                value={shopSearchQuery}
                                                onChange={(e) => setShopSearchQuery(e.target.value)}
                                                className="w-full bg-white/20 border border-white/30 p-3 pl-10 rounded-lg text-white placeholder-white/50 focus:outline-none focus:ring-2 focus:ring-pink-500"
                                            />
                                            <span className="absolute left-3 top-1/2 transform -translate-y-1/2 text-white/50">🔍</span>
                                        </div>
                                    </div>

                                    {/* Shop Cards Grid */}
                                    <div className="max-h-[400px] overflow-y-auto custom-scrollbar space-y-3 mb-4">
                                        {(() => {
                                            // Filter and sort shops
                                            const filteredShops = shops.filter(shop =>
                                                shop.shop_name.toLowerCase().includes(shopSearchQuery.toLowerCase())
                                            );
                                            
                                            // Sort by distance: nearest shop first, then in increasing order of distance
                                            const sortedShops = [...filteredShops].sort((a, b) => {
                                                const distanceA = a.distance ?? Infinity;
                                                const distanceB = b.distance ?? Infinity;
                                                return distanceA - distanceB;
                                            });

                                            if (sortedShops.length === 0) {
                                                return (
                                                    <div className="text-center py-8 text-purple-200">
                                                        <div className="text-4xl mb-2">🏪</div>
                                                        <p>No shops found matching your search</p>
                                                    </div>
                                                );
                                            }

                                            return sortedShops.map((shop) => {
                                                const isSelected = selectedShop === shop.id.toString();
                                                const isFavorite = favorites.includes(shop.id);
                                                
                                                return (
                                                    <div
                                                        key={shop.id}
                                                        onClick={() => setSelectedShop(shop.id.toString())}
                                                        className={`relative cursor-pointer transition-all duration-300 rounded-xl p-4 border-2 ${
                                                            isSelected
                                                                ? 'bg-gradient-to-r from-pink-500/30 to-purple-600/30 border-pink-400 shadow-lg shadow-pink-500/20 scale-[1.02]'
                                                                : 'bg-white/10 border-white/20 hover:bg-white/15 hover:border-white/30'
                                                        }`}
                                                    >
                                                        {/* Favorite Badge */}
                                                        {isFavorite && (
                                                            <div className="absolute top-2 right-2 text-2xl animate-pulse">
                                                                ⭐
                                                            </div>
                                                        )}

                                                        {/* Shop Header */}
                                                        <div className="flex items-start justify-between mb-3">
                                                            <div className="flex-1">
                                                                <div className="flex items-center gap-2 mb-1">
                                                                    <h3 className="text-white font-bold text-lg">
                                                                        {shop.shop_name}
                                                                    </h3>
                                                                    {shop.is_open ? (
                                                                        <span className="px-2 py-0.5 bg-green-500/30 text-green-300 text-xs rounded-full font-semibold">
                                                                            🟢 Open
                                                                        </span>
                                                                    ) : (
                                                                        <span className="px-2 py-0.5 bg-red-500/30 text-red-300 text-xs rounded-full font-semibold">
                                                                            🔴 Closed
                                                                        </span>
                                                                    )}
                                                                </div>
                                                                {shop.address && (
                                                                    <p className="text-white/60 text-sm truncate">
                                                                        📍 {shop.address}
                                                                    </p>
                                                                )}
                                                                {/* Shop pricing (visible to customer); use effective = shop or platform default */}
                                                                <div className="mt-1.5 text-sm text-purple-200">
                                                                    {(() => {
                                                                        const effBw = shop.effective_price_per_page_bw ?? shop.price_per_page_bw ?? 0;
                                                                        const effColor = shop.effective_price_per_page_color ?? shop.price_per_page_color ?? 0;
                                                                        const hasCustom = shop.price_per_page_bw != null || shop.price_per_page_color != null;
                                                                        return (
                                                                            <>
                                                                                B&W: ₹{effBw.toFixed(2)}/page
                                                                                <span className="ml-2">Color: ₹{effColor.toFixed(2)}/page</span>
                                                                                {!hasCustom && <span className="ml-2 text-white/60">(default)</span>}
                                                                                <span className="ml-2 text-white/70">
                                                                                    · Double-sided: {shop.double_sided_factor != null && shop.double_sided_factor < 1
                                                                                        ? `${(shop.double_sided_factor * 100).toFixed(0)}% of single`
                                                                                        : 'full price'}
                                                                                </span>
                                                                            </>
                                                                        );
                                                                    })()}
                                                                </div>
                                                            </div>
                                                        </div>

                                                        {/* Shop Details */}
                                                        <div className="flex items-center justify-between">
                                                            <div className="flex items-center gap-4">
                                                                {shop.distance !== undefined && (
                                                                    <div className="flex items-center gap-1">
                                                                        <span className="text-2xl">📏</span>
                                                                        <span className="text-white font-semibold">
                                                                            {shop.distance.toFixed(2)} km
                                                                        </span>
                                                                    </div>
                                                                )}
                                                                {shop.lat && shop.long && (
                                                                    <a
                                                                        href={`https://www.google.com/maps/dir/?api=1&destination=${shop.lat},${shop.long}`}
                                                                        target="_blank"
                                                                        rel="noopener noreferrer"
                                                                        onClick={(e) => e.stopPropagation()}
                                                                        className="px-3 py-1.5 bg-blue-500/20 hover:bg-blue-500/30 text-blue-300 rounded-lg transition-colors flex items-center gap-1 text-sm font-semibold"
                                                                    >
                                                                        🧭 Navigate
                                                                    </a>
                                                                )}
                                                            </div>
                                                            
                                                            {/* Favorite Toggle Button */}
                                        <button
                                            type="button"
                                                                onClick={(e) => {
                                                                    e.stopPropagation();
                                                                    toggleFavorite(shop.id);
                                                                }}
                                                                className={`px-3 py-2 rounded-lg transition-all text-xl ${
                                                                    isFavorite
                                                                        ? 'bg-pink-500/30 text-yellow-300 hover:bg-pink-500/40'
                                                                        : 'bg-white/10 text-white/50 hover:bg-white/20 hover:text-white'
                                                                }`}
                                                                title={isFavorite ? "Remove from favorites" : "Add to favorites"}
                                                            >
                                                                {isFavorite ? '⭐' : '🤍'}
                                        </button>
                                    </div>

                                                        {/* Selection Indicator */}
                                                        {isSelected && (
                                                            <div className="absolute -top-2 -right-2 bg-pink-500 text-white rounded-full w-8 h-8 flex items-center justify-center text-lg font-bold shadow-lg">
                                                                ✓
                                                            </div>
                                                        )}
                                                    </div>
                                                );
                                            });
                                        })()}
                                    </div>

                                    {/* Selected Shop Info */}
                                    {selectedShop && (() => {
                                        const shop = shops.find(s => s.id.toString() === selectedShop);
                                        if (!shop) return null;
                                        return (
                                            <div className="bg-gradient-to-r from-pink-500/20 to-purple-600/20 border border-pink-400/30 rounded-lg p-3 mb-2">
                                                <p className="text-white text-sm">
                                                    <span className="font-semibold">Selected:</span> {shop.shop_name}
                                                    {shop.distance !== undefined && (
                                                        <span className="text-purple-200 ml-2">
                                                            ({shop.distance.toFixed(2)} km away)
                                                        </span>
                                                    )}
                                                </p>
                                                <p className="text-purple-200 text-xs mt-1">
                                                    {(() => {
                                                        const effBw = shop.effective_price_per_page_bw ?? shop.price_per_page_bw ?? 0;
                                                        const effColor = shop.effective_price_per_page_color ?? shop.price_per_page_color ?? 0;
                                                        const hasCustom = shop.price_per_page_bw != null || shop.price_per_page_color != null;
                                                        return (
                                                            <>
                                                                B&W: ₹{effBw.toFixed(2)}/page · Color: ₹{effColor.toFixed(2)}/page
                                                                {!hasCustom && ' (default)'}
                                                                <span className="ml-2 text-white/70">
                                                                    · Double-sided: {shop.double_sided_factor != null && shop.double_sided_factor < 1
                                                                        ? `${(shop.double_sided_factor * 100).toFixed(0)}%` : 'full price'}
                                                                </span>
                                                            </>
                                                        );
                                                    })()}
                                                </p>
                                            </div>
                                        );
                                    })()}

                                    {!selectedShop && (
                                        <p className="text-purple-200 text-xs text-center py-2">
                                            👆 Click on a shop card to select it
                                        </p>
                                    )}
                                </div>
                            )}

                            {/* Estimated Cost & Wallet */}
                            {files.length > 0 && (
                                <div className="bg-gradient-to-r from-yellow-500/20 to-orange-600/20 border border-yellow-400/30 rounded-lg p-4 mb-4">
                                    <div className="flex items-center justify-between">
                                        <div>
                                            <p className="text-yellow-200 text-sm mb-1">Estimated Cost</p>
                                            {isCalculatingCost ? (
                                                <p className="text-white text-lg font-semibold">Calculating...</p>
                                            ) : estimatedCost !== null ? (
                                                <div>
                                                    <p className="text-white text-2xl font-bold">₹{estimatedCost.toFixed(2)}</p>
                                                    {estimatedPages !== null && (
                                                        <p className="text-yellow-200 text-xs mt-1">
                                                            {estimatedPages} page{estimatedPages !== 1 ? 's' : ''} × {copies} cop{copies !== 1 ? 'ies' : 'y'}
                                                        </p>
                                                    )}
                                                    {(walletBalance !== null || walletBalanceLoading) && (
                                                        <p className="text-purple-200 text-xs mt-1">
                                                            Wallet: {walletBalanceLoading ? '…' : `₹${(walletBalance ?? 0).toFixed(2)}`}
                                                        </p>
                                                    )}
                                                </div>
                                            ) : (
                                                <p className="text-white text-lg font-semibold">Unable to calculate</p>
                                            )}
                                        </div>
                                        <div className="text-4xl">💰</div>
                                    </div>
                                </div>
                            )}

                            {/* Submit Button */}
                            <button
                                type="submit"
                                disabled={uploading || processingPayment || files.length === 0}
                                className="w-full bg-gradient-to-r from-pink-500 to-purple-600 text-white font-bold py-4 rounded-lg hover:from-pink-600 hover:to-purple-700 transition-all duration-300 shadow-lg hover:shadow-xl disabled:opacity-50 disabled:cursor-not-allowed"
                            >
                                {processingPayment ? '💳 Processing Payment...' : uploading ? '📤 Uploading...' : `💳 Pay & ${printType === 'private' ? 'Get Code' : 'Upload to Queue'}`}
                            </button>
                        </form>

                        {/* Success Message - Private Print */}
                        {uniqueCode && printType === 'private' && (
                            <div className="mt-6 space-y-4">
                                <div className="bg-gradient-to-r from-green-500/20 to-emerald-600/20 border border-green-400/30 rounded-lg p-6">
                                    <p className="text-green-200 text-sm mb-2">✅ Upload Successful!</p>
                                    <div className="grid grid-cols-3 gap-4 mb-4">
                                        <div>
                                            <p className="text-purple-200 text-xs">Pages</p>
                                            <p className="text-white font-bold text-lg">{numPages}</p>
                                        </div>
                                        <div>
                                            <p className="text-purple-200 text-xs">Copies</p>
                                            <p className="text-white font-bold text-lg">{copies}</p>
                                        </div>
                                        <div>
                                            <p className="text-purple-200 text-xs">Total Cost</p>
                                            <p className="text-white font-bold text-lg">₹{totalCost}</p>
                                        </div>
                                    </div>
                                    <p className="text-purple-200 text-sm mb-2">Your Unique Code</p>
                                    <div className="flex items-center justify-between">
                                        <p className="text-4xl font-black text-white tracking-wider">{uniqueCode}</p>
                                        <button
                                            onClick={handleCopy}
                                            className="px-4 py-2 bg-white/20 text-white rounded-lg hover:bg-white/30 transition-all"
                                        >
                                            {copied ? '✅ Copied!' : '📋 Copy'}
                                        </button>
                                    </div>
                                    <button
                                        onClick={handleReset}
                                        className="w-full mt-4 py-3 bg-white/10 text-white rounded-lg hover:bg-white/20 transition-all border border-white/20 font-semibold"
                                    >
                                        🔄 Upload Another File
                                    </button>
                                </div>
                            </div>
                        )}

                        {/* Success Message - Queue Print */}
                        {queuePosition !== null && printType === 'queue' && (
                            <div className="mt-6 bg-gradient-to-r from-green-500/20 to-emerald-600/20 border border-green-400/30 rounded-lg p-6">
                                <p className="text-green-200 text-sm mb-4">✅ Added to Queue!</p>
                                <div className="grid grid-cols-4 gap-4">
                                    <div>
                                        <p className="text-purple-200 text-xs">Queue Position</p>
                                        <p className="text-white font-bold text-2xl">#{queuePosition}</p>
                                    </div>
                                    <div>
                                        <p className="text-purple-200 text-xs">Pages</p>
                                        <p className="text-white font-bold text-lg">{numPages}</p>
                                    </div>
                                    <div>
                                        <p className="text-purple-200 text-xs">Copies</p>
                                        <p className="text-white font-bold text-lg">{copies}</p>
                                    </div>
                                    <div>
                                        <p className="text-purple-200 text-xs">Total Cost</p>
                                        <p className="text-white font-bold text-lg">₹{totalCost}</p>
                                    </div>
                                </div>
                                <div className="bg-gradient-to-r from-blue-500/20 to-cyan-600/20 border border-blue-400/30 rounded-lg p-6 text-center">
                                    <p className="text-blue-200 text-sm mb-2">Sent to Queue</p>
                                    <p className="text-4xl font-black text-white mb-2">#{queuePosition}</p>
                                    <p className="text-white/60 text-sm">Your position in queue</p>

                                    {/* Navigate Button */}
                                    {(() => {
                                        const shop = shops.find(s => s.id.toString() === selectedShop.toString());
                                        if (shop && shop.lat && shop.long) {
                                            return (
                                                <a
                                                    href={`https://www.google.com/maps/dir/?api=1&destination=${shop.lat},${shop.long}`}
                                                    target="_blank"
                                                    rel="noopener noreferrer"
                                                    className="block mt-4 w-full py-3 bg-blue-500 hover:bg-blue-600 text-white rounded-lg transition-colors font-bold flex items-center justify-center gap-2"
                                                >
                                                    🧭 Navigate to Shop
                                                </a>
                                            );
                                        }
                                        return null;
                                    })()}

                                    <button
                                        onClick={handleReset}
                                        className="w-full mt-4 py-3 bg-white/10 text-white rounded-lg hover:bg-white/20 transition-all border border-white/20 font-semibold"
                                    >
                                        🔄 Upload Another File
                                    </button>
                                </div>
                            </div>
                        )}
                    </div>
                )}

                {/* Expense Tracker View */}
                {view === 'expenses' && (
                    <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-8 border border-white/20 mb-8">
                        <div className="flex items-center gap-3 mb-8">
                            <div className="text-4xl">💸</div>
                            <div>
                                <h2 className="text-2xl font-bold text-white">Expense Tracker</h2>
                                <p className="text-purple-200 text-sm">Track your printing expenses</p>
                            </div>
                            <button
                                onClick={() => setView('dashboard')}
                                className="ml-auto px-4 py-2 bg-white/10 text-white rounded-lg hover:bg-white/20 transition-all"
                            >
                                ← Back to Dashboard
                            </button>
                        </div>

                                <div className="grid md:grid-cols-3 gap-6">
                            <div className="bg-gradient-to-br from-red-500/20 to-pink-600/20 border border-red-500/30 rounded-xl p-6">
                                <p className="text-pink-200 text-sm mb-1">Total Spent</p>
                                <h3 className="text-4xl font-bold text-white">
                                    ₹{myOrders
                                        .filter((o: any) => o.status === 'downloaded')
                                        .reduce((sum: number, o: any) => sum + (o.total_cost || 0), 0).toFixed(2)}
                                </h3>
                                <p className="text-white/60 text-xs mt-2">Verified completed prints</p>
                            </div>

                            <div className="bg-gradient-to-br from-yellow-500/20 to-orange-600/20 border border-yellow-500/30 rounded-xl p-6">
                                <p className="text-yellow-200 text-sm mb-1">Pending Costs</p>
                                <h3 className="text-4xl font-bold text-white">
                                    ₹{myOrders
                                        .filter((o: any) => o.status !== 'downloaded' && o.status !== 'withdrawn' && o.status !== 'cancelled')
                                        .reduce((sum: number, o: any) => sum + (o.total_cost || 0), 0).toFixed(2)}
                                </h3>
                                <p className="text-white/60 text-xs mt-2">Active queue/private prints</p>
                            </div>

                            <div className="bg-gradient-to-br from-blue-500/20 to-indigo-600/20 border border-blue-500/30 rounded-xl p-6">
                                <p className="text-blue-200 text-sm mb-1">Total Files</p>
                                <h3 className="text-4xl font-bold text-white">
                                    {myOrders.reduce((n: number, o: any) => n + (o.file_count || o.files?.length || 1), 0)}
                                </h3>
                                <p className="text-white/60 text-xs mt-2">Lifetime uploads</p>
                            </div>
                        </div>
                    </div>
                )}

                {/* File History View (replaces My Files section when view='history') */}
                {(view === 'history' || view === 'dashboard') && (
                    <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-8 border border-white/20">
                        <div className="flex items-center gap-3 mb-6">
                            <div className="text-4xl">📁</div>
                            <h2 className="text-2xl font-bold text-white">
                                {view === 'history' ? 'File History' : 'My Files'}
                            </h2>
                            {view === 'history' && (
                                <button
                                    onClick={() => setView('dashboard')}
                                    className="ml-auto px-4 py-2 bg-white/10 text-white rounded-lg hover:bg-white/20 transition-all"
                                >
                                    ← Back to Dashboard
                                </button>
                            )}
                        </div>

                        <div className="space-y-3 max-h-[400px] overflow-y-auto custom-scrollbar">
                            {myOrders.length === 0 ? (
                                <div className="text-center py-12 text-purple-200">
                                    <div className="text-5xl mb-4">📄</div>
                                    <p>No print orders yet</p>
                                </div>
                            ) : (
                                myOrders.map((order) => (
                                    <div
                                        key={order.id}
                                        className="bg-white/10 rounded-lg p-4 border border-white/20"
                                    >
                                        <div className="flex items-start justify-between">
                                            <div className="flex-1">
                                                <div className="flex items-center gap-2 mb-2">
                                                    <span className="text-2xl">
                                                        {order.print_type === 'private' ? '🔒' : '📋'}
                                                    </span>
                                                    <span className="text-white font-semibold">
                                                        {order.print_type === 'private' ? 'Private Print' : 'Queue Print'}
                                                    </span>
                                                    {(order.file_count || order.files?.length || 0) > 1 && (
                                                        <span className="text-purple-300 text-sm">
                                                            ({order.file_count || order.files?.length} files)
                                                        </span>
                                                    )}
                                                    {order.print_type === 'private' && order.files?.[0]?.code && (
                                                        <span className="text-pink-400 font-mono text-lg">{order.files[0].code}</span>
                                                    )}
                                                </div>

                                                <div className="grid grid-cols-2 md:grid-cols-4 gap-2 text-sm">
                                                    <div>
                                                        <span className="text-purple-300">Pages:</span>
                                                        <span className="text-white ml-1">{order.num_pages ?? 0}</span>
                                                    </div>
                                                    <div>
                                                        <span className="text-purple-300">Copies:</span>
                                                        <span className="text-white ml-1">{order.copies ?? 1}</span>
                                                    </div>
                                                    <div>
                                                        <span className="text-purple-300">Mode:</span>
                                                        <span className="text-white ml-1">{order.print_mode ?? 'single'}</span>
                                                    </div>
                                                    <div>
                                                        <span className="text-purple-300">Cost:</span>
                                                        <span className="text-white ml-1">₹{order.total_cost ?? 0}</span>
                                                    </div>
                                                </div>

                                                {order.shop_name ? (
                                                    <div className="mt-2 text-sm flex items-center gap-2">
                                                        <div>
                                                            <span className="text-purple-300">Shop:</span>
                                                            <span className="text-white ml-1">{order.shop_name}</span>
                                                            {order.queue_position && (
                                                                <>
                                                                    <span className="text-purple-300 ml-3">Position:</span>
                                                                    <span className="text-pink-400 ml-1 font-bold">#{order.queue_position}</span>
                                                                </>
                                                            )}
                                                        </div>
                                                        {order.shop_lat != null && order.shop_long != null && (
                                                            <a
                                                                href={`https://www.google.com/maps/dir/?api=1&destination=${order.shop_lat},${order.shop_long}`}
                                                                target="_blank"
                                                                rel="noopener noreferrer"
                                                                className="ml-auto px-3 py-1 bg-blue-500/20 text-blue-300 rounded-lg hover:bg-blue-500/30 transition-colors flex items-center gap-1 text-xs"
                                                            >
                                                                🧭 Navigate
                                                            </a>
                                                        )}
                                                    </div>
                                                ) : (
                                                    <div className="mt-2 text-sm flex items-center gap-2">
                                                        <button
                                                            onClick={() => {
                                                                window.scrollTo({ top: document.body.scrollHeight, behavior: 'smooth' });
                                                            }}
                                                            className="ml-auto px-3 py-1 bg-pink-500/20 text-pink-300 rounded-lg hover:bg-pink-500/30 transition-colors flex items-center gap-1 text-xs"
                                                        >
                                                            📍 Find Nearby Shop
                                                        </button>
                                                    </div>
                                                )}
                                            </div>

                                            <div className="text-right">
                                                <div className={`px-3 py-1 rounded-full text-xs font-semibold ${
                                                    order.status === 'downloaded'
                                                    ? 'bg-green-500/20 text-green-300'
                                                    : order.status === 'withdrawn'
                                                        ? 'bg-red-500/20 text-red-300'
                                                    : order.status === 'cancelled'
                                                        ? 'bg-orange-500/20 text-orange-300'
                                                    : order.status === 'printing'
                                                        ? 'bg-blue-500/20 text-blue-300'
                                                    : 'bg-yellow-500/20 text-yellow-300'
                                                }`}>
                                                    {order.status === 'downloaded' ? '✅ Printed' : order.status === 'withdrawn' ? '🚫 Withdrawn' : order.status === 'cancelled' ? '❌ Cancelled by shop' : order.status === 'printing' ? '🖨️ Printing at shop...' : '⏳ Pending'}
                                                </div>
                                                {order.status === 'cancelled' && order.cancel_reason && (
                                                    <p className="mt-2 text-orange-200 text-xs max-w-[220px] text-right" title={order.cancel_reason}>
                                                        {order.cancel_reason}
                                                    </p>
                                                )}
                                                {order.status !== 'downloaded' && order.status !== 'withdrawn' && order.status !== 'printing' && order.status !== 'cancelled' && (
                                                    <button
                                                        onClick={() => handleWithdrawOrder(order)}
                                                        className="mt-2 px-3 py-1 bg-red-500/20 text-red-300 rounded-lg hover:bg-red-500/30 transition-colors flex items-center gap-1 text-xs"
                                                    >
                                                        Withdraw {(order.file_count || order.files?.length || 0) > 1 ? 'Order' : 'Print'}
                                                    </button>
                                                )}
                                            </div>
                                        </div>
                                    </div>
                                ))
                            )}
                        </div>
                    </div>
                )}

                {/* Map View */}
                {view === 'dashboard' && userLat !== null && userLong !== null && shops.length > 0 && (
                    <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-8 border border-white/20">
                        <div className="flex items-center gap-3 mb-6">
                            <div className="text-4xl">🗺️</div>
                            <h2 className="text-2xl font-bold text-white">Nearby Shops Map</h2>
                        </div>
                        <MapComponent
                            userLat={userLat}
                            userLong={userLong}
                            shops={shops}
                        />
                        <p className="text-purple-200 text-sm mt-4 text-center">
                            📍 Blue pin = Your location | 🔴 Red pins = Print shops
                        </p>
                    </div>
                )}
            </div>

            {/* Favorite Shops View */}
            {view === 'favorites' && (
                <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-8 border border-white/20 mb-8">
                    <div className="flex items-center gap-3 mb-6">
                        <div className="text-4xl">⭐</div>
                        <div>
                            <h2 className="text-2xl font-bold text-white">Favorite Shops</h2>
                            <p className="text-purple-200 text-sm">Your quick access list</p>
                        </div>
                        <button
                            onClick={() => setView('dashboard')}
                            className="ml-auto px-4 py-2 bg-white/10 text-white rounded-lg hover:bg-white/20 transition-all"
                        >
                            ← Back to Dashboard
                        </button>
                    </div>

                    <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
                        {favorites.length === 0 ? (
                            <div className="col-span-full text-center py-12 text-purple-300">
                                <p className="text-xl mb-2">No favorite shops yet</p>
                                <p className="text-sm">Go to Dashboard and add shops to your favorites!</p>
                            </div>
                        ) : (
                            shops.filter(s => favorites.includes(s.id)).map(shop => (
                                <div key={shop.id} className="bg-white/5 border border-white/10 rounded-xl p-6 hover:bg-white/10 transition-all">
                                    <div className="flex justify-between items-start mb-4">
                                        <div>
                                            <h3 className="text-xl font-bold text-white">{shop.shop_name}</h3>
                                            <p className="text-purple-200 text-sm">{shop.distance?.toFixed(2)} km away</p>
                                        </div>
                                        <button
                                            onClick={() => toggleFavorite(shop.id)}
                                            className="text-2xl hover:scale-110 transition-transform"
                                            title="Remove from favorites"
                                        >
                                            ⭐
                                        </button>
                                    </div>
                                    <p className="text-white/60 text-sm mb-4">{shop.address || 'No address provided'}</p>
                                    <div className="flex gap-2">
                                        <button
                                            onClick={() => {
                                                setSelectedShop(shop.id.toString());
                                                setPrintType('queue');
                                                setView('dashboard');
                                            }}
                                            className="flex-1 bg-pink-500 hover:bg-pink-600 text-white py-2 rounded-lg font-semibold transition-colors"
                                        >
                                            Select
                                        </button>
                                        {shop.lat && shop.long && (
                                            <a
                                                href={`https://www.google.com/maps/dir/?api=1&destination=${shop.lat},${shop.long}`}
                                                target="_blank"
                                                rel="noopener noreferrer"
                                                className="px-3 py-2 bg-blue-500 hover:bg-blue-600 text-white rounded-lg transition-colors"
                                                title="Navigate"
                                            >
                                                🧭
                                            </a>
                                        )}
                                    </div>
                                </div>
                            ))
                        )}
                    </div>
                </div>
            )}

            {/* Payment method choice (when wallet has balance) */}
            {showPaymentMethodModal && pendingPaymentParams && (
                <div className="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-4">
                    <div className="bg-gradient-to-br from-indigo-900/95 via-purple-900/95 to-pink-900/95 backdrop-blur-xl rounded-2xl border-2 border-white/20 shadow-2xl max-w-md w-full p-6">
                        <h3 className="text-xl font-bold text-white mb-2">Choose payment method</h3>
                        <p className="text-purple-200 text-sm mb-4">
                            Total: ₹{pendingPaymentParams.totalCost.toFixed(2)}. Wallet: ₹{(walletBalance ?? 0).toFixed(2)}
                        </p>
                        <div className="space-y-3">
                            <button
                                type="button"
                                onClick={() => handlePaymentMethodChoice('full_wallet')}
                                disabled={(walletBalance ?? 0) < pendingPaymentParams.totalCost}
                                className="w-full py-3 px-4 bg-white/10 hover:bg-white/20 border border-white/20 rounded-lg text-white font-medium disabled:opacity-50 disabled:cursor-not-allowed"
                            >
                                Pay full amount from wallet
                            </button>
                            <button
                                type="button"
                                onClick={() => handlePaymentMethodChoice('hybrid')}
                                className="w-full py-3 px-4 bg-white/10 hover:bg-white/20 border border-white/20 rounded-lg text-white font-medium"
                            >
                                Use ₹{Math.min(walletBalance ?? 0, pendingPaymentParams.totalCost).toFixed(2)} from wallet, rest via card/UPI
                            </button>
                            <button
                                type="button"
                                onClick={() => handlePaymentMethodChoice('razorpay_only')}
                                className="w-full py-3 px-4 bg-white/10 hover:bg-white/20 border border-white/20 rounded-lg text-white font-medium"
                            >
                                Pay full amount via card/UPI (Razorpay)
                            </button>
                            <button
                                type="button"
                                onClick={() => { setShowPaymentMethodModal(false); setPendingPaymentParams(null); }}
                                className="w-full py-2 text-white/70 hover:text-white text-sm"
                            >
                                Cancel
                            </button>
                        </div>
                    </div>
                </div>
            )}

            {/* Closed Shop Confirmation Modal */}
            {showClosedShopModal && closedShopData && (
                <div className="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-4">
                    <div className="bg-gradient-to-br from-red-900/95 via-purple-900/95 to-pink-900/95 backdrop-blur-xl rounded-2xl border-2 border-red-400/50 shadow-2xl max-w-md w-full p-6 animate-in fade-in zoom-in duration-300">
                        {/* Header */}
                        <div className="flex items-center gap-3 mb-4">
                            <div className="text-4xl">⚠️</div>
                            <div>
                                <h3 className="text-2xl font-bold text-white">Shop is Closed</h3>
                                <p className="text-red-200 text-sm">Please confirm your action</p>
                            </div>
                        </div>

                        {/* Shop Info */}
                        <div className="bg-white/10 rounded-xl p-4 mb-4 border border-white/20">
                            <div className="flex items-center gap-2 mb-2">
                                <span className="text-2xl">🏪</span>
                                <h4 className="text-xl font-bold text-white">{closedShopData.shop_name}</h4>
                                <span className="px-2 py-1 bg-red-500/30 text-red-300 text-xs rounded-full font-semibold">
                                    🔴 Closed
                                </span>
                            </div>
                            {closedShopData.distance !== undefined && (
                                <p className="text-purple-200 text-sm">
                                    📏 {closedShopData.distance.toFixed(2)} km away
                                </p>
                            )}
                            {closedShopData.address && (
                                <p className="text-white/60 text-sm mt-1">
                                    📍 {closedShopData.address}
                                </p>
                            )}
                        </div>

                        {/* Warning Message */}
                        <div className="bg-yellow-500/20 border border-yellow-400/30 rounded-xl p-4 mb-6">
                            <p className="text-yellow-200 text-sm leading-relaxed">
                                ⚠️ <strong>Warning:</strong> This shop is currently <strong>CLOSED</strong>. 
                                The shopkeeper may not be available to process your print job immediately.
                            </p>
                            <p className="text-yellow-100 text-sm mt-2">
                                Are you sure you want to proceed with uploading to this closed shop?
                            </p>
                        </div>

                        {/* Action Buttons */}
                        <div className="flex gap-3">
                            <button
                                onClick={handleCancelClosedShopUpload}
                                className="flex-1 px-4 py-3 bg-white/10 hover:bg-white/20 text-white rounded-lg font-semibold transition-all border border-white/20"
                            >
                                Cancel
                            </button>
                            <button
                                onClick={handleConfirmClosedShopUpload}
                                disabled={uploading || processingPayment}
                                className="flex-1 px-4 py-3 bg-gradient-to-r from-red-500 to-pink-600 hover:from-red-600 hover:to-pink-700 text-white rounded-lg font-bold transition-all shadow-lg disabled:opacity-50 disabled:cursor-not-allowed"
                            >
                                {processingPayment ? 'Processing Payment...' : uploading ? 'Uploading...' : 'Proceed Anyway'}
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
                                ⚠️ <strong>Warning:</strong> This will permanently delete your account and all associated data including files, print history, and favorites.
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

                <style jsx>{`
                    .custom-scrollbar::-webkit-scrollbar {
                        width: 8px;
                    }
                    .custom-scrollbar::-webkit-scrollbar-track {
                        background: rgba(255, 255, 255, 0.1);
                        border-radius: 10px;
                    }
                    .custom-scrollbar::-webkit-scrollbar-thumb {
                        background: rgba(236, 72, 153, 0.5);
                        border-radius: 10px;
                    }
                    .custom-scrollbar::-webkit-scrollbar-thumb:hover {
                        background: rgba(236, 72, 153, 0.7);
                    }
                `}</style>
            </div>
            <Footer />
        </div>
    );
}

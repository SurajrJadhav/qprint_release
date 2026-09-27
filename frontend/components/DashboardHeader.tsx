"use client";

import { useState, useEffect, Suspense } from 'react';
import { useRouter, usePathname, useSearchParams } from 'next/navigation';
import Link from 'next/link';
import { getWalletBalance } from '@/lib/api';

// Client-side navigation handler for same-route query param changes
const handleNavigation = (e: React.MouseEvent<HTMLAnchorElement>, href: string, router: any) => {
    e.preventDefault();
    router.push(href);
};

interface DashboardHeaderProps {
    displayName: string;
    role: 'customer' | 'shopkeeper';
    onLogout: () => void;
    onDeleteAccount?: () => void;
    shopStatus?: boolean;
    onToggleShopStatus?: () => void;
}

const normalizeDisplayName = (value: string | null | undefined, fallback = 'User') => {
    const normalized = (value ?? '').trim();
    if (!normalized || normalized.toLowerCase() === 'undefined' || normalized.toLowerCase() === 'null') {
        return fallback;
    }
    return normalized;
};

function DashboardHeaderFallback({ displayName }: { displayName: string }) {
    const safeDisplayName = normalizeDisplayName(displayName);
    return (
        <header className="sticky top-0 z-50 bg-gradient-to-br from-indigo-900/95 via-purple-900/95 to-pink-800/95 backdrop-blur-lg border-b border-white/10 shadow-lg">
            <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
                <div className="flex items-center justify-between h-16 md:h-20">
                    <Link href="/" className="flex items-center group">
                        <span className="text-xl md:text-2xl font-black text-white group-hover:text-pink-400 transition-colors">
                            Q<span className="text-pink-400">print</span>
                        </span>
                    </Link>
                    <div className="w-10 h-10 rounded-full bg-gradient-to-br from-pink-500 to-purple-600 flex items-center justify-center text-white font-bold text-lg">
                        {safeDisplayName[0]?.toUpperCase() || 'U'}
                    </div>
                </div>
            </div>
        </header>
    );
}

function DashboardHeaderContent({ 
    displayName, 
    role, 
    onLogout,
    onDeleteAccount,
    shopStatus,
    onToggleShopStatus 
}: DashboardHeaderProps) {
    const safeDisplayName = normalizeDisplayName(displayName, role === 'shopkeeper' ? 'Shopkeeper' : 'Customer');
    const [showProfileMenu, setShowProfileMenu] = useState(false);
    const [walletBalance, setWalletBalance] = useState<number | null>(null);
    const [walletLoading, setWalletLoading] = useState(false);
    const router = useRouter();
    const pathname = usePathname();
    const searchParams = useSearchParams();
    const view = searchParams?.get('view') || '';

    const isCustomer = role === 'customer';
    const isShopkeeper = role === 'shopkeeper';

    useEffect(() => {
        if (role !== 'customer') return;
        let cancelled = false;
        setWalletLoading(true);
        getWalletBalance()
            .then((data) => { if (!cancelled) setWalletBalance(data.balance ?? 0); })
            .catch(() => { if (!cancelled) setWalletBalance(null); })
            .finally(() => { if (!cancelled) setWalletLoading(false); });
        return () => { cancelled = true; };
    }, [role]);

    const handleLogout = () => {
        setShowProfileMenu(false);
        onLogout();
    };

    return (
        <header className="sticky top-0 z-50 bg-gradient-to-br from-indigo-900/95 via-purple-900/95 to-pink-800/95 backdrop-blur-lg border-b border-white/10 shadow-lg">
            <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
                <div className="flex items-center justify-between h-16 md:h-20">
                    {/* Brand */}
                    <Link href="/" className="flex items-center group">
                        <span className="text-xl md:text-2xl font-black text-white group-hover:text-pink-400 transition-colors">
                            Q<span className="text-pink-400">print</span>
                        </span>
                    </Link>

                    {/* Navigation Links */}
                    <nav className="hidden md:flex items-center space-x-6">
                        <a 
                            href={isCustomer ? '/customer/dashboard' : '/shopkeeper/dashboard'}
                            onClick={(e) => handleNavigation(e, isCustomer ? '/customer/dashboard' : '/shopkeeper/dashboard', router)}
                            className={`text-sm font-medium transition-colors cursor-pointer ${
                                isShopkeeper
                                    ? (pathname?.includes('/dashboard') && !['history', 'stats', 'profile', 'payouts'].includes(view))
                                    : (pathname?.includes('/dashboard') && !pathname?.includes('/history') && !pathname?.includes('/stats') && !pathname?.includes('/profile'))
                                    ? 'text-pink-400' 
                                    : 'text-white/80 hover:text-pink-400'
                            }`}
                        >
                            Dashboard
                        </a>
                        {isCustomer && (
                            <>
                                <a 
                                    href="/customer/dashboard?view=history"
                                    onClick={(e) => handleNavigation(e, '/customer/dashboard?view=history', router)}
                                    className={`text-sm font-medium transition-colors cursor-pointer ${
                                        pathname?.includes('history')
                                            ? 'text-pink-400' 
                                            : 'text-white/80 hover:text-pink-400'
                                    }`}
                                >
                                    My Files
                                </a>
                                <a 
                                    href="/customer/dashboard?view=expenses"
                                    onClick={(e) => handleNavigation(e, '/customer/dashboard?view=expenses', router)}
                                    className={`text-sm font-medium transition-colors cursor-pointer ${
                                        pathname?.includes('expenses')
                                            ? 'text-pink-400' 
                                            : 'text-white/80 hover:text-pink-400'
                                    }`}
                                >
                                    Expenses
                                </a>
                                <a 
                                    href="/customer/dashboard?view=favorites"
                                    onClick={(e) => handleNavigation(e, '/customer/dashboard?view=favorites', router)}
                                    className={`text-sm font-medium transition-colors cursor-pointer ${
                                        pathname?.includes('favorites')
                                            ? 'text-pink-400' 
                                            : 'text-white/80 hover:text-pink-400'
                                    }`}
                                >
                                    Favorites
                                </a>
                                <a 
                                    href="/customer/wallet"
                                    onClick={(e) => { e.preventDefault(); router.push('/customer/wallet'); }}
                                    className={`text-sm font-medium transition-colors cursor-pointer ${
                                        pathname?.includes('/wallet')
                                            ? 'text-pink-400' 
                                            : 'text-white/80 hover:text-pink-400'
                                    }`}
                                >
                                    Wallet
                                </a>
                                <a 
                                    href="/customer/refer"
                                    onClick={(e) => { e.preventDefault(); router.push('/customer/refer'); }}
                                    className={`text-sm font-medium transition-colors cursor-pointer ${
                                        pathname?.includes('/refer')
                                            ? 'text-pink-400' 
                                            : 'text-white/80 hover:text-pink-400'
                                    }`}
                                >
                                    Refer & Earn
                                </a>
                                <Link
                                    href="/download-apps"
                                    className={`text-sm font-medium transition-colors ${
                                        pathname === '/download-apps' ? 'text-pink-400' : 'text-white/80 hover:text-pink-400'
                                    }`}
                                >
                                    Download Apps
                                </Link>
                                                            </>
                                                        )}
                        {isShopkeeper && (
                            <>
                                <a 
                                    href="/shopkeeper/dashboard?view=history"
                                    onClick={(e) => handleNavigation(e, '/shopkeeper/dashboard?view=history', router)}
                                    className={`text-sm font-medium transition-colors cursor-pointer ${view === 'history' ? 'text-pink-400' : 'text-white/80 hover:text-pink-400'}`}
                                >
                                    History
                                </a>
                                <a 
                                    href="/shopkeeper/dashboard?view=stats"
                                    onClick={(e) => handleNavigation(e, '/shopkeeper/dashboard?view=stats', router)}
                                    className={`text-sm font-medium transition-colors cursor-pointer ${view === 'stats' ? 'text-pink-400' : 'text-white/80 hover:text-pink-400'}`}
                                >
                                    Stats
                                </a>
                                <a 
                                    href="/shopkeeper/dashboard?view=payouts"
                                    onClick={(e) => handleNavigation(e, '/shopkeeper/dashboard?view=payouts', router)}
                                    className={`text-sm font-medium transition-colors cursor-pointer ${view === 'payouts' ? 'text-pink-400' : 'text-white/80 hover:text-pink-400'}`}
                                >
                                    Payouts
                                </a>
                                <a 
                                    href="/shopkeeper/dashboard?view=profile"
                                    onClick={(e) => handleNavigation(e, '/shopkeeper/dashboard?view=profile', router)}
                                    className={`text-sm font-medium transition-colors cursor-pointer ${view === 'profile' ? 'text-pink-400' : 'text-white/80 hover:text-pink-400'}`}
                                >
                                    Profile
                                </a>
                                <Link
                                    href="/download-apps"
                                    className={`text-sm font-medium transition-colors ${
                                        pathname === '/download-apps' ? 'text-pink-400' : 'text-white/80 hover:text-pink-400'
                                    }`}
                                >
                                    Download Apps
                                </Link>
                            </>
                        )}
                    </nav>

                    {/* Right Side - Wallet (Customer) / Shop Status (Shopkeeper) + User Menu */}
                    <div className="flex items-center space-x-4">
                        {/* Wallet balance (Customer only) */}
                        {isCustomer && (
                            <Link
                                href="/customer/wallet"
                                className="hidden md:flex items-center gap-2 px-3 py-2 rounded-lg bg-white/10 border border-white/20 hover:bg-white/20 transition-colors text-white text-sm font-medium"
                            >
                                <span className="text-pink-300">Wallet</span>
                                <span>{walletLoading ? '…' : `₹${(walletBalance ?? 0).toFixed(2)}`}</span>
                            </Link>
                        )}
                        {/* Shop Status Toggle (Shopkeeper only) */}
                        {isShopkeeper && onToggleShopStatus && (
                            <div className="hidden md:flex items-center gap-3 bg-white/10 backdrop-blur-lg px-4 py-2 rounded-full border border-white/20">
                                <span className="text-sm text-white/80">Shop</span>
                                <button
                                    onClick={onToggleShopStatus}
                                    className={`w-12 h-6 rounded-full p-1 transition-colors duration-300 ${
                                        shopStatus ? 'bg-green-500' : 'bg-red-500/50'
                                    }`}
                                >
                                    <div
                                        className={`w-4 h-4 rounded-full bg-white shadow-md transform transition-transform duration-300 ${
                                            shopStatus ? 'translate-x-6' : 'translate-x-0'
                                        }`}
                                    />
                                </button>
                                <span className={`text-sm font-medium ${shopStatus ? 'text-green-400' : 'text-red-400'}`}>
                                    {shopStatus ? 'OPEN' : 'CLOSED'}
                                </span>
                            </div>
                        )}

                        {/* User Profile Menu */}
                        <div className="relative">
                            <button
                                onClick={() => setShowProfileMenu(!showProfileMenu)}
                                className="flex items-center gap-3 bg-white/10 backdrop-blur-lg px-4 py-2 rounded-full border border-white/20 hover:bg-white/20 transition-all duration-300"
                            >
                                <div className="w-10 h-10 bg-gradient-to-br from-pink-500 to-purple-600 rounded-full flex items-center justify-center text-white font-bold text-lg">
                                    {safeDisplayName[0]?.toUpperCase() || 'U'}
                                </div>
                                <span className="hidden md:block text-white font-medium text-sm">{safeDisplayName}</span>
                                <svg className="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                                </svg>
                            </button>

                            {showProfileMenu && (
                                <div className="absolute right-0 mt-2 w-56 bg-white/10 backdrop-blur-xl border border-white/20 rounded-xl shadow-2xl overflow-hidden z-50">
                                    <div className="p-2 space-y-1">
                                        <div className="px-4 py-2 text-xs text-white/60 uppercase tracking-wider">
                                            {isCustomer ? 'Customer' : 'Shopkeeper'} Account
                                        </div>
                                        {isCustomer && (
                                            <>
                                                <a
                                                    href="/customer/dashboard?view=expenses"
                                                    onClick={(e) => {
                                                        e.preventDefault();
                                                        setShowProfileMenu(false);
                                                        router.push('/customer/dashboard?view=expenses');
                                                    }}
                                                    className="w-full text-left px-4 py-3 text-white hover:bg-white/10 rounded-lg transition-colors flex items-center gap-3 cursor-pointer"
                                                >
                                                    <span>💸</span> Expense Tracker
                                                </a>
                                                <a
                                                    href="/customer/dashboard?view=history"
                                                    onClick={(e) => {
                                                        e.preventDefault();
                                                        setShowProfileMenu(false);
                                                        router.push('/customer/dashboard?view=history');
                                                    }}
                                                    className="w-full text-left px-4 py-3 text-white hover:bg-white/10 rounded-lg transition-colors flex items-center gap-3 cursor-pointer"
                                                >
                                                    <span>📂</span> File History
                                                </a>
                                                <a
                                                    href="/customer/dashboard?view=favorites"
                                                    onClick={(e) => {
                                                        e.preventDefault();
                                                        setShowProfileMenu(false);
                                                        router.push('/customer/dashboard?view=favorites');
                                                    }}
                                                    className="w-full text-left px-4 py-3 text-white hover:bg-white/10 rounded-lg transition-colors flex items-center gap-3 cursor-pointer"
                                                >
                                                    <span>⭐</span> Favorite Shops
                                                </a>
                                                <a
                                                    href="/customer/wallet"
                                                    onClick={(e) => {
                                                        e.preventDefault();
                                                        setShowProfileMenu(false);
                                                        router.push('/customer/wallet');
                                                    }}
                                                    className="w-full text-left px-4 py-3 text-white hover:bg-white/10 rounded-lg transition-colors flex items-center gap-3 cursor-pointer"
                                                >
                                                    <span>👛</span> Wallet
                                                </a>
                                                <a
                                                    href="/customer/refer"
                                                    onClick={(e) => {
                                                        e.preventDefault();
                                                        setShowProfileMenu(false);
                                                        router.push('/customer/refer');
                                                    }}
                                                    className="w-full text-left px-4 py-3 text-white hover:bg-white/10 rounded-lg transition-colors flex items-center gap-3 cursor-pointer"
                                                >
                                                    <span>🎁</span> Refer & Earn
                                                </a>
                                            </>
                                        )}
                                        {isShopkeeper && (
                                            <>
                                                <a
                                                    href="/shopkeeper/dashboard?view=dashboard"
                                                    onClick={(e) => {
                                                        e.preventDefault();
                                                        setShowProfileMenu(false);
                                                        router.push('/shopkeeper/dashboard?view=dashboard');
                                                    }}
                                                    className="w-full text-left px-4 py-3 text-white hover:bg-white/10 rounded-lg transition-colors flex items-center gap-3 cursor-pointer"
                                                >
                                                    <span>📊</span> Dashboard & Queue
                                                </a>
                                                <a
                                                    href="/shopkeeper/dashboard?view=history"
                                                    onClick={(e) => {
                                                        e.preventDefault();
                                                        setShowProfileMenu(false);
                                                        router.push('/shopkeeper/dashboard?view=history');
                                                    }}
                                                    className="w-full text-left px-4 py-3 text-white hover:bg-white/10 rounded-lg transition-colors flex items-center gap-3 cursor-pointer"
                                                >
                                                    <span>📜</span> Print History
                                                </a>
                                                <a
                                                    href="/shopkeeper/dashboard?view=stats"
                                                    onClick={(e) => {
                                                        e.preventDefault();
                                                        setShowProfileMenu(false);
                                                        router.push('/shopkeeper/dashboard?view=stats');
                                                    }}
                                                    className="w-full text-left px-4 py-3 text-white hover:bg-white/10 rounded-lg transition-colors flex items-center gap-3 cursor-pointer"
                                                >
                                                    <span>📊</span> Stats & Earnings
                                                </a>
                                                <a
                                                    href="/shopkeeper/dashboard?view=profile"
                                                    onClick={(e) => {
                                                        e.preventDefault();
                                                        setShowProfileMenu(false);
                                                        router.push('/shopkeeper/dashboard?view=profile');
                                                    }}
                                                    className="w-full text-left px-4 py-3 text-white hover:bg-white/10 rounded-lg transition-colors flex items-center gap-3 cursor-pointer"
                                                >
                                                    <span>👤</span> Profile
                                                </a>
                                            </>
                                        )}
                                        <div className="h-px bg-white/10 my-1"></div>
                                        <Link
                                            href="/download-apps"
                                            onClick={() => setShowProfileMenu(false)}
                                            className="block w-full text-left px-4 py-3 text-white hover:bg-white/10 rounded-lg transition-colors flex items-center gap-3"
                                        >
                                            <span>📥</span> Download Apps
                                        </Link>
                                        <button
                                            onClick={handleLogout}
                                            className="w-full text-left px-4 py-3 text-red-300 hover:bg-red-500/20 rounded-lg transition-colors flex items-center gap-3"
                                        >
                                            <span>🚪</span> Logout
                                        </button>
                                        {onDeleteAccount && (
                                            <>
                                                <div className="h-px bg-red-500/30 my-1"></div>
                                                <button
                                                    onClick={() => {
                                                        setShowProfileMenu(false);
                                                        onDeleteAccount();
                                                    }}
                                                    className="w-full text-left px-4 py-3 text-red-400 hover:bg-red-500/30 rounded-lg transition-colors flex items-center gap-3"
                                                >
                                                    <span>🗑️</span> Delete Account
                                                </button>
                                            </>
                                        )}
                                    </div>
                                </div>
                            )}
                        </div>
                    </div>
                </div>
            </div>

            {/* Close menu when clicking outside */}
            {showProfileMenu && (
                <div
                    className="fixed inset-0 z-40"
                    onClick={() => setShowProfileMenu(false)}
                />
            )}
        </header>
    );
}

export default function DashboardHeader(props: DashboardHeaderProps) {
    return (
        <Suspense fallback={<DashboardHeaderFallback displayName={props.displayName} />}>
            <DashboardHeaderContent {...props} />
        </Suspense>
    );
}

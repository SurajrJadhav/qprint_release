"use client";

import { useState, useEffect } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import Link from 'next/link';

export default function Header() {
    const [mounted, setMounted] = useState(false);
    const [isLoggedIn, setIsLoggedIn] = useState(false);
    const [userRole, setUserRole] = useState<string | null>(null);
    const [displayName, setDisplayName] = useState<string | null>(null);
    const [showMobileMenu, setShowMobileMenu] = useState(false);
    const [showUserMenu, setShowUserMenu] = useState(false);
    const router = useRouter();
    const pathname = usePathname();

    useEffect(() => {
        setMounted(true);
        // Check authentication status
        const token = localStorage.getItem('token') || sessionStorage.getItem('token');
        const role = localStorage.getItem('role');
        const storedName = (localStorage.getItem('display_name') || localStorage.getItem('username') || '').trim();
        const user = storedName && storedName.toLowerCase() !== 'undefined' && storedName.toLowerCase() !== 'null'
            ? storedName
            : null;
        
        setIsLoggedIn(!!(token || role));
        setUserRole(role);
        setDisplayName(user);
    }, [pathname]);

    const handleLogout = async () => {
        const { logout } = await import('@/lib/api');
        await logout();
        setIsLoggedIn(false);
        setUserRole(null);
        setDisplayName(null);
        router.push('/');
    };

    const scrollToSection = (sectionId: string) => {
        if (pathname === '/') {
            const element = document.getElementById(sectionId);
            if (element) {
                element.scrollIntoView({ behavior: 'smooth' });
                setShowMobileMenu(false);
            }
        } else {
            router.push(`/#${sectionId}`);
        }
    };

    if (!mounted) return null;

    // Don't show header on dashboard/wallet/refer/admin pages (they have their own navigation)
    if (pathname?.startsWith('/customer/dashboard') || pathname?.startsWith('/customer/wallet') || pathname?.startsWith('/customer/refer') || pathname?.startsWith('/shopkeeper/dashboard') || pathname?.startsWith('/admin')) {
        return null;
    }

    return (
        <header className="fixed top-0 left-0 right-0 z-50 bg-gradient-to-br from-indigo-900/95 via-purple-900/95 to-pink-800/95 backdrop-blur-lg border-b border-white/10 shadow-lg">
            <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
                <div className="flex items-center justify-between h-16 md:h-20">
                    {/* Brand */}
                    <Link href="/" className="flex items-center group">
                        <span className="text-xl md:text-2xl font-black text-white group-hover:text-pink-400 transition-colors">
                            Q<span className="text-pink-400">print</span>
                        </span>
                    </Link>

                    {/* Desktop Navigation */}
                    <nav className="hidden md:flex items-center space-x-8">
                        <Link 
                            href="/" 
                            className={`text-sm font-medium transition-colors ${
                                pathname === '/' 
                                    ? 'text-pink-400' 
                                    : 'text-white/80 hover:text-pink-400'
                            }`}
                        >
                            Home
                        </Link>
                        <button
                            onClick={() => scrollToSection('how-it-works')}
                            className="text-sm font-medium text-white/80 hover:text-pink-400 transition-colors"
                        >
                            How It Works
                        </button>
                        <button
                            onClick={() => scrollToSection('features')}
                            className="text-sm font-medium text-white/80 hover:text-pink-400 transition-colors"
                        >
                            Features
                        </button>
                        <Link 
                            href="/contact" 
                            className={`text-sm font-medium transition-colors ${
                                pathname === '/contact' 
                                    ? 'text-pink-400' 
                                    : 'text-white/80 hover:text-pink-400'
                            }`}
                        >
                            Contact
                        </Link>
                        <Link 
                            href="/download-apps" 
                            className={`text-sm font-medium transition-colors ${
                                pathname === '/download-apps' 
                                    ? 'text-pink-400' 
                                    : 'text-white/80 hover:text-pink-400'
                            }`}
                        >
                            Download Apps
                        </Link>
                        {isLoggedIn ? (
                            <Link 
                                href={userRole === 'customer' ? '/customer/dashboard' : '/shopkeeper/dashboard'}
                                className="text-sm font-medium text-white/80 hover:text-pink-400 transition-colors"
                            >
                                Dashboard
                            </Link>
                        ) : (
                            <Link 
                                href="/login"
                                onClick={(e) => {
                                    // Store intended destination - default to customer dashboard
                                    localStorage.setItem('redirectAfterLogin', '/customer/dashboard');
                                }}
                                className="text-sm font-medium text-white/80 hover:text-pink-400 transition-colors"
                            >
                                Dashboard
                            </Link>
                        )}
                    </nav>

                    {/* Auth Buttons / User Menu */}
                    <div className="hidden md:flex items-center space-x-4">
                        {isLoggedIn ? (
                            <div className="relative">
                                <button
                                    onClick={() => setShowUserMenu(!showUserMenu)}
                                    className="flex items-center space-x-2 px-4 py-2 rounded-lg bg-white/10 hover:bg-white/20 transition-colors"
                                >
                                    <div className="w-8 h-8 rounded-full bg-gradient-to-r from-pink-500 to-purple-600 flex items-center justify-center text-white font-bold text-sm">
                                        {displayName?.[0]?.toUpperCase() || 'U'}
                                    </div>
                                    <span className="text-white text-sm font-medium">{displayName || 'User'}</span>
                                    <svg className="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                                    </svg>
                                </button>

                                {showUserMenu && (
                                    <div className="absolute right-0 mt-2 w-56 bg-white/10 backdrop-blur-xl border border-white/20 rounded-xl shadow-2xl overflow-hidden">
                                        <div className="p-2 space-y-1">
                                            <div className="px-4 py-2 text-xs text-white/60 uppercase tracking-wider">
                                                {userRole === 'customer' ? 'Customer' : 'Shopkeeper'} Account
                                            </div>
                                            <Link
                                                href={userRole === 'customer' ? '/customer/dashboard' : '/shopkeeper/dashboard'}
                                                onClick={() => setShowUserMenu(false)}
                                                className="block px-4 py-3 text-white hover:bg-white/10 rounded-lg transition-colors"
                                            >
                                                Dashboard
                                            </Link>
                                            <button
                                                onClick={() => {
                                                    setShowUserMenu(false);
                                                    handleLogout();
                                                }}
                                                className="w-full text-left px-4 py-3 text-red-400 hover:bg-white/10 rounded-lg transition-colors"
                                            >
                                                Logout
                                            </button>
                                        </div>
                                    </div>
                                )}
                            </div>
                        ) : (
                            <>
                                <Link
                                    href="/login"
                                    className="px-4 py-2 text-sm font-medium text-white/80 hover:text-white transition-colors"
                                >
                                    Sign In
                                </Link>
                                <Link
                                    href="/register"
                                    className="px-6 py-2 text-sm font-medium text-white bg-gradient-to-r from-pink-500 to-purple-600 rounded-full hover:from-pink-600 hover:to-purple-700 transition-all shadow-lg hover:shadow-xl"
                                >
                                    Get Started
                                </Link>
                            </>
                        )}
                    </div>

                    {/* Mobile Menu Button */}
                    <button
                        onClick={() => setShowMobileMenu(!showMobileMenu)}
                        className="md:hidden p-2 rounded-lg text-white hover:bg-white/10 transition-colors"
                    >
                        {showMobileMenu ? (
                            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                            </svg>
                        ) : (
                            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
                            </svg>
                        )}
                    </button>
                </div>

                {/* Mobile Menu */}
                {showMobileMenu && (
                    <div className="md:hidden py-4 border-t border-white/10">
                        <nav className="flex flex-col space-y-4">
                            <Link 
                                href="/" 
                                onClick={() => setShowMobileMenu(false)}
                                className={`px-4 py-2 text-base font-medium transition-colors ${
                                    pathname === '/' 
                                        ? 'text-pink-400' 
                                        : 'text-white/80 hover:text-pink-400'
                                }`}
                            >
                                Home
                            </Link>
                            <button
                                onClick={() => scrollToSection('how-it-works')}
                                className="px-4 py-2 text-left text-base font-medium text-white/80 hover:text-pink-400 transition-colors"
                            >
                                How It Works
                            </button>
                            <button
                                onClick={() => scrollToSection('features')}
                                className="px-4 py-2 text-left text-base font-medium text-white/80 hover:text-pink-400 transition-colors"
                            >
                                Features
                            </button>
                            <Link 
                                href="/contact" 
                                onClick={() => setShowMobileMenu(false)}
                                className={`px-4 py-2 text-base font-medium transition-colors ${
                                    pathname === '/contact' 
                                        ? 'text-pink-400' 
                                        : 'text-white/80 hover:text-pink-400'
                                }`}
                            >
                                Contact
                            </Link>
                            <Link 
                                href="/download-apps" 
                                onClick={() => setShowMobileMenu(false)}
                                className={`px-4 py-2 text-base font-medium transition-colors ${
                                    pathname === '/download-apps' 
                                        ? 'text-pink-400' 
                                        : 'text-white/80 hover:text-pink-400'
                                }`}
                            >
                                Download Apps
                            </Link>
                            {isLoggedIn ? (
                                <Link 
                                    href={userRole === 'customer' ? '/customer/dashboard' : '/shopkeeper/dashboard'}
                                    onClick={() => setShowMobileMenu(false)}
                                    className="px-4 py-2 text-base font-medium text-white/80 hover:text-pink-400 transition-colors"
                                >
                                    Dashboard
                                </Link>
                            ) : (
                                <Link 
                                    href="/login"
                                    onClick={(e) => {
                                        setShowMobileMenu(false);
                                        // Store intended destination - default to customer dashboard
                                        localStorage.setItem('redirectAfterLogin', '/customer/dashboard');
                                    }}
                                    className="px-4 py-2 text-base font-medium text-white/80 hover:text-pink-400 transition-colors"
                                >
                                    Dashboard
                                </Link>
                            )}
                            
                            {isLoggedIn ? (
                                <>
                                    <div className="border-t border-white/10 pt-4 mt-4">
                                        <div className="px-4 py-2 text-xs text-white/60 uppercase tracking-wider">
                                            {userRole === 'customer' ? 'Customer' : 'Shopkeeper'}
                                        </div>
                                        <Link
                                            href={userRole === 'customer' ? '/customer/dashboard' : '/shopkeeper/dashboard'}
                                            onClick={() => setShowMobileMenu(false)}
                                            className="block px-4 py-2 text-base font-medium text-white/80 hover:text-pink-400 transition-colors"
                                        >
                                            Dashboard
                                        </Link>
                                        <button
                                            onClick={() => {
                                                setShowMobileMenu(false);
                                                handleLogout();
                                            }}
                                            className="w-full text-left px-4 py-2 text-base font-medium text-red-400 hover:text-red-300 transition-colors"
                                        >
                                            Logout
                                        </button>
                                    </div>
                                </>
                            ) : (
                                <div className="border-t border-white/10 pt-4 mt-4 space-y-2">
                                    <Link
                                        href="/login"
                                        onClick={() => setShowMobileMenu(false)}
                                        className="block px-4 py-2 text-center text-base font-medium text-white/80 hover:text-white transition-colors"
                                    >
                                        Sign In
                                    </Link>
                                    <Link
                                        href="/register"
                                        onClick={() => setShowMobileMenu(false)}
                                        className="block px-4 py-2 text-center text-base font-medium text-white bg-gradient-to-r from-pink-500 to-purple-600 rounded-full hover:from-pink-600 hover:to-purple-700 transition-all"
                                    >
                                        Get Started
                                    </Link>
                                </div>
                            )}
                        </nav>
                    </div>
                )}
            </div>

            {/* Close user menu when clicking outside */}
            {showUserMenu && (
                <div
                    className="fixed inset-0 z-40"
                    onClick={() => setShowUserMenu(false)}
                />
            )}
        </header>
    );
}

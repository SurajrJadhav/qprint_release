"use client";

import { useState, useEffect, Suspense } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import dynamic from 'next/dynamic';
import api, { registerSendOtp, registerVerifyOtp } from '@/lib/api';
import { getSafeErrorMessage } from '@/lib/safeError';
import Link from 'next/link';
import Footer from '@/components/Footer';

// Dynamically import LocationPicker to avoid SSR issues with browser APIs
const LocationPicker = dynamic(() => import('@/components/LocationPicker'), {
    ssr: false,
    loading: () => <div className="fixed inset-0 z-50 bg-black bg-opacity-50 flex items-center justify-center">
        <div className="bg-white rounded-lg p-4">Loading map...</div>
    </div>
});

type Step = 1 | 2 | 3;

function RegisterPageContent() {
    const [step, setStep] = useState<Step>(1);
    const [email, setEmail] = useState('');
    const [otpCode, setOtpCode] = useState('');
    const [signupToken, setSignupToken] = useState('');
    const [verifiedEmail, setVerifiedEmail] = useState('');
    const [fullName, setFullName] = useState('');
    const [phone, setPhone] = useState('');
    const [password, setPassword] = useState('');
    const [confirmPassword, setConfirmPassword] = useState('');
    const [role, setRole] = useState<'customer' | 'shopkeeper'>('customer');
    const [shopName, setShopName] = useState('');
    const [address, setAddress] = useState('');
    const [lat, setLat] = useState(0);
    const [long, setLong] = useState(0);
    const [error, setError] = useState('');
    const [isLoading, setIsLoading] = useState(false);
    const [showLocationPicker, setShowLocationPicker] = useState(false);
    const [referralCode, setReferralCode] = useState('');
    const router = useRouter();
    const searchParams = useSearchParams();

    useEffect(() => {
        const code = searchParams?.get('referral_code')?.trim() ?? '';
        if (code) setReferralCode(code);
        const fromEmail = searchParams?.get('email')?.trim();
        const fromToken = searchParams?.get('signup_token')?.trim();
        if (fromEmail && fromToken) {
            setVerifiedEmail(fromEmail);
            setSignupToken(fromToken);
            setEmail(fromEmail);
            setStep(3);
        }
    }, [searchParams]);

    const handleSendOtp = async (e: React.FormEvent) => {
        e.preventDefault();
        setError('');
        const trimmed = email.trim().toLowerCase();
        if (!trimmed) {
            setError('Email is required');
            return;
        }
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmed)) {
            setError('Invalid email format');
            return;
        }
        setIsLoading(true);
        try {
            await registerSendOtp({ email: trimmed });
            setEmail(trimmed);
            setStep(2);
            setOtpCode('');
        } catch (err: unknown) {
            setError(getSafeErrorMessage(err, 'register'));
        } finally {
            setIsLoading(false);
        }
    };

    const handleVerifyOtp = async (e: React.FormEvent) => {
        e.preventDefault();
        setError('');
        const code = otpCode.trim();
        if (code.length !== 6) {
            setError('Enter the 6-digit code');
            return;
        }
        setIsLoading(true);
        try {
            const res = await registerVerifyOtp({ email, code });
            setSignupToken(res.signup_token);
            setVerifiedEmail(res.email);
            setStep(3);
        } catch (err: unknown) {
            setError(getSafeErrorMessage(err, 'register'));
        } finally {
            setIsLoading(false);
        }
    };

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        setError('');
        setIsLoading(true);
        
        // Validation
        if (!fullName.trim()) {
            setError('Full name is required');
            setIsLoading(false);
            return;
        }
        if (fullName.length < 2 || fullName.length > 50) {
            setError('Full name must be between 2 and 50 characters');
            setIsLoading(false);
            return;
        }
        if (!email.trim()) {
            setError('Email is required');
            setIsLoading(false);
            return;
        }
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
            setError('Invalid email format');
            setIsLoading(false);
            return;
        }
        if (!phone.trim()) {
            setError('Phone number is required');
            setIsLoading(false);
            return;
        }
        const cleanPhone = phone.replace(/\s/g, '');
        if (!/^[0-9]{10}$/.test(cleanPhone)) {
            setError('Phone number must be 10 digits');
            setIsLoading(false);
            return;
        }
        if (password.length < 8) {
            setError('Password must be at least 8 characters');
            setIsLoading(false);
            return;
        }
        if (password !== confirmPassword) {
            setError('Passwords do not match');
            setIsLoading(false);
            return;
        }
        
        // Validate shopkeeper-specific fields
        if (role === 'shopkeeper') {
            if (!shopName.trim()) {
                setError('Shop name is required for shopkeeper registration');
                setIsLoading(false);
                return;
            }
            if (shopName.length < 2 || shopName.length > 100) {
                setError('Shop name must be between 2 and 100 characters');
                setIsLoading(false);
                return;
            }
            if (!address.trim()) {
                setError('Address is required for shopkeeper registration');
                setIsLoading(false);
                return;
            }
            if (lat === 0 && long === 0) {
                setError('Location is required for shopkeeper registration. Please click "Get Current Location" to capture your shop coordinates.');
                setIsLoading(false);
                return;
            }
        }
        
        try {
            const payload: any = {
                full_name: fullName.trim(),
                email: verifiedEmail || email.trim(),
                phone: cleanPhone,
                password,
                role,
                signup_token: signupToken,
            };

            if (role === 'shopkeeper') {
                payload.shop_name = shopName.trim();
                payload.address = address.trim();
                payload.lat = lat;
                payload.long = long;
            }
            if (role === 'customer' && referralCode.trim()) {
                payload.referral_code = referralCode.trim();
            }

            const res = await api.post('/register', payload);
            const data = res.data as { token?: string; role?: string; display_name?: string } | undefined;
            if (data?.token && data?.role) {
                const isHttps = typeof window !== 'undefined' && window.location.protocol === 'https:';
                if (!isHttps) {
                    localStorage.setItem('token', data.token);
                } else {
                    sessionStorage.setItem('token', data.token);
                }
                localStorage.setItem('role', data.role);
                localStorage.setItem('display_name', data.display_name ?? fullName.trim());
                localStorage.removeItem('username');
                if (data.role === 'shopkeeper') router.push('/shopkeeper/dashboard');
                else router.push('/customer/dashboard');
                return;
            }
            router.push('/login?registered=true');
        } catch (err: unknown) {
            console.error('Registration error:', err);
            setError(getSafeErrorMessage(err, 'register'));
        } finally {
            setIsLoading(false);
        }
    };

    const getLocation = () => {
        if (typeof window !== 'undefined' && typeof navigator !== 'undefined' && navigator.geolocation) {
            navigator.geolocation.getCurrentPosition(
                (position) => {
                    setLat(position.coords.latitude);
                    setLong(position.coords.longitude);
                    setError(''); // Clear any previous errors
                },
                (error) => {
                    console.error('Geolocation error:', error);
                    setError('Failed to get location. Please allow location access and try again.');
                }
            );
        } else {
            setError('Geolocation is not supported by your browser.');
        }
    };

    return (
        <div className="flex min-h-screen flex-col items-center justify-center p-6 md:p-24 bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800">
            <div className="w-full max-w-2xl">
                <div className="text-center mb-8">
                    <h1 className="text-5xl font-black text-white mb-2">
                        Q<span className="text-pink-400">print</span>
                    </h1>
                    <p className="text-purple-200">Create your account</p>
                </div>

                <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 md:p-8 border border-white/20">
                    {/* Step 1: Email + Send OTP */}
                    {step === 1 && (
                        <>
                            <div className="mb-6">
                                <label className="block text-white font-semibold mb-3 text-lg">I am a:</label>
                                <div className="grid grid-cols-2 gap-4">
                                    <button
                                        type="button"
                                        onClick={() => setRole('customer')}
                                        className={`p-4 rounded-xl border-2 transition-all duration-300 ${
                                            role === 'customer'
                                                ? 'bg-gradient-to-r from-pink-500 to-purple-600 border-pink-400 shadow-lg scale-105'
                                                : 'bg-white/10 border-white/30 hover:bg-white/20'
                                        }`}
                                    >
                                        <div className="text-white font-bold text-lg mb-1">👤 Customer</div>
                                        <div className="text-purple-200 text-sm">Print documents</div>
                                    </button>
                                    <button
                                        type="button"
                                        onClick={() => setRole('shopkeeper')}
                                        className={`p-4 rounded-xl border-2 transition-all duration-300 ${
                                            role === 'shopkeeper'
                                                ? 'bg-gradient-to-r from-pink-500 to-purple-600 border-pink-400 shadow-lg scale-105'
                                                : 'bg-white/10 border-white/30 hover:bg-white/20'
                                        }`}
                                    >
                                        <div className="text-white font-bold text-lg mb-1">🏪 Shopkeeper</div>
                                        <div className="text-purple-200 text-sm">Run a print shop</div>
                                    </button>
                                </div>
                            </div>
                            <form onSubmit={handleSendOtp} className="flex flex-col gap-4">
                                <input
                                    type="email"
                                    placeholder="Email *"
                                    value={email}
                                    onChange={(e) => setEmail(e.target.value)}
                                    className="bg-white/20 border border-white/30 p-3 rounded-lg text-white placeholder-purple-200 focus:outline-none focus:ring-2 focus:ring-pink-500"
                                    required
                                />
                                {error && (
                                    <div className="text-pink-300 bg-red-500/20 p-3 rounded-lg border border-red-500/30">{error}</div>
                                )}
                                <button
                                    type="submit"
                                    disabled={isLoading}
                                    className="bg-gradient-to-r from-pink-500 to-purple-600 text-white font-bold p-3 rounded-lg hover:from-pink-600 hover:to-purple-700 transition-all duration-300 shadow-lg disabled:opacity-50"
                                >
                                    {isLoading ? 'Sending code...' : 'Send verification code'}
                                </button>
                            </form>
                        </>
                    )}

                    {/* Step 2: Enter OTP */}
                    {step === 2 && (
                        <form onSubmit={handleVerifyOtp} className="flex flex-col gap-4">
                            <p className="text-purple-200">
                                We sent a 6-digit code to <strong className="text-white">{email}</strong>. Enter it below.
                            </p>
                            <input
                                type="text"
                                inputMode="numeric"
                                autoComplete="one-time-code"
                                placeholder="000000"
                                value={otpCode}
                                onChange={(e) => setOtpCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
                                maxLength={6}
                                className="bg-white/20 border border-white/30 p-3 rounded-lg text-white placeholder-purple-200 focus:outline-none focus:ring-2 focus:ring-pink-500 text-center text-2xl tracking-widest"
                            />
                            {error && (
                                <div className="text-pink-300 bg-red-500/20 p-3 rounded-lg border border-red-500/30">{error}</div>
                            )}
                            <button
                                type="submit"
                                disabled={isLoading || otpCode.length !== 6}
                                className="bg-gradient-to-r from-pink-500 to-purple-600 text-white font-bold p-3 rounded-lg hover:from-pink-600 hover:to-purple-700 transition-all duration-300 shadow-lg disabled:opacity-50"
                            >
                                {isLoading ? 'Verifying...' : 'Verify'}
                            </button>
                            <button
                                type="button"
                                onClick={() => { setStep(1); setError(''); setOtpCode(''); }}
                                className="text-purple-200 hover:text-white text-sm"
                            >
                                Use a different email
                            </button>
                        </form>
                    )}

                    {/* Step 3: Full registration form */}
                    {step === 3 && (
                    <form onSubmit={handleSubmit} className="flex flex-col gap-4">
                        <p className="text-purple-200 text-sm mb-2">
                            Email verified: <strong className="text-white">{verifiedEmail}</strong>
                        </p>
                        {/* Full Name */}
                        <input
                            type="text"
                            placeholder="Full Name *"
                            value={fullName}
                            onChange={(e) => setFullName(e.target.value)}
                            className="bg-white/20 border border-white/30 p-3 rounded-lg text-white placeholder-purple-200 focus:outline-none focus:ring-2 focus:ring-pink-500"
                            required
                        />

                        {/* Email (read-only; verified in step 1) */}
                        <input
                            type="email"
                            placeholder="Email *"
                            value={verifiedEmail}
                            readOnly
                            className="bg-white/10 border border-white/20 p-3 rounded-lg text-purple-200 cursor-not-allowed"
                            required
                        />

                        {/* Phone */}
                        <input
                            type="tel"
                            placeholder="Phone Number (10 digits) *"
                            value={phone}
                            onChange={(e) => setPhone(e.target.value.replace(/\D/g, '').slice(0, 10))}
                            className="bg-white/20 border border-white/30 p-3 rounded-lg text-white placeholder-purple-200 focus:outline-none focus:ring-2 focus:ring-pink-500"
                            required
                        />

                        {/* Password */}
                        <input
                            type="password"
                            placeholder="Password (min 8 characters) *"
                            value={password}
                            onChange={(e) => setPassword(e.target.value)}
                            className="bg-white/20 border border-white/30 p-3 rounded-lg text-white placeholder-purple-200 focus:outline-none focus:ring-2 focus:ring-pink-500"
                            required
                        />

                        {/* Confirm Password */}
                        <input
                            type="password"
                            placeholder="Confirm Password *"
                            value={confirmPassword}
                            onChange={(e) => setConfirmPassword(e.target.value)}
                            className="bg-white/20 border border-white/30 p-3 rounded-lg text-white placeholder-purple-200 focus:outline-none focus:ring-2 focus:ring-pink-500"
                            required
                        />

                        {/* Referral code (customer only, optional) */}
                        {role === 'customer' && (
                            <>
                                {referralCode && (
                                    <p className="text-purple-200 text-sm">Referred by a friend</p>
                                )}
                                <input
                                    type="text"
                                    placeholder="Referral code (optional)"
                                    value={referralCode}
                                    onChange={(e) => setReferralCode(e.target.value)}
                                    className="bg-white/20 border border-white/30 p-3 rounded-lg text-white placeholder-purple-200 focus:outline-none focus:ring-2 focus:ring-pink-500"
                                />
                            </>
                        )}

                        {/* Shopkeeper-specific fields */}
                        {role === 'shopkeeper' && (
                            <>
                                <input
                                    type="text"
                                    placeholder="Shop Name *"
                                    value={shopName}
                                    onChange={(e) => setShopName(e.target.value)}
                                    className="bg-white/20 border border-white/30 p-3 rounded-lg text-white placeholder-purple-200 focus:outline-none focus:ring-2 focus:ring-pink-500"
                                    required
                                />
                                <textarea
                                    placeholder="Shop Address *"
                                    value={address}
                                    onChange={(e) => setAddress(e.target.value)}
                                    rows={3}
                                    className="bg-white/20 border border-white/30 p-3 rounded-lg text-white placeholder-purple-200 focus:outline-none focus:ring-2 focus:ring-pink-500 resize-none"
                                    required
                                />
                                {/* Map-based location picker button */}
                                <button
                                    type="button"
                                    onClick={() => setShowLocationPicker(true)}
                                    className="bg-gradient-to-r from-pink-500 to-purple-600 text-white p-3 rounded-lg hover:from-pink-600 hover:to-purple-700 transition-all duration-300 flex items-center justify-center gap-2 font-semibold shadow-lg"
                                >
                                    🗺️ Set Location on Map *
                                </button>
                                
                                {/* Quick location button (fallback) */}
                                <button
                                    type="button"
                                    onClick={getLocation}
                                    className="bg-white/20 text-white p-3 rounded-lg border border-white/30 hover:bg-white/30 transition-all duration-300 flex items-center justify-center gap-2"
                                >
                                    📍 Quick: Get Current Location
                                </button>
                                
                                {(lat !== 0 || long !== 0) ? (
                                    <div className="text-green-300 text-sm bg-white/10 p-3 rounded-lg border border-green-500/30">
                                        ✓ Location captured: {lat.toFixed(6)}, {long.toFixed(6)}
                                        {address && (
                                            <div className="mt-2 text-xs text-green-200">
                                                {address}
                                            </div>
                                        )}
                                    </div>
                                ) : (
                                    <div className="text-yellow-300 text-sm bg-white/10 p-3 rounded-lg border border-yellow-500/30">
                                        ⚠ Location required - Click "Set Location on Map" above
                                    </div>
                                )}
                            </>
                        )}

                        {error && (
                            <div className="text-pink-300 bg-red-500/20 p-3 rounded-lg border border-red-500/30">
                                {error}
                            </div>
                        )}

                        <button
                            type="submit"
                            disabled={isLoading}
                            className="bg-gradient-to-r from-pink-500 to-purple-600 text-white font-bold p-3 rounded-lg hover:from-pink-600 hover:to-purple-700 transition-all duration-300 shadow-lg hover:shadow-xl disabled:opacity-50 disabled:cursor-not-allowed"
                        >
                            {isLoading ? 'Creating Account...' : 'Create Account'}
                        </button>
                    </form>
                    )}

                    <div className="mt-6 space-y-2">
                        <p className="text-center text-purple-200">
                            Already have an account?{' '}
                            <Link href="/login" className="text-pink-400 hover:text-pink-300 font-semibold">
                                Sign In
                            </Link>
                        </p>
                        <p className="text-center text-purple-200 text-sm">
                            <Link href="/forgot-password" className="text-pink-400 hover:text-pink-300">
                                Forgot Password?
                            </Link>
                            {' | '}
                        </p>
                    </div>
                </div>
            </div>
            <Footer />
            
            {/* Location Picker Modal */}
            {showLocationPicker && (
                <LocationPicker
                    initialLat={lat !== 0 ? lat : undefined}
                    initialLng={long !== 0 ? long : undefined}
                    onLocationSelect={(selectedLat, selectedLong, selectedAddress) => {
                        setLat(selectedLat);
                        setLong(selectedLong);
                        if (selectedAddress) {
                            setAddress(selectedAddress);
                        }
                        setShowLocationPicker(false);
                    }}
                    onCancel={() => setShowLocationPicker(false)}
                />
            )}
        </div>
    );
}

export default function RegisterPage() {
    return (
        <Suspense fallback={
            <div className="flex min-h-screen flex-col items-center justify-center p-6 md:p-24 bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800">
                <div className="text-white text-lg">Loading...</div>
            </div>
        }>
            <RegisterPageContent />
        </Suspense>
    );
}

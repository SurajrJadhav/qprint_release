"use client";

import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import Script from 'next/script';
import api, { loginRequestOtp, loginVerifyOtp, loginWithGoogle } from '@/lib/api';
import { getSafeErrorMessage } from '@/lib/safeError';
import Link from 'next/link';
import Footer from '@/components/Footer';

type LoginMode = 'password' | 'otp';

declare global {
    interface Window {
        google?: {
            accounts: {
                id: {
                    initialize: (config: {
                        client_id: string;
                        callback: (response: { credential: string }) => void;
                        auto_select?: boolean;
                        cancel_on_tap_outside?: boolean;
                    }) => void;
                    renderButton: (
                        parent: HTMLElement,
                        options: {
                            theme?: string;
                            size?: string;
                            width?: number;
                            text?: string;
                            shape?: string;
                        }
                    ) => void;
                };
            };
        };
    }
}

function setAuthFromResponse(res: { token: string; role: string; display_name: string }) {
    const isHttps = typeof window !== 'undefined' && window.location.protocol === 'https:';
    if (!isHttps) {
        localStorage.setItem('token', res.token);
    } else {
        sessionStorage.setItem('token', res.token);
    }
    localStorage.setItem('role', res.role);
    localStorage.setItem('display_name', res.display_name);
    localStorage.removeItem('username');
}

const googleClientId = process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID || '';

export default function LoginPage() {
    const [mode, setMode] = useState<LoginMode>('password');
    const [login, setLogin] = useState('');
    const [password, setPassword] = useState('');
    const [otpCode, setOtpCode] = useState('');
    const [otpSent, setOtpSent] = useState(false);
    const [error, setError] = useState('');
    const [isLoading, setIsLoading] = useState(false);
    const [gisReady, setGisReady] = useState(false);
    const googleBtnRef = useRef<HTMLDivElement>(null);
    const router = useRouter();

    const redirectAfterLogin = (role: string) => {
        const redirectTo = localStorage.getItem('redirectAfterLogin');
        if (redirectTo) {
            localStorage.removeItem('redirectAfterLogin');
            router.push(redirectTo);
            return;
        }
        if (role === 'admin') {
            alert('Admin accounts should login at http://localhost:3001');
            return;
        }
        if (role === 'shopkeeper') router.push('/shopkeeper/dashboard');
        else router.push('/customer/dashboard');
    };

    const handleGoogleCredential = async (credential: string) => {
        setError('');
        setIsLoading(true);
        try {
            const res = await loginWithGoogle(credential, 'customer');
            if ('needs_signup' in res && res.needs_signup) {
                const q = new URLSearchParams({
                    email: res.email,
                    signup_token: res.signup_token,
                });
                if (res.full_name) q.set('full_name', res.full_name);
                router.push(`/register?${q.toString()}`);
                return;
            }
            setAuthFromResponse(res);
            redirectAfterLogin(res.role);
        } catch (err: unknown) {
            setError(getSafeErrorMessage(err, 'auth'));
        } finally {
            setIsLoading(false);
        }
    };

    useEffect(() => {
        if (!gisReady || !googleClientId || !googleBtnRef.current || !window.google) return;
        window.google.accounts.id.initialize({
            client_id: googleClientId,
            callback: (response) => {
                if (response?.credential) void handleGoogleCredential(response.credential);
            },
            auto_select: false,
            cancel_on_tap_outside: true,
        });
        googleBtnRef.current.innerHTML = '';
        window.google.accounts.id.renderButton(googleBtnRef.current, {
            theme: 'outline',
            size: 'large',
            width: 320,
            text: 'continue_with',
            shape: 'rectangular',
        });
        // eslint-disable-next-line react-hooks/exhaustive-deps -- initialize once GIS is ready
    }, [gisReady, googleClientId]);

    const handlePasswordSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        setError('');
        setIsLoading(true);
        try {
            const res = await api.post('/login', { login, password });
            setAuthFromResponse(res.data);
            redirectAfterLogin(res.data.role);
        } catch (err: unknown) {
            setError(getSafeErrorMessage(err, 'auth'));
        } finally {
            setIsLoading(false);
        }
    };

    const handleSendOtp = async (e: React.FormEvent) => {
        e.preventDefault();
        setError('');
        if (!login.trim()) {
            setError('Enter your email');
            return;
        }
        setIsLoading(true);
        try {
            await loginRequestOtp(login);
            setOtpSent(true);
            setOtpCode('');
        } catch (err: unknown) {
            setError(getSafeErrorMessage(err, 'auth'));
        } finally {
            setIsLoading(false);
        }
    };

    const handleVerifyOtp = async (e: React.FormEvent) => {
        e.preventDefault();
        setError('');
        if (otpCode.trim().length !== 6) {
            setError('Enter the 6-digit code');
            return;
        }
        setIsLoading(true);
        try {
            const res = await loginVerifyOtp(login, otpCode);
            if ('needs_signup' in res && res.needs_signup) {
                router.push(`/register?email=${encodeURIComponent(res.email)}&signup_token=${encodeURIComponent(res.signup_token)}`);
                return;
            }
            const loginRes = res as { token: string; role: string; display_name: string };
            setAuthFromResponse(loginRes);
            redirectAfterLogin(loginRes.role);
        } catch (err: unknown) {
            setError(getSafeErrorMessage(err, 'auth'));
        } finally {
            setIsLoading(false);
        }
    };

    return (
        <div className="flex min-h-screen flex-col items-center justify-center p-24 bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800">
            {googleClientId ? (
                <Script
                    src="https://accounts.google.com/gsi/client"
                    strategy="afterInteractive"
                    onLoad={() => setGisReady(true)}
                />
            ) : null}
            <div className="w-full max-w-md">
                <div className="text-center mb-8">
                    <h1 className="text-5xl font-black text-white mb-2">
                        Q<span className="text-pink-400">print</span>
                    </h1>
                    <p className="text-purple-200">Sign in to your account</p>
                </div>

                <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-8 border border-white/20">
                    <div className="flex rounded-lg bg-white/10 p-1 mb-4">
                        <button
                            type="button"
                            onClick={() => { setMode('password'); setError(''); setOtpSent(false); }}
                            className={`flex-1 py-2 rounded-md text-sm font-medium transition ${mode === 'password' ? 'bg-white/20 text-white' : 'text-purple-200'}`}
                        >
                            Password
                        </button>
                        <button
                            type="button"
                            onClick={() => { setMode('otp'); setError(''); setOtpSent(false); }}
                            className={`flex-1 py-2 rounded-md text-sm font-medium transition ${mode === 'otp' ? 'bg-white/20 text-white' : 'text-purple-200'}`}
                        >
                            OTP (Email)
                        </button>
                    </div>

                    {mode === 'password' ? (
                        <form onSubmit={handlePasswordSubmit} className="flex flex-col gap-4">
                            <input
                                type="text"
                                placeholder="Email or mobile number"
                                value={login}
                                onChange={(e) => setLogin(e.target.value)}
                                className="bg-white/20 border border-white/30 p-3 rounded-lg text-white placeholder-purple-200 focus:outline-none focus:ring-2 focus:ring-pink-500"
                                required
                            />
                            <input
                                type="password"
                                placeholder="Password"
                                value={password}
                                onChange={(e) => setPassword(e.target.value)}
                                className="bg-white/20 border border-white/30 p-3 rounded-lg text-white placeholder-purple-200 focus:outline-none focus:ring-2 focus:ring-pink-500"
                                required
                            />
                            {error && <p className="text-pink-300 bg-red-500/20 p-3 rounded-lg">{error}</p>}
                            <button
                                type="submit"
                                disabled={isLoading}
                                className="bg-gradient-to-r from-pink-500 to-purple-600 text-white font-bold p-3 rounded-lg hover:from-pink-600 hover:to-purple-700 transition-all duration-300 shadow-lg hover:shadow-xl disabled:opacity-70"
                            >
                                Sign In
                            </button>
                        </form>
                    ) : (
                        <>
                            {!otpSent ? (
                                <form onSubmit={handleSendOtp} className="flex flex-col gap-4">
                                    <input
                                        type="text"
                                        placeholder="Email"
                                        value={login}
                                        onChange={(e) => setLogin(e.target.value)}
                                        className="bg-white/20 border border-white/30 p-3 rounded-lg text-white placeholder-purple-200 focus:outline-none focus:ring-2 focus:ring-pink-500"
                                    />
                                    {error && <p className="text-pink-300 bg-red-500/20 p-3 rounded-lg">{error}</p>}
                                    <button
                                        type="submit"
                                        disabled={isLoading}
                                        className="bg-gradient-to-r from-pink-500 to-purple-600 text-white font-bold p-3 rounded-lg hover:from-pink-600 hover:to-purple-700 transition-all duration-300 disabled:opacity-70"
                                    >
                                        Send OTP
                                    </button>
                                </form>
                            ) : (
                                <form onSubmit={handleVerifyOtp} className="flex flex-col gap-4">
                                    <p className="text-purple-200 text-sm">Code sent to {login}</p>
                                    <input
                                        type="text"
                                        placeholder="6-digit code"
                                        value={otpCode}
                                        onChange={(e) => setOtpCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
                                        maxLength={6}
                                        className="bg-white/20 border border-white/30 p-3 rounded-lg text-white placeholder-purple-200 focus:outline-none focus:ring-2 focus:ring-pink-500"
                                    />
                                    {error && <p className="text-pink-300 bg-red-500/20 p-3 rounded-lg">{error}</p>}
                                    <div className="flex gap-2">
                                        <button
                                            type="button"
                                            onClick={() => { setOtpSent(false); setError(''); }}
                                            className="flex-1 py-3 rounded-lg border border-white/30 text-white"
                                        >
                                            Change
                                        </button>
                                        <button
                                            type="submit"
                                            disabled={isLoading || otpCode.length !== 6}
                                            className="flex-1 bg-gradient-to-r from-pink-500 to-purple-600 text-white font-bold p-3 rounded-lg hover:from-pink-600 hover:to-purple-700 transition-all duration-300 disabled:opacity-70"
                                        >
                                            Verify & Sign In
                                        </button>
                                    </div>
                                </form>
                            )}
                        </>
                    )}

                    {googleClientId ? (
                        <div className="mt-6">
                            <div className="flex items-center gap-3 mb-4">
                                <div className="flex-1 h-px bg-white/20" />
                                <span className="text-purple-200 text-sm">or</span>
                                <div className="flex-1 h-px bg-white/20" />
                            </div>
                            <div className="flex justify-center" ref={googleBtnRef} />
                            {mode === 'otp' && error ? (
                                <p className="text-pink-300 bg-red-500/20 p-3 rounded-lg mt-3">{error}</p>
                            ) : null}
                        </div>
                    ) : null}

                    <div className="mt-6 space-y-2">
                        <p className="text-center text-purple-200">
                            Don&apos;t have an account?{' '}
                            <Link href="/register" className="text-pink-400 hover:text-pink-300 font-semibold">
                                Register
                            </Link>
                        </p>
                        {mode === 'password' && (
                            <p className="text-center text-purple-200 text-sm">
                                <Link href="/forgot-password" className="text-pink-400 hover:text-pink-300">
                                    Forgot Password?
                                </Link>
                            </p>
                        )}
                    </div>
                </div>
            </div>
            <Footer />
        </div>
    );
}

"use client";

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import api, { fetchCsrfToken } from '@/lib/api';

type Step = 'password' | '2fa' | 'otp_email' | 'otp_code';

export default function AdminLoginPage() {
    const [login, setLogin] = useState('');
    const [password, setPassword] = useState('');
    const [code, setCode] = useState('');
    const [step, setStep] = useState<Step>('password');
    const [tempToken, setTempToken] = useState('');
    const [accountLabel, setAccountLabel] = useState('');
    const [otpEmail, setOtpEmail] = useState('');
    const [error, setError] = useState('');
    const [loading, setLoading] = useState(false);
    const router = useRouter();

    // Fetch CSRF token on load so login/OTP requests send the header when a cookie is present (avoids 403)
    useEffect(() => {
        fetchCsrfToken();
    }, []);

    const handlePasswordSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        setError('');
        setLoading(true);
        try {
            const res = await api.post('/login', { login, password });

            if (res.data.requires_2fa && res.data.temp_token) {
                setTempToken(res.data.temp_token);
                setAccountLabel(res.data.display_name || '');
                setStep('2fa');
                setCode('');
                setLoading(false);
                return;
            }

            if (res.data.role !== 'admin') {
                setError('Access denied. Admin account required.');
                setLoading(false);
                return;
            }

            localStorage.setItem('token', res.data.token);
            localStorage.setItem('role', res.data.role);
            localStorage.setItem('display_name', res.data.display_name ?? '');
            localStorage.removeItem('username');
            router.push('/dashboard');
        } catch (err: any) {
            console.error('Login error:', err);
            if (err.response) {
                if (err.response.status === 401 || err.response.status === 403) {
                    setError('Invalid credentials or access denied.');
                } else {
                    setError(typeof err.response.data === 'string' ? err.response.data : (err.response.data?.error || 'Something went wrong. Try again.'));
                }
            } else if (err.request) {
                setError('Cannot connect to server. Server offline.');
            } else {
                setError('Login failed. Try again.');
            }
            setLoading(false);
        }
    };

    const handle2FASubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        setError('');
        setLoading(true);
        try {
            const res = await api.post('/login/verify-2fa', { temp_token: tempToken, code: code.trim() });

            if (res.data.role !== 'admin') {
                setError('Access denied. Admin account required.');
                setLoading(false);
                return;
            }

            localStorage.setItem('token', res.data.token);
            localStorage.setItem('role', res.data.role);
            localStorage.setItem('display_name', res.data.display_name ?? '');
            localStorage.removeItem('username');
            router.push('/dashboard');
        } catch (err: any) {
            console.error('Verify 2FA error:', err);
            if (err.response) {
                if (err.response.status === 401) {
                    setError(err.response.data && typeof err.response.data === 'string' ? err.response.data : 'Invalid verification code.');
                } else {
                    setError(err.response.data?.error || err.response.data || 'Verification failed. Try again.');
                }
            } else {
                setError('Verification failed. Try again.');
            }
            setLoading(false);
        }
    };

    const backToPassword = () => {
        setStep('password');
        setTempToken('');
        setCode('');
        setError('');
        setOtpEmail('');
    };

    const handleRequestOTP = async (e: React.FormEvent) => {
        e.preventDefault();
        setError('');
        setLoading(true);
        try {
            await api.post('/admin/login/request-otp', { email: otpEmail.trim() });
            setStep('otp_code');
            setCode('');
        } catch (err: any) {
            setError(err.response?.data?.error || 'Failed to send code. Try again.');
        }
        setLoading(false);
    };

    const handleVerifyOTP = async (e: React.FormEvent) => {
        e.preventDefault();
        setError('');
        setLoading(true);
        try {
            const res = await api.post('/admin/login/verify-otp', { email: otpEmail.trim(), code: code.trim() });
            if (res.data.role !== 'admin') {
                setError('Access denied. Admin account required.');
                setLoading(false);
                return;
            }
            localStorage.setItem('token', res.data.token);
            localStorage.setItem('role', res.data.role);
            localStorage.setItem('display_name', res.data.display_name ?? '');
            localStorage.removeItem('username');
            router.push('/dashboard');
        } catch (err: any) {
            if (err.response?.status === 401) {
                setError(typeof err.response?.data === 'string' ? err.response.data : 'Invalid or expired code. Request a new code.');
            } else {
                setError(typeof err.response?.data === 'string' ? err.response.data : (err.response?.data?.error || 'Verification failed. Try again.'));
            }
            setLoading(false);
        }
    };

    return (
        <div className="flex min-h-screen flex-col items-center justify-center p-24 bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800">
            <div className="w-full max-w-md">
                <div className="text-center mb-8">
                    <h1 className="text-5xl font-black text-white mb-2">
                        Q<span className="text-pink-400">print</span> <span className="text-yellow-400">Admin</span>
                    </h1>
                    <p className="text-purple-200">Admin Panel Login</p>
                </div>

                <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-8 border border-white/20">
                    {step === 'password' && (
                        <>
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
                                    disabled={loading}
                                    className="bg-gradient-to-r from-pink-500 to-purple-600 text-white font-bold p-3 rounded-lg hover:from-pink-600 hover:to-purple-700 transition-all duration-300 shadow-lg hover:shadow-xl disabled:opacity-50"
                                >
                                    {loading ? 'Signing in…' : 'Sign In'}
                                </button>
                            </form>
                            <p className="text-center text-purple-200 text-sm mt-4">
                                Or{' '}
                                <button type="button" onClick={() => { setStep('otp_email'); setError(''); setOtpEmail(''); }} className="underline hover:text-white">
                                    sign in with email OTP
                                </button>
                            </p>
                        </>
                    )}
                    {step === 'otp_email' && (
                        <form onSubmit={handleRequestOTP} className="flex flex-col gap-4">
                            <p className="text-purple-200 text-sm">Enter your admin account email. We’ll send a one-time code.</p>
                            <input
                                type="email"
                                placeholder="Admin email"
                                value={otpEmail}
                                onChange={(e) => setOtpEmail(e.target.value)}
                                className="bg-white/20 border border-white/30 p-3 rounded-lg text-white placeholder-purple-200 focus:outline-none focus:ring-2 focus:ring-pink-500"
                                required
                            />
                            {error && <p className="text-pink-300 bg-red-500/20 p-3 rounded-lg">{error}</p>}
                            <button type="submit" disabled={loading} className="bg-gradient-to-r from-pink-500 to-purple-600 text-white font-bold p-3 rounded-lg hover:from-pink-600 hover:to-purple-700 transition-all duration-300 shadow-lg disabled:opacity-50">
                                {loading ? 'Sending…' : 'Send login code'}
                            </button>
                            <button type="button" onClick={backToPassword} className="text-purple-200 hover:text-white text-sm">← Back to password</button>
                        </form>
                    )}
                    {step === 'otp_code' && (
                        <form onSubmit={handleVerifyOTP} className="flex flex-col gap-4">
                            <p className="text-purple-200 text-sm text-center">
                                Enter the 6-digit code we sent to <strong className="text-white">{otpEmail}</strong>
                            </p>
                            <input
                                type="text"
                                inputMode="numeric"
                                autoComplete="one-time-code"
                                placeholder="000000"
                                value={code}
                                onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
                                className="bg-white/20 border border-white/30 p-3 rounded-lg text-white placeholder-purple-200 focus:outline-none focus:ring-2 focus:ring-pink-500 text-center text-2xl tracking-widest"
                                maxLength={6}
                                required
                            />
                            {error && <p className="text-pink-300 bg-red-500/20 p-3 rounded-lg">{error}</p>}
                            <button type="submit" disabled={loading || code.length !== 6} className="bg-gradient-to-r from-pink-500 to-purple-600 text-white font-bold p-3 rounded-lg hover:from-pink-600 hover:to-purple-700 transition-all duration-300 shadow-lg disabled:opacity-50">
                                {loading ? 'Verifying…' : 'Verify & sign in'}
                            </button>
                            <button type="button" onClick={() => { setStep('otp_email'); setCode(''); setError(''); }} className="text-purple-200 hover:text-white text-sm">Use a different email</button>
                            <button type="button" onClick={backToPassword} className="text-purple-200 hover:text-white text-sm">← Back to password</button>
                        </form>
                    )}
                    {step === '2fa' && (
                        <form onSubmit={handle2FASubmit} className="flex flex-col gap-4">
                            <p className="text-purple-200 text-sm text-center">
                                Enter the 6-digit code we sent to your account email{accountLabel ? ` for ${accountLabel}` : ''}.
                            </p>
                            <input
                                type="text"
                                inputMode="numeric"
                                autoComplete="one-time-code"
                                placeholder="000000"
                                value={code}
                                onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
                                className="bg-white/20 border border-white/30 p-3 rounded-lg text-white placeholder-purple-200 focus:outline-none focus:ring-2 focus:ring-pink-500 text-center text-2xl tracking-widest"
                                maxLength={6}
                                required
                            />
                            {error && <p className="text-pink-300 bg-red-500/20 p-3 rounded-lg">{error}</p>}
                            <button
                                type="submit"
                                disabled={loading || code.length !== 6}
                                className="bg-gradient-to-r from-pink-500 to-purple-600 text-white font-bold p-3 rounded-lg hover:from-pink-600 hover:to-purple-700 transition-all duration-300 shadow-lg hover:shadow-xl disabled:opacity-50"
                            >
                                {loading ? 'Verifying…' : 'Verify'}
                            </button>
                            <button
                                type="button"
                                onClick={backToPassword}
                                className="text-purple-200 hover:text-white text-sm"
                            >
                                ← Back to password
                            </button>
                        </form>
                    )}
                </div>
            </div>
        </div>
    );
}

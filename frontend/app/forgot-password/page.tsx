"use client";

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import api from '@/lib/api';
import { getSafeErrorMessage } from '@/lib/safeError';
import Link from 'next/link';
import Footer from '@/components/Footer';

export default function ForgotPasswordPage() {
    const [email, setEmail] = useState('');
    const [error, setError] = useState('');
    const [success, setSuccess] = useState(false);
    const [isLoading, setIsLoading] = useState(false);
    const router = useRouter();

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        setError('');
        setIsLoading(true);

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

        try {
            await api.post('/forgot-password', { email: email.trim() });
            setSuccess(true);
        } catch (err: unknown) {
            console.error('Forgot password error:', err);
            setError(getSafeErrorMessage(err, 'forgot_password'));
        } finally {
            setIsLoading(false);
        }
    };

    return (
        <div className="flex min-h-screen flex-col items-center justify-center p-6 md:p-24 bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800">
            <div className="w-full max-w-md">
                <div className="text-center mb-8">
                    <h1 className="text-5xl font-black text-white mb-2">
                        Q<span className="text-pink-400">print</span>
                    </h1>
                    <p className="text-purple-200">Reset your password</p>
                </div>

                <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 md:p-8 border border-white/20">
                    {!success ? (
                        <>
                            <p className="text-purple-200 mb-6 text-center">
                                Enter your email address and we'll send you a password reset link.
                            </p>
                            <form onSubmit={handleSubmit} className="flex flex-col gap-4">
                                <input
                                    type="email"
                                    placeholder="Email Address *"
                                    value={email}
                                    onChange={(e) => setEmail(e.target.value)}
                                    className="bg-white/20 border border-white/30 p-3 rounded-lg text-white placeholder-purple-200 focus:outline-none focus:ring-2 focus:ring-pink-500"
                                    required
                                />

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
                                    {isLoading ? 'Sending...' : 'Send Reset Link'}
                                </button>
                            </form>
                        </>
                    ) : (
                        <div className="text-center">
                            <div className="text-green-300 text-lg mb-4">
                                ✓ Password reset link sent!
                            </div>
                            <p className="text-purple-200 mb-4">
                                Check your email for the password reset link. The link will expire in 1 hour.
                            </p>
                            <p className="text-purple-300 text-sm mb-4">
                                If you don't see the email, check your spam folder.
                            </p>
                            <Link
                                href="/reset-password"
                                className="text-pink-400 hover:text-pink-300 font-semibold block mb-4"
                            >
                                Go to Reset Password Page
                            </Link>
                            <Link
                                href="/login"
                                className="text-purple-200 hover:text-white"
                            >
                                Back to Login
                            </Link>
                        </div>
                    )}

                    <div className="mt-6 text-center">
                        <Link href="/login" className="text-purple-200 hover:text-white text-sm">
                            ← Back to Login
                        </Link>
                    </div>
                </div>
            </div>
            <Footer />
        </div>
    );
}

"use client";

import { useState, useEffect, Suspense } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import api from '@/lib/api';
import { getSafeErrorMessage } from '@/lib/safeError';
import Link from 'next/link';
import Footer from '@/components/Footer';

function ResetPasswordForm() {
    const [token, setToken] = useState('');
    const [password, setPassword] = useState('');
    const [confirmPassword, setConfirmPassword] = useState('');
    const [error, setError] = useState('');
    const [success, setSuccess] = useState(false);
    const [isLoading, setIsLoading] = useState(false);
    const router = useRouter();
    const searchParams = useSearchParams();

    // Get token from URL if present
    useEffect(() => {
        const urlToken = searchParams.get('token');
        if (urlToken) {
            setToken(urlToken);
        }
    }, [searchParams]);

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        setError('');

        if (!token.trim()) {
            setError('Reset token is required');
            return;
        }

        if (password.length < 8) {
            setError('Password must be at least 8 characters');
            return;
        }

        if (password !== confirmPassword) {
            setError('Passwords do not match');
            return;
        }

        setIsLoading(true);

        try {
            await api.post('/reset-password', {
                token: token.trim(),
                password,
            });
            setSuccess(true);
            setTimeout(() => {
                router.push('/login?passwordReset=true');
            }, 2000);
        } catch (err: unknown) {
            console.error('Reset password error:', err);
            setError(getSafeErrorMessage(err, 'reset_password'));
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
                    <p className="text-purple-200">Set new password</p>
                </div>

                <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 md:p-8 border border-white/20">
                    {!success ? (
                        <>
                            <p className="text-purple-200 mb-6 text-center">
                                Enter your reset token and new password.
                            </p>
                            <form onSubmit={handleSubmit} className="flex flex-col gap-4">
                                <input
                                    type="text"
                                    placeholder="Reset Token *"
                                    value={token}
                                    onChange={(e) => setToken(e.target.value)}
                                    className="bg-white/20 border border-white/30 p-3 rounded-lg text-white placeholder-purple-200 focus:outline-none focus:ring-2 focus:ring-pink-500"
                                    required
                                />
                                <input
                                    type="password"
                                    placeholder="New Password (min 8 characters) *"
                                    value={password}
                                    onChange={(e) => setPassword(e.target.value)}
                                    className="bg-white/20 border border-white/30 p-3 rounded-lg text-white placeholder-purple-200 focus:outline-none focus:ring-2 focus:ring-pink-500"
                                    required
                                />
                                <input
                                    type="password"
                                    placeholder="Confirm New Password *"
                                    value={confirmPassword}
                                    onChange={(e) => setConfirmPassword(e.target.value)}
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
                                    {isLoading ? 'Resetting...' : 'Reset Password'}
                                </button>
                            </form>
                        </>
                    ) : (
                        <div className="text-center">
                            <div className="text-green-300 text-lg mb-4">
                                ✓ Password reset successfully!
                            </div>
                            <p className="text-purple-200">
                                Redirecting to login page...
                            </p>
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

export default function ResetPasswordPage() {
    return (
        <Suspense fallback={
            <div className="flex min-h-screen flex-col items-center justify-center p-6 md:p-24 bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800">
                <div className="w-full max-w-md">
                    <div className="text-center mb-8">
                        <h1 className="text-5xl font-black text-white mb-2">
                            Q<span className="text-pink-400">print</span>
                        </h1>
                        <p className="text-purple-200">Loading...</p>
                    </div>
                </div>
                <Footer />
            </div>
        }>
            <ResetPasswordForm />
        </Suspense>
    );
}

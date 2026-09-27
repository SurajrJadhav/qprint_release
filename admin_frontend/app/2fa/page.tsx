"use client";

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { get2FAStatus, enable2FA, disable2FA } from '@/lib/api';

export default function TwoFAPage() {
    const [status, setStatus] = useState<{ enabled: boolean } | null>(null);
    const [loading, setLoading] = useState(true);
    const [disablePassword, setDisablePassword] = useState('');
    const [message, setMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null);
    const [actionLoading, setActionLoading] = useState(false);
    const router = useRouter();

    useEffect(() => {
        const token = localStorage.getItem('token');
        const role = localStorage.getItem('role');
        if (!token || role !== 'admin') {
            router.push('/login');
            return;
        }
        get2FAStatus()
            .then(setStatus)
            .catch(() => setMessage({ type: 'error', text: 'Failed to load 2FA status' }))
            .finally(() => setLoading(false));
    }, [router]);

    const handleEnable = async () => {
        setMessage(null);
        setActionLoading(true);
        try {
            await enable2FA();
            setMessage({ type: 'success', text: 'Email 2FA enabled. When you sign in, we’ll send a 6-digit code to your account email.' });
            setStatus({ enabled: true });
        } catch (err: any) {
            const msg = err.response?.data || err.response?.data?.message || 'Failed to enable 2FA. Make sure your account has an email set.';
            setMessage({ type: 'error', text: typeof msg === 'string' ? msg : 'Failed to enable 2FA.' });
        } finally {
            setActionLoading(false);
        }
    };

    const handleDisable = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!disablePassword.trim()) {
            setMessage({ type: 'error', text: 'Enter your password to disable 2FA' });
            return;
        }
        setMessage(null);
        setActionLoading(true);
        try {
            await disable2FA(disablePassword);
            setMessage({ type: 'success', text: '2FA disabled successfully.' });
            setDisablePassword('');
            setStatus({ enabled: false });
        } catch (err: any) {
            setMessage({ type: 'error', text: err.response?.data?.message || err.response?.data || 'Failed to disable 2FA.' });
        } finally {
            setActionLoading(false);
        }
    };

    if (loading || status === null) {
        return (
            <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800 flex items-center justify-center">
                <div className="text-white text-xl">Loading…</div>
            </div>
        );
    }

    return (
        <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800">
            <div className="max-w-lg mx-auto px-4 py-8">
                <div className="flex items-center justify-between mb-8">
                    <h1 className="text-3xl font-black text-white">
                        Two-Factor <span className="text-pink-400">Authentication</span>
                    </h1>
                    <Link
                        href="/dashboard"
                        className="px-4 py-2 bg-white/10 hover:bg-white/20 text-white rounded-lg border border-white/20"
                    >
                        ← Dashboard
                    </Link>
                </div>

                <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 border border-white/20 space-y-6">
                    {message && (
                        <div
                            className={`p-4 rounded-xl ${
                                message.type === 'success'
                                    ? 'bg-green-500/20 border border-green-400/50 text-green-200'
                                    : 'bg-red-500/20 border border-red-400/50 text-red-200'
                            }`}
                        >
                            {message.text}
                        </div>
                    )}

                    <p className="text-purple-200">
                        {status.enabled
                            ? 'Two-factor authentication is enabled. When you sign in with your password, we’ll send a 6-digit code to your account email.'
                            : 'Add an extra layer of security: after entering your password, we’ll send a one-time code to your account email. Make sure your profile has an email set.'}
                    </p>

                    {status.enabled ? (
                        <div>
                            <h2 className="text-white font-semibold mb-2">Disable 2FA</h2>
                            <p className="text-purple-200 text-sm mb-3">Enter your password to turn off email 2FA.</p>
                            <form onSubmit={handleDisable} className="space-y-3">
                                <input
                                    type="password"
                                    placeholder="Your password"
                                    value={disablePassword}
                                    onChange={(e) => setDisablePassword(e.target.value)}
                                    className="w-full px-4 py-3 rounded-xl bg-white/10 border border-white/20 text-white placeholder-purple-300 focus:ring-2 focus:ring-pink-500"
                                />
                                <button
                                    type="submit"
                                    disabled={actionLoading}
                                    className="px-4 py-2 bg-red-500/20 hover:bg-red-500/30 text-white rounded-lg border border-red-400/50 disabled:opacity-50"
                                >
                                    {actionLoading ? 'Disabling…' : 'Disable 2FA'}
                                </button>
                            </form>
                        </div>
                    ) : (
                        <button
                            type="button"
                            onClick={handleEnable}
                            disabled={actionLoading}
                            className="px-6 py-3 bg-gradient-to-r from-pink-500 to-purple-600 text-white font-bold rounded-xl hover:from-pink-600 hover:to-purple-700 disabled:opacity-50"
                        >
                            {actionLoading ? 'Enabling…' : 'Enable email 2FA'}
                        </button>
                    )}
                </div>
            </div>
        </div>
    );
}

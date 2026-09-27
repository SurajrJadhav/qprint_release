"use client";

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import api from '@/lib/api';
import { fetchCsrfToken } from '@/lib/api';

export default function AdminNotificationsPage() {
    const [title, setTitle] = useState('');
    const [body, setBody] = useState('');
    const [sending, setSending] = useState(false);
    const [message, setMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null);
    const [recipients, setRecipients] = useState<number | null>(null);
    const router = useRouter();

    useEffect(() => {
        const token = localStorage.getItem('token');
        const role = localStorage.getItem('role');
        if (!token || role !== 'admin') {
            router.push('/login');
            return;
        }
    }, [router]);

    const handleSend = async (e: React.FormEvent) => {
        e.preventDefault();
        const t = title.trim();
        if (!t) {
            setMessage({ type: 'error', text: 'Title is required.' });
            return;
        }
        setMessage(null);
        setSending(true);
        try {
            await fetchCsrfToken();
            const res = await api.post<{ message: string; recipients: number }>('/admin/notifications/send', {
                title: t,
                body: body.trim() || t,
            });
            setMessage({ type: 'success', text: `Notification sent to ${res.data?.recipients ?? 0} customer(s).` });
            setTitle('');
            setBody('');
        } catch (err: any) {
            let text = 'Failed to send.';
            if (err.response?.data?.message) text = err.response.data.message;
            else if (err.response?.status === 401) {
                router.push('/login');
                return;
            }
            setMessage({ type: 'error', text });
        } finally {
            setSending(false);
        }
    };

    return (
        <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800">
            <div className="container mx-auto px-4 py-8">
                <div className="flex justify-between items-center mb-8">
                    <div>
                        <h1 className="text-4xl font-black text-white mb-2">
                            Send <span className="text-pink-400">Notification</span>
                        </h1>
                        <p className="text-purple-200">Push notification to all customer app users (Android/iOS)</p>
                    </div>
                    <Link
                        href="/dashboard"
                        className="bg-white/10 hover:bg-white/20 text-white px-4 py-2 rounded-lg border border-white/20"
                    >
                        ← Dashboard
                    </Link>
                </div>

                <div className="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20 max-w-xl">
                    <form onSubmit={handleSend} className="space-y-4">
                        <div>
                            <label className="block text-purple-200 text-sm mb-1">Title (required)</label>
                            <input
                                type="text"
                                value={title}
                                onChange={(e) => setTitle(e.target.value)}
                                placeholder="e.g. Maintenance tonight"
                                maxLength={100}
                                className="w-full px-3 py-2 rounded-lg bg-white/10 border border-white/20 text-white placeholder-purple-300 focus:ring-2 focus:ring-pink-500"
                            />
                        </div>
                        <div>
                            <label className="block text-purple-200 text-sm mb-1">Body (optional)</label>
                            <textarea
                                value={body}
                                onChange={(e) => setBody(e.target.value)}
                                placeholder="e.g. App will be down 2–4 AM for maintenance."
                                rows={3}
                                className="w-full px-3 py-2 rounded-lg bg-white/10 border border-white/20 text-white placeholder-purple-300 focus:ring-2 focus:ring-pink-500 resize-none"
                            />
                            <p className="text-purple-200/80 text-xs mt-1">If empty, title is used as body.</p>
                        </div>
                        {message && (
                            <div className={`p-3 rounded-lg text-sm ${message.type === 'success' ? 'bg-green-500/20 text-green-200' : 'bg-red-500/20 text-red-200'}`}>
                                {message.text}
                            </div>
                        )}
                        <button
                            type="submit"
                            disabled={sending}
                            className="w-full px-4 py-3 bg-pink-500/80 hover:bg-pink-500 disabled:opacity-50 text-white rounded-lg font-medium"
                        >
                            {sending ? 'Sending…' : 'Send to all customers'}
                        </button>
                    </form>
                    <p className="text-purple-200/80 text-xs mt-4">
                        Only customers who have opened the mobile app and registered their device will receive this notification.
                    </p>
                </div>
            </div>
        </div>
    );
}

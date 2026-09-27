"use client";

import { useState, useEffect } from "react";
import Link from "next/link";
import { getAppDownloads, AppDownloadLinks } from "@/lib/api";

export default function DownloadAppsPage() {
    const [links, setLinks] = useState<AppDownloadLinks | null>(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        getAppDownloads()
            .then(setLinks)
            .catch(() => setLinks({
                windows_shopkeeper_url: "",
                android_customer_url: "",
                ios_customer_url: "",
            }))
            .finally(() => setLoading(false));
    }, []);

    if (loading) {
        return (
            <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800 flex items-center justify-center">
                <div className="text-white text-xl">Loading...</div>
            </div>
        );
    }

    const base = links || {
        windows_shopkeeper_url: "",
        android_customer_url: "",
        ios_customer_url: "",
        windows_coming_soon: true,
        android_coming_soon: true,
        ios_coming_soon: true,
    };

    return (
        <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800 relative overflow-hidden">
            <div className="absolute inset-0 overflow-hidden">
                <div className="absolute -top-40 -right-40 w-80 h-80 bg-purple-500 rounded-full mix-blend-multiply filter blur-xl opacity-20 animate-blob" />
                <div className="absolute -bottom-40 -left-40 w-80 h-80 bg-pink-500 rounded-full mix-blend-multiply filter blur-xl opacity-20 animate-blob animation-delay-2000" />
            </div>

            <div className="relative z-10 max-w-4xl mx-auto px-4 py-16">
                <div className="text-center mb-12">
                    <h1 className="text-4xl md:text-5xl font-black text-white mb-3">
                        Download <span className="text-pink-400">Qprint</span> Apps
                    </h1>
                    <p className="text-lg text-purple-200">
                        Use the app on your phone or computer instead of the web for the best experience.
                    </p>
                </div>

                <div className="grid md:grid-cols-3 gap-6">
                    {/* Windows - Shopkeeper */}
                    <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 border border-white/20 hover:bg-white/15 transition-all">
                        <div className="text-5xl mb-4">🖥️</div>
                        <h2 className="text-xl font-bold text-white mb-1">Windows</h2>
                        <p className="text-purple-200 text-sm mb-4">Shopkeeper app — manage queue & print</p>
                        {base.windows_shopkeeper_url ? (
                            <a
                                href={base.windows_shopkeeper_url}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="inline-block w-full text-center px-4 py-3 bg-gradient-to-r from-pink-500 to-purple-600 text-white font-bold rounded-xl hover:from-pink-600 hover:to-purple-700 transition-all"
                            >
                                Download for Windows
                            </a>
                        ) : base.windows_coming_soon ? (
                            <p className="text-amber-300 text-sm font-medium">Coming soon</p>
                        ) : (
                            <p className="text-purple-300 text-sm">Link not set yet. Check back later.</p>
                        )}
                    </div>

                    {/* Android - Customer */}
                    <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 border border-white/20 hover:bg-white/15 transition-all">
                        <div className="text-5xl mb-4">📱</div>
                        <h2 className="text-xl font-bold text-white mb-1">Android</h2>
                        <p className="text-purple-200 text-sm mb-4">Customer app — upload, pay, collect</p>
                        {base.android_customer_url ? (
                            <a
                                href={base.android_customer_url}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="inline-block w-full text-center px-4 py-3 bg-gradient-to-r from-green-500 to-teal-600 text-white font-bold rounded-xl hover:from-green-600 hover:to-teal-700 transition-all"
                            >
                                Get on Google Play
                            </a>
                        ) : base.android_coming_soon ? (
                            <p className="text-amber-300 text-sm font-medium">Coming soon</p>
                        ) : (
                            <p className="text-purple-300 text-sm">Link not set yet. Check back later.</p>
                        )}
                    </div>

                    {/* iOS - Customer */}
                    <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 border border-white/20 hover:bg-white/15 transition-all">
                        <div className="text-5xl mb-4">🍎</div>
                        <h2 className="text-xl font-bold text-white mb-1">iPhone / iPad</h2>
                        <p className="text-purple-200 text-sm mb-4">Customer app — upload, pay, collect</p>
                        {base.ios_customer_url ? (
                            <a
                                href={base.ios_customer_url}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="inline-block w-full text-center px-4 py-3 bg-gradient-to-r from-indigo-500 to-blue-600 text-white font-bold rounded-xl hover:from-indigo-600 hover:to-blue-700 transition-all"
                            >
                                Get on App Store
                            </a>
                        ) : base.ios_coming_soon ? (
                            <p className="text-amber-300 text-sm font-medium">Coming soon</p>
                        ) : (
                            <p className="text-purple-300 text-sm">Link not set yet. Check back later.</p>
                        )}
                    </div>
                </div>

                <div className="mt-12 text-center">
                    <Link
                        href="/"
                        className="text-purple-200 hover:text-white transition-colors"
                    >
                        ← Back to home
                    </Link>
                </div>
            </div>

            <style jsx>{`
                @keyframes blob {
                    0%, 100% { transform: translate(0, 0) scale(1); }
                    33% { transform: translate(30px, -50px) scale(1.1); }
                    66% { transform: translate(-20px, 20px) scale(0.9); }
                }
                .animate-blob { animation: blob 7s infinite; }
                .animation-delay-2000 { animation-delay: 2s; }
            `}</style>
        </div>
    );
}

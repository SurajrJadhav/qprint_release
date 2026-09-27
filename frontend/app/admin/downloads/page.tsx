"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { getAppDownloads, updateAppDownloads, AppDownloadLinks } from "@/lib/api";

export default function AdminDownloadsPage() {
    const [links, setLinks] = useState<AppDownloadLinks>({
        windows_shopkeeper_url: "",
        android_customer_url: "",
        ios_customer_url: "",
    });
    const [loading, setLoading] = useState(true);
    const [saving, setSaving] = useState(false);
    const [message, setMessage] = useState<{ type: "success" | "error"; text: string } | null>(null);
    const router = useRouter();

    useEffect(() => {
        const token = localStorage.getItem("token") || sessionStorage.getItem("token");
        const role = localStorage.getItem("role");
        if ((!token && !role) || role !== "admin") {
            router.push("/login");
            return;
        }
        getAppDownloads()
            .then((data) => setLinks({
                windows_shopkeeper_url: data.windows_shopkeeper_url ?? "",
                android_customer_url: data.android_customer_url ?? "",
                ios_customer_url: data.ios_customer_url ?? "",
                windows_coming_soon: data.windows_coming_soon !== false,
                android_coming_soon: data.android_coming_soon !== false,
                ios_coming_soon: data.ios_coming_soon !== false,
            }))
            .catch(() => setMessage({ type: "error", text: "Failed to load links" }))
            .finally(() => setLoading(false));
    }, [router]);

    const handleSave = async (e: React.FormEvent) => {
        e.preventDefault();
        setSaving(true);
        setMessage(null);
        try {
            await updateAppDownloads(links);
            setMessage({ type: "success", text: "App download links updated successfully." });
        } catch {
            setMessage({ type: "error", text: "Failed to save. Try again." });
        } finally {
            setSaving(false);
        }
    };

    if (loading) {
        return (
            <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800 flex items-center justify-center">
                <div className="text-white text-xl">Loading...</div>
            </div>
        );
    }

    return (
        <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800">
            <div className="max-w-3xl mx-auto px-4 py-8">
                <div className="flex items-center justify-between mb-8">
                    <div>
                        <h1 className="text-3xl font-black text-white mb-1">
                            App Download <span className="text-pink-400">Links</span>
                        </h1>
                        <p className="text-purple-200">
                            Set URLs for Windows (shopkeeper), Android (customer), and iOS (customer). These appear on the public Download Apps page.
                        </p>
                    </div>
                    <Link
                        href="/admin/dashboard"
                        className="px-4 py-2 bg-white/10 hover:bg-white/20 text-white rounded-lg border border-white/20"
                    >
                        ← Dashboard
                    </Link>
                </div>

                <form onSubmit={handleSave} className="space-y-6">
                    {message && (
                        <div
                            className={`p-4 rounded-xl ${
                                message.type === "success"
                                    ? "bg-green-500/20 border border-green-400/50 text-green-200"
                                    : "bg-red-500/20 border border-red-400/50 text-red-200"
                            }`}
                        >
                            {message.text}
                        </div>
                    )}

                    <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 border border-white/20 space-y-6">
                        {/* Windows */}
                        <div className="space-y-2">
                            <span className="text-white font-medium block">Windows (Shopkeeper app)</span>
                            <input
                                type="url"
                                value={links.windows_shopkeeper_url}
                                onChange={(e) =>
                                    setLinks((prev) => ({ ...prev, windows_shopkeeper_url: e.target.value }))
                                }
                                placeholder="https://example.com/qprint-shop.msix"
                                className="w-full px-4 py-3 rounded-xl bg-white/10 border border-white/20 text-white placeholder-purple-300 focus:ring-2 focus:ring-pink-500 focus:border-transparent"
                            />
                            <label className="flex items-center gap-2 cursor-pointer">
                                <input
                                    type="checkbox"
                                    checked={links.windows_coming_soon !== false}
                                    onChange={(e) =>
                                        setLinks((prev) => ({ ...prev, windows_coming_soon: e.target.checked }))
                                    }
                                    className="rounded border-white/30 bg-white/10 text-pink-500 focus:ring-pink-500"
                                />
                                <span className="text-purple-200 text-sm">Mark as Coming soon (hides download link on public page)</span>
                            </label>
                            <span className="text-purple-300 text-sm block">Direct link to .msix installer or download page</span>
                        </div>

                        {/* Android */}
                        <div className="space-y-2">
                            <span className="text-white font-medium block">Android (Customer app)</span>
                            <input
                                type="url"
                                value={links.android_customer_url}
                                onChange={(e) =>
                                    setLinks((prev) => ({ ...prev, android_customer_url: e.target.value }))
                                }
                                placeholder="https://play.google.com/store/apps/details?id=..."
                                className="w-full px-4 py-3 rounded-xl bg-white/10 border border-white/20 text-white placeholder-purple-300 focus:ring-2 focus:ring-pink-500 focus:border-transparent"
                            />
                            <label className="flex items-center gap-2 cursor-pointer">
                                <input
                                    type="checkbox"
                                    checked={links.android_coming_soon !== false}
                                    onChange={(e) =>
                                        setLinks((prev) => ({ ...prev, android_coming_soon: e.target.checked }))
                                    }
                                    className="rounded border-white/30 bg-white/10 text-pink-500 focus:ring-pink-500"
                                />
                                <span className="text-purple-200 text-sm">Mark as Coming soon</span>
                            </label>
                            <span className="text-purple-300 text-sm block">Google Play Store link</span>
                        </div>

                        {/* iOS */}
                        <div className="space-y-2">
                            <span className="text-white font-medium block">iOS (Customer app)</span>
                            <input
                                type="url"
                                value={links.ios_customer_url}
                                onChange={(e) =>
                                    setLinks((prev) => ({ ...prev, ios_customer_url: e.target.value }))
                                }
                                placeholder="https://apps.apple.com/app/..."
                                className="w-full px-4 py-3 rounded-xl bg-white/10 border border-white/20 text-white placeholder-purple-300 focus:ring-2 focus:ring-pink-500 focus:border-transparent"
                            />
                            <label className="flex items-center gap-2 cursor-pointer">
                                <input
                                    type="checkbox"
                                    checked={links.ios_coming_soon !== false}
                                    onChange={(e) =>
                                        setLinks((prev) => ({ ...prev, ios_coming_soon: e.target.checked }))
                                    }
                                    className="rounded border-white/30 bg-white/10 text-pink-500 focus:ring-pink-500"
                                />
                                <span className="text-purple-200 text-sm">Mark as Coming soon</span>
                            </label>
                            <span className="text-purple-300 text-sm block">App Store link</span>
                        </div>
                    </div>

                    <div className="flex gap-4">
                        <button
                            type="submit"
                            disabled={saving}
                            className="px-6 py-3 bg-gradient-to-r from-pink-500 to-purple-600 text-white font-bold rounded-xl hover:from-pink-600 hover:to-purple-700 disabled:opacity-50"
                        >
                            {saving ? "Saving…" : "Save links"}
                        </button>
                        <a
                            href="/download-apps"
                            target="_blank"
                            rel="noopener noreferrer"
                            className="px-6 py-3 bg-white/10 text-white rounded-xl border border-white/20 hover:bg-white/20"
                        >
                            Preview download page →
                        </a>
                    </div>
                </form>

                <div className="mt-8 p-4 bg-white/5 rounded-xl border border-white/10 text-purple-200 text-sm">
                    <strong className="text-white">Where to host files:</strong>
                    <ul className="list-disc list-inside mt-2 space-y-1">
                        <li><strong>Windows .msix:</strong> Upload to your server, Render static file, or a file host (e.g. GitHub Releases, OneDrive share link). Paste the direct download URL here.</li>
                        <li><strong>Android:</strong> Use the Google Play Store listing URL after publishing the app.</li>
                        <li><strong>iOS:</strong> Use the App Store listing URL after publishing the app.</li>
                    </ul>
                </div>
            </div>
        </div>
    );
}

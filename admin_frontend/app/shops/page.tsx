"use client";

import { useState, useEffect, useMemo } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import api from "@/lib/api";

interface Shopkeeper {
    id: number;
    full_name?: string;
    shop_name?: string;
    email?: string;
    phone?: string;
    role: string;
}

export default function ShopsListPage() {
    const [shopkeepers, setShopkeepers] = useState<Shopkeeper[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState("");
    const [search, setSearch] = useState("");
    const router = useRouter();

    useEffect(() => {
        const token = localStorage.getItem("token");
        const role = localStorage.getItem("role");
        if (!token || role !== "admin") {
            router.push("/login");
            return;
        }

        (async () => {
            try {
                const res = await api.get("/admin/users", {
                    params: { role: "shopkeeper", page_size: 500 },
                });
                setShopkeepers(res.data.users || []);
                setError("");
            } catch (err: unknown) {
                const e = err as { response?: { status: number } };
                if (e.response?.status === 401) {
                    router.push("/login");
                    return;
                }
                setError("Failed to load shops.");
            } finally {
                setLoading(false);
            }
        })();
    }, [router]);

    const filtered = useMemo(() => {
        const q = search.trim().toLowerCase();
        if (!q) return shopkeepers;
        return shopkeepers.filter((s) => {
            const shop = (s.shop_name || "").toLowerCase();
            const owner = (s.full_name || s.email || s.phone || "").toLowerCase();
            return shop.includes(q) || owner.includes(q) || String(s.id).includes(q);
        });
    }, [shopkeepers, search]);

    const handleLogout = () => {
        localStorage.removeItem("token");
        localStorage.removeItem("role");
        localStorage.removeItem("display_name");
        localStorage.removeItem("username");
        router.push("/login");
    };

    if (loading) {
        return (
            <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800 flex items-center justify-center">
                <div className="text-white text-xl">Loading shops…</div>
            </div>
        );
    }

    return (
        <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800">
            <div className="container mx-auto px-4 py-8">
                <div className="flex justify-between items-center mb-8">
                    <div>
                        <h1 className="text-4xl font-black text-white mb-2">
                            <span className="text-pink-400">Shops</span>
                        </h1>
                        <p className="text-purple-200">
                            Open a shop to see all orders and manage payouts in one place
                        </p>
                    </div>
                    <div className="flex gap-4">
                        <Link
                            href="/dashboard"
                            className="bg-white/10 hover:bg-white/20 text-white px-4 py-2 rounded-lg border border-white/20"
                        >
                            Dashboard
                        </Link>
                        <button
                            type="button"
                            onClick={handleLogout}
                            className="bg-red-500/20 hover:bg-red-500/30 text-white px-4 py-2 rounded-lg border border-red-400/50"
                        >
                            Logout
                        </button>
                    </div>
                </div>

                <div className="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20 mb-6">
                    <label className="admin-label mb-2" htmlFor="shop-search">
                        Search by shop name, owner name, or ID
                    </label>
                    <input
                        id="shop-search"
                        type="search"
                        value={search}
                        onChange={(e) => setSearch(e.target.value)}
                        placeholder="Type to filter…"
                        className="w-full max-w-md bg-white/20 border border-white/30 p-3 rounded-lg text-white placeholder-purple-200"
                    />
                </div>

                {error && (
                    <div className="bg-red-500/20 border border-red-400/50 rounded-xl p-4 mb-6">
                        <p className="text-red-300">{error}</p>
                    </div>
                )}

                <div className="bg-white/10 backdrop-blur-lg rounded-xl border border-white/20 overflow-hidden">
                    {filtered.length === 0 ? (
                        <div className="p-12 text-center text-purple-200">
                            {shopkeepers.length === 0
                                ? "No shopkeeper accounts yet."
                                : "No shops match your search."}
                        </div>
                    ) : (
                        <div className="overflow-x-auto">
                            <table className="w-full">
                                <thead className="bg-white/10">
                                    <tr>
                                        <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">
                                            Shop
                                        </th>
                                        <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">
                                            Owner
                                        </th>
                                        <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">
                                            ID
                                        </th>
                                        <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">
                                            Action
                                        </th>
                                    </tr>
                                </thead>
                                <tbody className="divide-y divide-white/10">
                                    {filtered.map((s) => (
                                        <tr key={s.id} className="hover:bg-white/5">
                                            <td className="px-6 py-4 text-white font-medium">
                                                {s.shop_name || "—"}
                                            </td>
                                            <td className="px-6 py-4 text-white">{s.full_name || s.email || "—"}</td>
                                            <td className="px-6 py-4 text-white font-mono text-sm">{s.id}</td>
                                            <td className="px-6 py-4">
                                                <Link
                                                    href={`/shops/${s.id}`}
                                                    className="text-pink-300 hover:text-pink-200 font-medium"
                                                >
                                                    View orders &amp; payouts →
                                                </Link>
                                            </td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    )}
                </div>

                <p className="text-purple-300 text-sm mt-6">
                    Tip: the legacy <Link href="/payments" className="text-pink-300 hover:underline">Manage payments</Link>{" "}
                    dropdown is still available if you prefer that flow.
                </p>
            </div>
        </div>
    );
}

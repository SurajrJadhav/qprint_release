"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import api from "@/lib/api";
import Link from "next/link";

interface Shopkeeper {
    id: number;
    full_name?: string;
    shop_name?: string;
    role: string;
}

interface Payout {
    id: number;
    shopkeeper_id: number;
    shopkeeper_name: string;
    payment_order_id: number;
    order_id: string;
    amount: number;
    status: string;
    payout_method?: string;
    payout_reference?: string;
    created_at: string;
    paid_at?: string;
    failed_at?: string;
    failure_reason?: string;
}

interface PayoutListResponse {
    payouts: Payout[];
    total: number;
    page: number;
    page_size: number;
    total_pages: number;
}

export default function ManagePaymentsPage() {
    const [shopkeepers, setShopkeepers] = useState<Shopkeeper[]>([]);
    const [selectedShopId, setSelectedShopId] = useState<number | "">("");
    const [payoutsData, setPayoutsData] = useState<PayoutListResponse | null>(null);
    const [loadingShops, setLoadingShops] = useState(true);
    const [loadingPayouts, setLoadingPayouts] = useState(false);
    const [error, setError] = useState("");
    const [updating, setUpdating] = useState<number | null>(null);
    const router = useRouter();

    useEffect(() => {
        const token = localStorage.getItem("token");
        const role = localStorage.getItem("role");
        if (!token || role !== "admin") {
            router.push("/login");
            return;
        }
        fetchShopkeepers();
    }, [router]);

    useEffect(() => {
        if (selectedShopId !== "") {
            fetchPayouts();
        } else {
            setPayoutsData(null);
        }
    }, [selectedShopId]);

    const fetchShopkeepers = async () => {
        try {
            setLoadingShops(true);
            const res = await api.get("/admin/users", {
                params: { role: "shopkeeper", page_size: 500 },
            });
            setShopkeepers(res.data.users || []);
            setError("");
        } catch (err: unknown) {
            const e = err as { response?: { status: number; data?: unknown }; message?: string };
            if (e.response?.status === 401) {
                router.push("/login");
                return;
            }
            setError("Failed to load shopkeepers.");
        } finally {
            setLoadingShops(false);
        }
    };

    const fetchPayouts = async () => {
        if (selectedShopId === "") return;
        try {
            setLoadingPayouts(true);
            const res = await api.get("/admin/payouts", {
                params: { shopkeeper_id: String(selectedShopId), page_size: 100 },
            });
            setPayoutsData(res.data);
            setError("");
        } catch (err: unknown) {
            const e = err as { response?: { status: number }; message?: string };
            if (e.response?.status === 401) {
                router.push("/login");
                return;
            }
            setError("Failed to load payouts for this shop.");
        } finally {
            setLoadingPayouts(false);
        }
    };

    const handleUpdateStatus = async (payoutId: number, status: string) => {
        if (status === "paid") {
            const method = prompt("Enter payout method (e.g., Bank Transfer, UPI):");
            if (!method) return;
            const reference = prompt("Enter payout reference/transaction ID:");
            if (!reference) return;
            try {
                setUpdating(payoutId);
                await api.put("/admin/payouts/update", {
                    payout_id: payoutId,
                    status: "paid",
                    payout_method: method,
                    payout_reference: reference,
                });
                await fetchPayouts();
            } catch (err) {
                alert("Failed to update payout. Try again.");
            } finally {
                setUpdating(null);
            }
        } else if (status === "failed") {
            const reason = prompt("Reason for failure (optional):");
            try {
                setUpdating(payoutId);
                await api.put("/admin/payouts/update", {
                    payout_id: payoutId,
                    status: "failed",
                    failure_reason: reason && reason.trim() ? reason.trim() : undefined,
                });
                alert("Payout marked as failed. You can mark it as paid later if the issue is resolved.");
                await fetchPayouts();
            } catch (err) {
                alert("Failed to update payout. Try again.");
            } finally {
                setUpdating(null);
            }
        }
    };

    const getStatusColor = (status: string) => {
        switch (status) {
            case "paid": return "bg-green-500/20 text-green-300";
            case "pending": return "bg-yellow-500/20 text-yellow-300";
            case "failed": return "bg-red-500/20 text-red-300";
            default: return "bg-gray-500/20 text-gray-300";
        }
    };

    const selectedShop = shopkeepers.find((s) => s.id === selectedShopId);
    const displayName = selectedShop
        ? (selectedShop.shop_name || selectedShop.full_name || `Shop #${selectedShop.id}`)
        : "";

    return (
        <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800">
            <div className="container mx-auto px-4 py-8">
                <div className="flex justify-between items-center mb-8">
                    <div>
                        <h1 className="text-4xl font-black text-white mb-2">
                            Manage <span className="text-pink-400">Payments</span>
                        </h1>
                        <p className="text-purple-200">
                            Select a shop to view payout history and mark payments as done. For a full shop view with orders, use{" "}
                            <Link href="/shops" className="text-pink-300 hover:underline">Shops</Link>.
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
                            onClick={() => {
                                localStorage.removeItem("token");
                                localStorage.removeItem("role");
                                localStorage.removeItem("display_name");
                                localStorage.removeItem("username");
                                router.push("/login");
                            }}
                            className="bg-red-500/20 hover:bg-red-500/30 text-white px-4 py-2 rounded-lg border border-red-400/50"
                        >
                            Logout
                        </button>
                    </div>
                </div>

                {/* Shop selector */}
                <div className="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20 mb-6">
                    <label className="admin-label mb-2">Select shop</label>
                    <select
                        value={selectedShopId}
                        onChange={(e) => setSelectedShopId(e.target.value === "" ? "" : Number(e.target.value))}
                        className="admin-select w-full max-w-md"
                    >
                        <option value="">-- Choose a shop --</option>
                        {shopkeepers.map((s) => (
                            <option key={s.id} value={s.id}>
                                {s.shop_name || s.full_name || `Shop #${s.id}`} (ID: {s.id})
                            </option>
                        ))}
                    </select>
                    {loadingShops && <p className="text-purple-200 mt-2">Loading shops...</p>}
                </div>

                {error && (
                    <div className="bg-red-500/20 border border-red-400/50 rounded-xl p-4 mb-6">
                        <p className="text-red-300">{error}</p>
                    </div>
                )}

                {selectedShopId !== "" && (
                    <>
                        <div className="bg-white/10 backdrop-blur-lg rounded-xl p-4 mb-4 border border-white/20">
                            <p className="text-white font-medium">
                                Payout history for: <span className="text-pink-300">{displayName}</span>
                            </p>
                        </div>

                        {loadingPayouts ? (
                            <div className="bg-white/10 rounded-xl p-12 text-center">
                                <p className="text-white">Loading payouts...</p>
                            </div>
                        ) : payoutsData && (payoutsData.payouts?.length ?? 0) === 0 ? (
                            <div className="bg-white/10 backdrop-blur-lg rounded-xl p-12 text-center border border-white/20">
                                <p className="text-purple-200 font-medium">No payouts for this shop yet.</p>
                                <p className="text-purple-300 text-sm mt-2 max-w-md mx-auto">
                                    Payouts appear when a customer pays for a queue print at this shop and the payment is captured. You can also check the <Link href="/payouts" className="text-pink-300 hover:underline">Payouts</Link> page to see all payouts across shops.
                                </p>
                            </div>
                        ) : payoutsData && (payoutsData.payouts?.length ?? 0) > 0 ? (
                            <div className="bg-white/10 backdrop-blur-lg rounded-xl border border-white/20 overflow-hidden">
                                <div className="overflow-x-auto">
                                    <table className="w-full">
                                        <thead className="bg-white/10">
                                            <tr>
                                                <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">ID</th>
                                                <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Order ID</th>
                                                <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Amount</th>
                                                <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Status</th>
                                                <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Method</th>
                                                <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Reference</th>
                                                <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Created</th>
                                                <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Paid at</th>
                                                <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Failed</th>
                                                <th className="px-6 py-3 text-left text-xs font-medium text-purple-200 uppercase">Actions</th>
                                            </tr>
                                        </thead>
                                        <tbody className="divide-y divide-white/10">
                                            {(payoutsData.payouts ?? []).map((payout) => (
                                                <tr key={payout.id} className="hover:bg-white/5">
                                                    <td className="px-6 py-4 whitespace-nowrap text-white">{payout.id}</td>
                                                    <td className="px-6 py-4 whitespace-nowrap text-white font-mono text-sm">{payout.order_id}</td>
                                                    <td className="px-6 py-4 whitespace-nowrap text-white font-medium">₹{payout.amount.toFixed(2)}</td>
                                                    <td className="px-6 py-4 whitespace-nowrap">
                                                        <span className={`px-2 py-1 rounded text-xs font-medium ${getStatusColor(payout.status)}`}>
                                                            {payout.status}
                                                        </span>
                                                    </td>
                                                    <td className="px-6 py-4 whitespace-nowrap text-white">{payout.payout_method || "-"}</td>
                                                    <td className="px-6 py-4 whitespace-nowrap text-white font-mono text-xs">{payout.payout_reference || "-"}</td>
                                                    <td className="px-6 py-4 whitespace-nowrap text-white text-sm">
                                                        {new Date(payout.created_at).toLocaleDateString()}
                                                    </td>
                                                    <td className="px-6 py-4 whitespace-nowrap text-white text-sm">
                                                        {payout.paid_at ? new Date(payout.paid_at).toLocaleDateString() : "-"}
                                                    </td>
                                                    <td className="px-6 py-4 whitespace-nowrap text-white text-sm max-w-[180px]">
                                                        {payout.failed_at ? (
                                                            <span title={payout.failure_reason || ""}>
                                                                {new Date(payout.failed_at).toLocaleDateString()}
                                                                {payout.failure_reason && (
                                                                    <span className="block text-purple-300 text-xs truncate" title={payout.failure_reason}>
                                                                        {payout.failure_reason}
                                                                    </span>
                                                                )}
                                                            </span>
                                                        ) : "-"}
                                                    </td>
                                                    <td className="px-6 py-4 whitespace-nowrap">
                                                        {(payout.status === "pending" || payout.status === "failed") && (
                                                            <div className="flex gap-2 flex-wrap">
                                                                <button
                                                                    onClick={() => handleUpdateStatus(payout.id, "paid")}
                                                                    disabled={updating === payout.id}
                                                                    className="text-green-400 hover:text-green-300 font-medium disabled:opacity-50"
                                                                >
                                                                    {updating === payout.id ? "Updating..." : "Mark paid"}
                                                                </button>
                                                                {payout.status === "pending" && (
                                                                    <button
                                                                        onClick={() => handleUpdateStatus(payout.id, "failed")}
                                                                        disabled={updating === payout.id}
                                                                        className="text-red-400 hover:text-red-300 font-medium disabled:opacity-50"
                                                                    >
                                                                        Mark failed
                                                                    </button>
                                                                )}
                                                            </div>
                                                        )}
                                                    </td>
                                                </tr>
                                            ))}
                                        </tbody>
                                    </table>
                                </div>
                                <div className="px-6 py-3 border-t border-white/10 text-purple-200 text-sm">
                                    Showing {(payoutsData.payouts ?? []).length} of {payoutsData.total ?? 0} payouts
                                </div>
                            </div>
                        ) : null}
                    </>
                )}
            </div>
        </div>
    );
}

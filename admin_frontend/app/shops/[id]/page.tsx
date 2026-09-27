"use client";

import { useState, useEffect, useCallback } from "react";
import { useRouter, useParams } from "next/navigation";
import Link from "next/link";
import api, { fetchCsrfToken } from "@/lib/api";

interface ShopkeeperDetail {
    id: number;
    full_name?: string;
    email?: string;
    phone?: string;
    shop_name?: string;
    role: string;
    total_orders: number;
    total_earned?: number;
}

interface Order {
    id: number;
    user_id: number;
    customer_name: string;
    order_id: string;
    payment_id?: string;
    amount: number;
    status: string;
    shopkeeper_id?: number;
    shopkeeper_name?: string;
    platform_commission: number;
    shopkeeper_amount?: number;
    print_type: string;
    copies: number;
    print_mode: string;
    color_mode: string;
    paper_size: string;
    created_at: string;
    paid_at?: string;
}

interface OrderListResponse {
    orders: Order[];
    total: number;
    page: number;
    page_size: number;
    total_pages: number;
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

interface PayoutSummary {
    total_pending_count: number;
    total_pending_amount: number;
    total_paid_count: number;
    total_paid_amount: number;
}

interface PayoutListResponse {
    payouts: Payout[];
    total: number;
    page: number;
    page_size: number;
    total_pages: number;
    summary?: PayoutSummary;
}

type Tab = "orders" | "payouts";

export default function ShopDetailPage() {
    const params = useParams();
    const router = useRouter();
    const rawId = params?.id;
    const idStr = Array.isArray(rawId) ? rawId[0] : rawId;
    const shopkeeperId = typeof idStr === "string" ? parseInt(idStr, 10) : NaN;

    const [shop, setShop] = useState<ShopkeeperDetail | null>(null);
    const [shopError, setShopError] = useState("");
    const [tab, setTab] = useState<Tab>("orders");

    const [ordersData, setOrdersData] = useState<OrderListResponse | null>(null);
    const [ordersLoading, setOrdersLoading] = useState(false);
    const [ordersError, setOrdersError] = useState("");
    const [orderPage, setOrderPage] = useState(1);
    const [statusFilter, setStatusFilter] = useState("");

    const [payoutSummary, setPayoutSummary] = useState<PayoutSummary | null>(null);
    const [payoutsData, setPayoutsData] = useState<PayoutListResponse | null>(null);
    const [payoutsLoading, setPayoutsLoading] = useState(false);
    const [payoutsError, setPayoutsError] = useState("");
    const [payoutPage, setPayoutPage] = useState(1);
    const [updating, setUpdating] = useState<number | null>(null);

    const validId = Number.isFinite(shopkeeperId) && shopkeeperId > 0;

    useEffect(() => {
        const token = localStorage.getItem("token");
        const role = localStorage.getItem("role");
        if (!token || role !== "admin") {
            router.push("/login");
            return;
        }
        fetchCsrfToken();
    }, [router]);

    useEffect(() => {
        if (!validId) {
            setShopError("Invalid shop ID.");
            return;
        }
        let cancelled = false;
        (async () => {
            try {
                const res = await api.get<ShopkeeperDetail>("/admin/users/details", {
                    params: { user_id: shopkeeperId },
                });
                if (cancelled) return;
                if (res.data.role !== "shopkeeper") {
                    setShopError("This account is not a shopkeeper.");
                    setShop(null);
                    return;
                }
                setShop(res.data);
                setShopError("");
            } catch (err: unknown) {
                if (cancelled) return;
                const e = err as { response?: { status: number } };
                if (e.response?.status === 401) {
                    router.push("/login");
                    return;
                }
                if (e.response?.status === 404) {
                    setShopError("Shop not found.");
                } else {
                    setShopError("Failed to load shop.");
                }
                setShop(null);
            }
        })();
        return () => {
            cancelled = true;
        };
    }, [shopkeeperId, validId, router]);

    const fetchPayoutSummary = useCallback(async () => {
        if (!validId) return;
        try {
            const res = await api.get<PayoutListResponse>("/admin/payouts", {
                params: { shopkeeper_id: String(shopkeeperId), page: 1, page_size: 1 },
            });
            if (res.data.summary) setPayoutSummary(res.data.summary);
        } catch {
            /* non-fatal */
        }
    }, [shopkeeperId, validId]);

    const fetchOrders = useCallback(async () => {
        if (!validId) return;
        setOrdersLoading(true);
        setOrdersError("");
        try {
            const params = new URLSearchParams({
                page: String(orderPage),
                page_size: "20",
                shopkeeper_id: String(shopkeeperId),
            });
            if (statusFilter === "pending_at_shop") {
                params.set("pending_at_shop", "true");
            } else if (statusFilter) {
                params.set("status", statusFilter);
            }
            const res = await api.get<OrderListResponse>(`/admin/orders?${params.toString()}`);
            setOrdersData(res.data);
        } catch (err: unknown) {
            const e = err as { response?: { status: number }; message?: string };
            if (e.response?.status === 401) {
                router.push("/login");
                return;
            }
            setOrdersError("Failed to load orders for this shop.");
            setOrdersData(null);
        } finally {
            setOrdersLoading(false);
        }
    }, [shopkeeperId, validId, orderPage, statusFilter, router]);

    const fetchPayouts = useCallback(async () => {
        if (!validId) return;
        setPayoutsLoading(true);
        setPayoutsError("");
        try {
            const res = await api.get<PayoutListResponse>("/admin/payouts", {
                params: {
                    shopkeeper_id: String(shopkeeperId),
                    page: payoutPage,
                    page_size: 50,
                },
            });
            setPayoutsData(res.data);
            if (res.data.summary) setPayoutSummary(res.data.summary);
        } catch (err: unknown) {
            const e = err as { response?: { status: number } };
            if (e.response?.status === 401) {
                router.push("/login");
                return;
            }
            setPayoutsError("Failed to load payouts.");
            setPayoutsData(null);
        } finally {
            setPayoutsLoading(false);
        }
    }, [shopkeeperId, validId, payoutPage, router]);

    useEffect(() => {
        if (!shop || !validId) return;
        fetchOrders();
    }, [shop, validId, fetchOrders]);

    useEffect(() => {
        if (!shop || !validId) return;
        fetchPayoutSummary();
    }, [shop, validId, fetchPayoutSummary]);

    useEffect(() => {
        if (!shop || !validId || tab !== "payouts") return;
        fetchPayouts();
    }, [shop, validId, tab, fetchPayouts]);

    const handleUpdatePayout = async (payoutId: number, status: string) => {
        if (status === "paid") {
            const method = prompt("Enter payout method (e.g., Bank Transfer, UPI):");
            if (!method) return;
            const reference = prompt("Enter payout reference/transaction ID:");
            if (!reference) return;
            try {
                setUpdating(payoutId);
                await fetchCsrfToken();
                await api.put("/admin/payouts/update", {
                    payout_id: payoutId,
                    status: "paid",
                    payout_method: method,
                    payout_reference: reference,
                });
                await fetchPayouts();
                await fetchPayoutSummary();
                await fetchOrders();
            } catch {
                alert("Failed to update payout. Try again.");
            } finally {
                setUpdating(null);
            }
        } else if (status === "failed") {
            const reason = prompt("Reason for failure (optional):");
            try {
                setUpdating(payoutId);
                await fetchCsrfToken();
                await api.put("/admin/payouts/update", {
                    payout_id: payoutId,
                    status: "failed",
                    failure_reason: reason && reason.trim() ? reason.trim() : undefined,
                });
                await fetchPayouts();
                await fetchPayoutSummary();
                await fetchOrders();
            } catch {
                alert("Failed to update payout. Try again.");
            } finally {
                setUpdating(null);
            }
        }
    };

    const getOrderStatusColor = (status: string) => {
        switch (status) {
            case "paid":
                return "bg-green-500/20 text-green-300";
            case "pending":
                return "bg-yellow-500/20 text-yellow-300";
            case "failed":
                return "bg-red-500/20 text-red-300";
            case "refunded":
                return "bg-purple-500/20 text-purple-300";
            default:
                return "bg-gray-500/20 text-gray-300";
        }
    };

    const getPayoutStatusColor = (status: string) => {
        switch (status) {
            case "paid":
                return "bg-green-500/20 text-green-300";
            case "pending":
                return "bg-yellow-500/20 text-yellow-300";
            case "failed":
                return "bg-red-500/20 text-red-300";
            default:
                return "bg-gray-500/20 text-gray-300";
        }
    };

    const handleLogout = () => {
        localStorage.removeItem("token");
        localStorage.removeItem("role");
        localStorage.removeItem("display_name");
        localStorage.removeItem("username");
        router.push("/login");
    };

    const displayName = shop ? (shop.shop_name || shop.full_name || `Shop #${shop.id}`) : "";

    if (!validId) {
        return (
            <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800 flex items-center justify-center px-4">
                <div className="text-center">
                    <p className="text-red-300 mb-4">{shopError || "Invalid shop ID."}</p>
                    <Link href="/shops" className="text-pink-300 hover:underline">
                        ← Back to shops
                    </Link>
                </div>
            </div>
        );
    }

    if (shopError && !shop) {
        return (
            <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800 flex items-center justify-center px-4">
                <div className="text-center">
                    <p className="text-red-300 mb-4">{shopError}</p>
                    <Link href="/shops" className="text-pink-300 hover:underline">
                        ← Back to shops
                    </Link>
                </div>
            </div>
        );
    }

    if (!shop) {
        return (
            <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800 flex items-center justify-center">
                <div className="text-white text-xl">Loading shop…</div>
            </div>
        );
    }

    return (
        <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800">
            <div className="container mx-auto px-4 py-8">
                <div className="flex flex-wrap justify-between items-start gap-4 mb-6">
                    <div>
                        <nav className="text-purple-300 text-sm mb-2">
                            <Link href="/shops" className="hover:text-white">
                                Shops
                            </Link>
                            <span className="mx-2">/</span>
                            <span className="text-white">{displayName}</span>
                        </nav>
                        <h1 className="text-3xl md:text-4xl font-black text-white mb-1">
                            {displayName}
                        </h1>
                        <p className="text-purple-200">
                            {shop.full_name ? `${shop.full_name} · ` : ""}ID {shop.id}
                            {shop.phone ? ` · ${shop.phone}` : ""}
                        </p>
                    </div>
                    <div className="flex gap-3 flex-wrap">
                        <Link
                            href="/shops"
                            className="bg-white/10 hover:bg-white/20 text-white px-4 py-2 rounded-lg border border-white/20"
                        >
                            All shops
                        </Link>
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

                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 mb-6">
                    <div className="bg-white/10 backdrop-blur-lg rounded-xl p-4 border border-white/20">
                        <div className="text-purple-200 text-xs uppercase">Pending payouts</div>
                        <div className="text-xl font-bold text-yellow-300">
                            ₹{(payoutSummary?.total_pending_amount ?? 0).toFixed(2)}
                        </div>
                        <div className="text-purple-300 text-sm">
                            {payoutSummary?.total_pending_count ?? 0} items
                        </div>
                    </div>
                    <div className="bg-white/10 backdrop-blur-lg rounded-xl p-4 border border-white/20">
                        <div className="text-purple-200 text-xs uppercase">Paid out (all time)</div>
                        <div className="text-xl font-bold text-green-300">
                            ₹{(payoutSummary?.total_paid_amount ?? 0).toFixed(2)}
                        </div>
                        <div className="text-purple-300 text-sm">
                            {payoutSummary?.total_paid_count ?? 0} items
                        </div>
                    </div>
                    <div className="bg-white/10 backdrop-blur-lg rounded-xl p-4 border border-white/20">
                        <div className="text-purple-200 text-xs uppercase">Paid payout lines (profile)</div>
                        <div className="text-xl font-bold text-white">{shop.total_orders}</div>
                        <div className="text-purple-300 text-sm">
                            ₹{(shop.total_earned ?? 0).toFixed(2)} total earned
                        </div>
                    </div>
                </div>

                <div className="flex gap-2 mb-6 border-b border-white/10 pb-1">
                    <button
                        type="button"
                        onClick={() => setTab("orders")}
                        className={`px-4 py-2 rounded-t-lg font-medium ${
                            tab === "orders"
                                ? "bg-white/20 text-white"
                                : "text-purple-200 hover:text-white hover:bg-white/10"
                        }`}
                    >
                        Orders
                    </button>
                    <button
                        type="button"
                        onClick={() => setTab("payouts")}
                        className={`px-4 py-2 rounded-t-lg font-medium ${
                            tab === "payouts"
                                ? "bg-white/20 text-white"
                                : "text-purple-200 hover:text-white hover:bg-white/10"
                        }`}
                    >
                        Payouts
                    </button>
                </div>

                {tab === "orders" && (
                    <>
                        <div className="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20 mb-6">
                            <label className="admin-label mb-2">Status</label>
                            <select
                                value={statusFilter}
                                onChange={(e) => {
                                    setStatusFilter(e.target.value);
                                    setOrderPage(1);
                                }}
                                className="admin-select w-full max-w-md"
                            >
                                <option value="">All</option>
                                <option value="pending_at_shop">Pending at shop</option>
                                <option value="pending">Pending (payment)</option>
                                <option value="paid">Paid</option>
                                <option value="failed">Failed</option>
                                <option value="refunded">Refunded</option>
                            </select>
                        </div>

                        {ordersError && (
                            <div className="bg-red-500/20 border border-red-400/50 rounded-xl p-4 mb-6">
                                <p className="text-red-300">{ordersError}</p>
                            </div>
                        )}

                        {ordersLoading && !ordersData ? (
                            <div className="text-white p-8 text-center">Loading orders…</div>
                        ) : ordersData && ordersData.orders.length === 0 ? (
                            <div className="bg-white/10 rounded-xl p-12 text-center text-purple-200">
                                No orders for this shop with the current filter.
                            </div>
                        ) : ordersData ? (
                            <div className="bg-white/10 backdrop-blur-lg rounded-xl border border-white/20 overflow-hidden">
                                <div className="overflow-x-auto">
                                    <table className="w-full">
                                        <thead className="bg-white/10">
                                            <tr>
                                                <th className="px-4 py-3 text-left text-xs font-medium text-purple-200 uppercase">
                                                    Order ID
                                                </th>
                                                <th className="px-4 py-3 text-left text-xs font-medium text-purple-200 uppercase">
                                                    Customer
                                                </th>
                                                <th className="px-4 py-3 text-left text-xs font-medium text-purple-200 uppercase">
                                                    Created
                                                </th>
                                                <th className="px-4 py-3 text-left text-xs font-medium text-purple-200 uppercase">
                                                    Amount
                                                </th>
                                                <th className="px-4 py-3 text-left text-xs font-medium text-purple-200 uppercase">
                                                    Status
                                                </th>
                                                <th className="px-4 py-3 text-left text-xs font-medium text-purple-200 uppercase">
                                                    Type
                                                </th>
                                            </tr>
                                        </thead>
                                        <tbody className="divide-y divide-white/10">
                                            {ordersData.orders.map((order) => (
                                                <tr key={order.id} className="hover:bg-white/5">
                                                    <td className="px-4 py-3 text-white font-mono text-sm">
                                                        {order.order_id}
                                                    </td>
                                                    <td className="px-4 py-3 text-white">{order.customer_name}</td>
                                                    <td className="px-4 py-3 text-white text-sm">
                                                        {new Date(order.created_at).toLocaleString(undefined, {
                                                            dateStyle: "short",
                                                            timeStyle: "short",
                                                        })}
                                                    </td>
                                                    <td className="px-4 py-3 text-white">₹{order.amount.toFixed(2)}</td>
                                                    <td className="px-4 py-3">
                                                        <span
                                                            className={`px-2 py-1 rounded text-xs font-medium ${getOrderStatusColor(
                                                                order.status
                                                            )}`}
                                                        >
                                                            {statusFilter === "pending_at_shop"
                                                                ? "Pending at shop"
                                                                : order.status}
                                                        </span>
                                                    </td>
                                                    <td className="px-4 py-3">
                                                        <span className="px-2 py-1 rounded text-xs font-medium bg-blue-500/20 text-blue-300">
                                                            {order.print_type}
                                                        </span>
                                                    </td>
                                                </tr>
                                            ))}
                                        </tbody>
                                    </table>
                                </div>
                                {ordersData.total_pages > 1 && (
                                    <div className="px-4 py-3 flex justify-between items-center border-t border-white/10">
                                        <span className="text-purple-200 text-sm">
                                            Page {ordersData.page} of {ordersData.total_pages} ({ordersData.total}{" "}
                                            orders)
                                        </span>
                                        <div className="flex gap-2">
                                            <button
                                                type="button"
                                                onClick={() => setOrderPage((p) => Math.max(1, p - 1))}
                                                disabled={orderPage === 1 || ordersLoading}
                                                className="px-4 py-2 bg-white/10 hover:bg-white/20 text-white rounded-lg disabled:opacity-50"
                                            >
                                                Previous
                                            </button>
                                            <button
                                                type="button"
                                                onClick={() =>
                                                    setOrderPage((p) =>
                                                        Math.min(ordersData.total_pages, p + 1)
                                                    )
                                                }
                                                disabled={
                                                    orderPage === ordersData.total_pages || ordersLoading
                                                }
                                                className="px-4 py-2 bg-white/10 hover:bg-white/20 text-white rounded-lg disabled:opacity-50"
                                            >
                                                Next
                                            </button>
                                        </div>
                                    </div>
                                )}
                            </div>
                        ) : null}
                    </>
                )}

                {tab === "payouts" && (
                    <>
                        {payoutsError && (
                            <div className="bg-red-500/20 border border-red-400/50 rounded-xl p-4 mb-6">
                                <p className="text-red-300">{payoutsError}</p>
                            </div>
                        )}

                        {payoutsLoading && !payoutsData ? (
                            <div className="text-white p-8 text-center">Loading payouts…</div>
                        ) : payoutsData && (payoutsData.payouts?.length ?? 0) === 0 ? (
                            <div className="bg-white/10 backdrop-blur-lg rounded-xl p-12 text-center border border-white/20">
                                <p className="text-purple-200">No payouts for this shop yet.</p>
                            </div>
                        ) : payoutsData ? (
                            <div className="bg-white/10 backdrop-blur-lg rounded-xl border border-white/20 overflow-hidden">
                                <div className="overflow-x-auto">
                                    <table className="w-full">
                                        <thead className="bg-white/10">
                                            <tr>
                                                <th className="px-4 py-3 text-left text-xs font-medium text-purple-200 uppercase">
                                                    Order ID
                                                </th>
                                                <th className="px-4 py-3 text-left text-xs font-medium text-purple-200 uppercase">
                                                    Amount
                                                </th>
                                                <th className="px-4 py-3 text-left text-xs font-medium text-purple-200 uppercase">
                                                    Status
                                                </th>
                                                <th className="px-4 py-3 text-left text-xs font-medium text-purple-200 uppercase">
                                                    Method / Ref
                                                </th>
                                                <th className="px-4 py-3 text-left text-xs font-medium text-purple-200 uppercase">
                                                    Created
                                                </th>
                                                <th className="px-4 py-3 text-left text-xs font-medium text-purple-200 uppercase">
                                                    Actions
                                                </th>
                                            </tr>
                                        </thead>
                                        <tbody className="divide-y divide-white/10">
                                            {(payoutsData.payouts ?? []).map((payout) => (
                                                <tr key={payout.id} className="hover:bg-white/5">
                                                    <td className="px-4 py-3 text-white font-mono text-sm">
                                                        {payout.order_id}
                                                    </td>
                                                    <td className="px-4 py-3 text-white font-medium">
                                                        ₹{payout.amount.toFixed(2)}
                                                    </td>
                                                    <td className="px-4 py-3">
                                                        <span
                                                            className={`px-2 py-1 rounded text-xs font-medium ${getPayoutStatusColor(
                                                                payout.status
                                                            )}`}
                                                        >
                                                            {payout.status}
                                                        </span>
                                                    </td>
                                                    <td className="px-4 py-3 text-white text-sm max-w-[200px]">
                                                        <div>{payout.payout_method || "—"}</div>
                                                        <div className="text-purple-300 font-mono text-xs truncate">
                                                            {payout.payout_reference || "—"}
                                                        </div>
                                                    </td>
                                                    <td className="px-4 py-3 text-white text-sm">
                                                        {new Date(payout.created_at).toLocaleDateString()}
                                                    </td>
                                                    <td className="px-4 py-3">
                                                        {(payout.status === "pending" ||
                                                            payout.status === "failed") && (
                                                            <div className="flex gap-2 flex-wrap">
                                                                <button
                                                                    type="button"
                                                                    onClick={() =>
                                                                        handleUpdatePayout(payout.id, "paid")
                                                                    }
                                                                    disabled={updating === payout.id}
                                                                    className="text-green-400 hover:text-green-300 font-medium disabled:opacity-50"
                                                                >
                                                                    {updating === payout.id
                                                                        ? "…"
                                                                        : "Mark paid"}
                                                                </button>
                                                                {payout.status === "pending" && (
                                                                    <button
                                                                        type="button"
                                                                        onClick={() =>
                                                                            handleUpdatePayout(
                                                                                payout.id,
                                                                                "failed"
                                                                            )
                                                                        }
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
                                {payoutsData.total_pages > 1 && (
                                    <div className="px-4 py-3 flex justify-between items-center border-t border-white/10">
                                        <span className="text-purple-200 text-sm">
                                            Page {payoutsData.page} of {payoutsData.total_pages}
                                        </span>
                                        <div className="flex gap-2">
                                            <button
                                                type="button"
                                                onClick={() => setPayoutPage((p) => Math.max(1, p - 1))}
                                                disabled={payoutPage === 1 || payoutsLoading}
                                                className="px-4 py-2 bg-white/10 hover:bg-white/20 text-white rounded-lg disabled:opacity-50"
                                            >
                                                Previous
                                            </button>
                                            <button
                                                type="button"
                                                onClick={() =>
                                                    setPayoutPage((p) =>
                                                        Math.min(payoutsData.total_pages, p + 1)
                                                    )
                                                }
                                                disabled={
                                                    payoutPage === payoutsData.total_pages || payoutsLoading
                                                }
                                                className="px-4 py-2 bg-white/10 hover:bg-white/20 text-white rounded-lg disabled:opacity-50"
                                            >
                                                Next
                                            </button>
                                        </div>
                                    </div>
                                )}
                            </div>
                        ) : null}
                    </>
                )}
            </div>
        </div>
    );
}

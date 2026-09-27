"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import api, {
  getWalletBalance,
  getWalletTransactions,
  topupWallet,
} from "@/lib/api";
import { getSafeErrorMessage } from "@/lib/safeError";
import { openRazorpayCheckout } from "@/lib/razorpay";
import Footer from "@/components/Footer";
import DashboardHeader from "@/components/DashboardHeader";

const MIN_TOPUP = 10;
const MAX_TOPUP = 10000;

type WalletTransaction = {
  id: number;
  transaction_type: string;
  amount: number;
  balance_after: number;
  status: string;
  description?: string;
  created_at: string;
};

export default function WalletPage() {
  const router = useRouter();
  const [balance, setBalance] = useState<number | null>(null);
  const [balanceLoading, setBalanceLoading] = useState(true);
  const [transactions, setTransactions] = useState<WalletTransaction[]>([]);
  const [transactionsLoading, setTransactionsLoading] = useState(true);
  const [totalTransactions, setTotalTransactions] = useState(0);
  const [displayName, setDisplayName] = useState("");
  const [topupAmount, setTopupAmount] = useState("");
  const [topupLoading, setTopupLoading] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    const token = localStorage.getItem("token") || sessionStorage.getItem("token");
    const role = localStorage.getItem("role");
    if (!token || !role) {
      router.push("/login");
      return;
    }
    const storedName = (localStorage.getItem("display_name") || localStorage.getItem("username") || "").trim();
    const safeName = storedName && storedName.toLowerCase() !== "undefined" && storedName.toLowerCase() !== "null"
      ? storedName
      : "Customer";
    setDisplayName(safeName);
    fetchBalance();
    fetchTransactions();
  }, [router]);

  const fetchBalance = async () => {
    setBalanceLoading(true);
    setError("");
    try {
      const data = await getWalletBalance();
      setBalance(data.balance ?? 0);
    } catch (err) {
      console.error("Wallet balance error:", err);
      setError(getSafeErrorMessage(err, "wallet"));
      if ((err as any)?.response?.status === 401) {
        router.push("/login");
        return;
      }
      setBalance(0);
    } finally {
      setBalanceLoading(false);
    }
  };

  const fetchTransactions = async (offset = 0) => {
    if (offset === 0) setTransactionsLoading(true);
    try {
      const data = await getWalletTransactions({ limit: 50, offset });
      setTransactions(data.transactions ?? []);
      setTotalTransactions(data.total ?? 0);
    } catch (err) {
      console.error("Wallet transactions error:", err);
      if (offset === 0) setError(getSafeErrorMessage(err, "wallet"));
    } finally {
      if (offset === 0) setTransactionsLoading(false);
    }
  };

  const handleAddMoney = async (e: React.FormEvent) => {
    e.preventDefault();
    const amount = parseFloat(topupAmount);
    if (Number.isNaN(amount) || amount < MIN_TOPUP || amount > MAX_TOPUP) {
      setError(`Amount must be between ₹${MIN_TOPUP} and ₹${MAX_TOPUP}`);
      return;
    }
    setTopupLoading(true);
    setError("");
    try {
      const { order_id, key_id, amount: amt } = await topupWallet(amount);
      await openRazorpayCheckout({
        key: key_id,
        amount: amt * 100,
        order_id,
        name: "Qprint",
        description: "Add money to wallet",
        handler: async () => {
          setTopupAmount("");
          await fetchBalance();
          await fetchTransactions(0);
        },
        onError: (err) => {
          console.error("Razorpay error:", err);
          setError(getSafeErrorMessage(err, "payment"));
        },
      });
    } catch (err) {
      console.error("Top-up error:", err);
      setError(getSafeErrorMessage(err, "wallet"));
    } finally {
      setTopupLoading(false);
    }
  };

  const handleLogout = async () => {
    await api.post("/logout").catch(() => {});
    if (typeof window !== "undefined") {
      localStorage.removeItem("token");
      localStorage.removeItem("role");
      localStorage.removeItem("display_name");
      localStorage.removeItem("username");
      sessionStorage.removeItem("token");
    }
    router.push("/");
  };

  const formatDate = (s: string) => {
    try {
      const d = new Date(s);
      return d.toLocaleString(undefined, {
        dateStyle: "short",
        timeStyle: "short",
      });
    } catch {
      return s;
    }
  };

  const typeLabel = (type: string) => {
    switch (type) {
      case "topup": return "Add money";
      case "payment": return "Payment";
      case "refund": return "Refund";
      case "withdrawal": return "Withdrawal";
      case "referral_bonus": return "Referral bonus";
      case "referral_welcome": return "Welcome bonus";
      default: return type;
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800">
      <DashboardHeader
        displayName={displayName}
        role="customer"
        onLogout={handleLogout}
      />
      <div className="p-6 pt-8">
        <div className="max-w-3xl mx-auto space-y-6">
          <div className="flex items-center justify-between">
            <h1 className="text-2xl font-bold text-white flex items-center gap-2">
              <span className="text-3xl">👛</span> Wallet
            </h1>
            <Link
              href="/customer/dashboard"
              className="px-4 py-2 bg-white/10 text-white rounded-lg hover:bg-white/20 transition-all text-sm font-medium"
            >
              ← Dashboard
            </Link>
          </div>

          {error && (
            <div className="bg-red-500/20 border border-red-400/50 rounded-lg p-4 text-red-200 text-sm">
              {error}
            </div>
          )}

          <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-8 border border-white/20">
            <p className="text-purple-200 text-sm mb-2">Available balance</p>
            {balanceLoading ? (
              <p className="text-white text-2xl font-bold">Loading...</p>
            ) : (
              <p className="text-white text-4xl font-bold">
                ₹{(balance ?? 0).toFixed(2)}
              </p>
            )}
          </div>

          <Link
            href="/customer/refer"
            className="block bg-purple-600/30 backdrop-blur-lg rounded-2xl p-4 border border-purple-300/30 hover:bg-purple-600/40 transition-colors"
          >
            <div className="flex items-center gap-4">
              <span className="text-3xl">🎁</span>
              <div className="flex-1">
                <p className="text-white font-semibold">Earn by referring friends</p>
                <p className="text-purple-200 text-sm">Share your code, get wallet credit when they print.</p>
              </div>
              <span className="text-white/60">→</span>
            </div>
          </Link>

          <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-8 border border-white/20">
            <h2 className="text-lg font-bold text-white mb-4">Add money</h2>
            <form onSubmit={handleAddMoney} className="flex flex-col sm:flex-row gap-4">
              <input
                type="number"
                min={MIN_TOPUP}
                max={MAX_TOPUP}
                step="1"
                placeholder={`₹${MIN_TOPUP} – ₹${MAX_TOPUP}`}
                value={topupAmount}
                onChange={(e) => {
                  setTopupAmount(e.target.value);
                  setError("");
                }}
                className="flex-1 bg-white/20 border border-white/30 p-3 rounded-lg text-white placeholder-white/50 focus:outline-none focus:ring-2 focus:ring-pink-500"
              />
              <button
                type="submit"
                disabled={topupLoading}
                className="px-6 py-3 bg-gradient-to-r from-pink-500 to-purple-600 text-white font-semibold rounded-lg hover:from-pink-600 hover:to-purple-700 transition-all disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {topupLoading ? "Processing…" : "Add money"}
              </button>
            </form>
            <p className="text-white/60 text-xs mt-2">
              Min ₹{MIN_TOPUP}, max ₹{MAX_TOPUP}. Secure payment via Razorpay.
            </p>
          </div>

          <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-8 border border-white/20">
            <h2 className="text-lg font-bold text-white mb-4">Recent transactions</h2>
            {transactionsLoading ? (
              <p className="text-purple-200">Loading…</p>
            ) : transactions.length === 0 ? (
              <p className="text-purple-200">No transactions yet.</p>
            ) : (
              <ul className="space-y-3 max-h-[400px] overflow-y-auto">
                {transactions.map((t) => (
                  <li
                    key={t.id}
                    className="flex items-center justify-between py-3 border-b border-white/10 last:border-0"
                  >
                    <div>
                      <span className="text-white font-medium">{typeLabel(t.transaction_type)}</span>
                      {t.description && (
                        <span className="text-white/60 text-sm ml-2">{t.description}</span>
                      )}
                      <p className="text-white/50 text-xs mt-0.5">{formatDate(t.created_at)}</p>
                    </div>
                    <div className="text-right">
                      <span className={t.amount >= 0 ? "text-green-400" : "text-red-400"}>
                        {t.amount >= 0 ? "+" : ""}₹{t.amount.toFixed(2)}
                      </span>
                      <p className="text-white/50 text-xs">Balance: ₹{t.balance_after.toFixed(2)}</p>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </div>
      </div>
      <Footer />
    </div>
  );
}

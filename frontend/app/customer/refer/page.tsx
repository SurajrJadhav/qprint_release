"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import api, { getProfile, getReferralSummary, getReferralHistory, inviteByEmail } from "@/lib/api";
import { getSafeErrorMessage } from "@/lib/safeError";
import Footer from "@/components/Footer";
import DashboardHeader from "@/components/DashboardHeader";

type ReferralItem = {
  id: number;
  status: string;
  amount: number;
  credited_at: string | null;
  created_at: string;
};

export default function ReferPage() {
  const router = useRouter();
  const [referralCode, setReferralCode] = useState<string | null>(null);
  const [referralLink, setReferralLink] = useState<string | null>(null);
  const [totalReferred, setTotalReferred] = useState(0);
  const [totalCredited, setTotalCredited] = useState(0);
  const [totalEarnings, setTotalEarnings] = useState(0);
  const [pendingCount, setPendingCount] = useState(0);
  const [history, setHistory] = useState<ReferralItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [statsError, setStatsError] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [inviteEmail, setInviteEmail] = useState("");
  const [inviteLoading, setInviteLoading] = useState(false);
  const [inviteSuccess, setInviteSuccess] = useState("");

  useEffect(() => {
    const token = localStorage.getItem("token") || sessionStorage.getItem("token");
    const role = localStorage.getItem("role");
    if (!token || role !== "customer") {
      router.push("/login");
      return;
    }
    const storedName = (localStorage.getItem("display_name") || localStorage.getItem("username") || "").trim();
    const safeName = storedName && storedName.toLowerCase() !== "undefined" && storedName.toLowerCase() !== "null"
      ? storedName
      : "Customer";
    setDisplayName(safeName);
    load();
  }, [router]);

  const load = async () => {
    setLoading(true);
    setError("");
    setStatsError("");
    try {
      // Load profile first so referral code/link are always shown (including for accounts created via referral)
      const profile = await getProfile();
      setReferralCode((profile.referral_code as string) ?? null);
      setReferralLink((profile.referral_link as string) ?? null);
    } catch (err) {
      setError(getSafeErrorMessage(err, "referral"));
      if ((err as { response?: { status?: number } })?.response?.status === 401) {
        router.push("/login");
      }
      setLoading(false);
      return;
    }
    try {
      const [summary, historyData] = await Promise.all([
        getReferralSummary(),
        getReferralHistory({ limit: 30, offset: 0 }),
      ]);
      setTotalReferred(summary.total_referred ?? 0);
      setTotalCredited(summary.total_credited ?? 0);
      setTotalEarnings(summary.total_earnings ?? 0);
      setPendingCount(summary.pending_count ?? 0);
      setHistory((historyData.referrals as ReferralItem[]) ?? []);
    } catch (err) {
      setStatsError("Stats temporarily unavailable.");
      setHistory([]);
    } finally {
      setLoading(false);
    }
  };

  const copyCode = () => {
    if (!referralCode) return;
    navigator.clipboard.writeText(referralCode);
    if (typeof window !== "undefined") {
      window.getSelection?.()?.removeAllRanges?.();
    }
    alert("Referral code copied!");
  };

  const copyLink = () => {
    const link = referralLink || (referralCode ? `${typeof window !== "undefined" ? window.location.origin : ""}/r/${referralCode}` : "");
    if (!link) return;
    navigator.clipboard.writeText(link);
    alert("Link copied!");
  };

  const share = async () => {
    const link = referralLink || (referralCode && typeof window !== "undefined" ? `${window.location.origin}/r/${referralCode}` : "");
    if (!link) return;
    const text = "Use my qprint referral link to sign up and get prints easily. You'll get a welcome bonus too!\n" + link;
    if (navigator.share) {
      try {
        await navigator.share({
          title: "Join qprint",
          text,
          url: link,
        });
      } catch (e) {
        copyLink();
      }
    } else {
      copyLink();
    }
  };

  const handleInviteByEmail = async (e: React.FormEvent) => {
    e.preventDefault();
    const email = inviteEmail.trim().toLowerCase();
    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      setError("Please enter a valid email address.");
      return;
    }
    setInviteLoading(true);
    setError("");
    setInviteSuccess("");
    try {
      await inviteByEmail(email);
      setInviteSuccess(`Invite sent to ${email}`);
      setInviteEmail("");
    } catch (err) {
      const msg = (err as { response?: { status?: number; data?: { message?: string } } })?.response?.data?.message
        || getSafeErrorMessage(err, "referral");
      setError(msg);
      if ((err as { response?: { status?: number } })?.response?.status === 429) {
        setError("Daily invite limit reached. Try again tomorrow.");
      }
    } finally {
      setInviteLoading(false);
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
      return new Date(s).toLocaleDateString(undefined, { dateStyle: "short" });
    } catch {
      return s;
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800">
      <DashboardHeader displayName={displayName} role="customer" onLogout={handleLogout} />
      <div className="p-6 pt-8">
        <div className="max-w-3xl mx-auto space-y-6">
          <div className="flex items-center justify-between">
            <h1 className="text-2xl font-bold text-white flex items-center gap-2">
              <span className="text-3xl">🎁</span> Refer & Earn
            </h1>
            <Link
              href="/customer/dashboard"
              className="px-4 py-2 bg-white/10 text-white rounded-lg hover:bg-white/20 transition-all text-sm font-medium"
            >
              ← Dashboard
            </Link>
          </div>

          {error && (
            <div className="bg-red-500/20 border border-red-400/50 rounded-lg p-4 text-red-200 text-sm space-y-3">
              <p>{error}</p>
              <button
                type="button"
                onClick={load}
                className="px-4 py-2 bg-white/20 text-white rounded-lg hover:bg-white/30 transition-colors text-sm font-medium"
              >
                Retry
              </button>
            </div>
          )}

          {loading ? (
            <div className="text-purple-200">Loading…</div>
          ) : (
            <>
              <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-8 border border-white/20 text-center">
                <p className="text-purple-200 text-sm mb-2">Your referral code</p>
                <p className="text-white text-3xl font-bold tracking-widest mb-6">
                  {referralCode ?? "—"}
                </p>
                <div className="flex flex-wrap justify-center gap-3">
                  <button
                    type="button"
                    onClick={copyCode}
                    disabled={!referralCode}
                    className="px-5 py-2.5 bg-white/20 text-white rounded-xl hover:bg-white/30 transition-colors disabled:opacity-50"
                  >
                    Copy code
                  </button>
                  <button
                    type="button"
                    onClick={copyLink}
                    disabled={!referralLink && !referralCode}
                    className="px-5 py-2.5 bg-white/20 text-white rounded-xl hover:bg-white/30 transition-colors disabled:opacity-50"
                  >
                    Copy link
                  </button>
                  <button
                    type="button"
                    onClick={share}
                    disabled={!referralLink && !referralCode}
                    className="px-5 py-2.5 bg-pink-500 text-white rounded-xl hover:bg-pink-600 transition-colors disabled:opacity-50"
                  >
                    Share
                  </button>
                </div>
              </div>

              <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 border border-white/20">
                <h2 className="text-lg font-bold text-white mb-3">Invite by email</h2>
                <p className="text-purple-200 text-sm mb-4">We’ll send your referral link to a friend (via Resend).</p>
                <form onSubmit={handleInviteByEmail} className="flex flex-col sm:flex-row gap-3">
                  <input
                    type="email"
                    placeholder="Friend’s email"
                    value={inviteEmail}
                    onChange={(e) => setInviteEmail(e.target.value)}
                    className="flex-1 bg-white/20 border border-white/30 px-4 py-2.5 rounded-xl text-white placeholder-purple-200 focus:outline-none focus:ring-2 focus:ring-pink-500"
                    disabled={inviteLoading}
                  />
                  <button
                    type="submit"
                    disabled={inviteLoading || !referralCode}
                    className="px-5 py-2.5 bg-pink-500 text-white rounded-xl hover:bg-pink-600 transition-colors disabled:opacity-50 font-medium"
                  >
                    {inviteLoading ? "Sending…" : "Send invite"}
                  </button>
                </form>
                {inviteSuccess && (
                  <p className="text-green-300 text-sm mt-2">{inviteSuccess}</p>
                )}
              </div>

              <p className="text-white/50 text-sm text-center">
                By sharing you agree to our{" "}
                <Link href="/terms" className="underline hover:text-white">Terms & Conditions</Link>.
              </p>

              <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 border border-white/20">
                <h2 className="text-lg font-bold text-white mb-4">Your referral stats</h2>
                {statsError && (
                  <p className="text-amber-200 text-sm mb-4">{statsError}</p>
                )}
                <div className="grid grid-cols-3 gap-4 text-center">
                  <div>
                    <p className="text-2xl font-bold text-white">{totalReferred}</p>
                    <p className="text-purple-200 text-sm">Referred</p>
                  </div>
                  <div>
                    <p className="text-2xl font-bold text-white">{totalCredited}</p>
                    <p className="text-purple-200 text-sm">Completed</p>
                  </div>
                  <div>
                    <p className="text-2xl font-bold text-white">₹{totalEarnings.toFixed(0)}</p>
                    <p className="text-purple-200 text-sm">Earned</p>
                  </div>
                </div>
                {pendingCount > 0 && (
                  <p className="text-purple-200 text-sm mt-4">
                    {pendingCount} friend(s) signed up — when they complete their first print or top-up, you get the bonus.
                  </p>
                )}
              </div>

              <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 border border-white/20">
                <h2 className="text-lg font-bold text-white mb-4">Recent referrals</h2>
                {history.length === 0 ? (
                  <p className="text-purple-200">No referrals yet. Share your code with friends!</p>
                ) : (
                  <ul className="space-y-3">
                    {history.map((r) => (
                      <li
                        key={r.id}
                        className="flex items-center justify-between py-3 border-b border-white/10 last:border-0"
                      >
                        <div className="flex items-center gap-3">
                          <span
                            className={`w-10 h-10 rounded-full flex items-center justify-center ${
                              r.status === "credited" ? "bg-green-500/30 text-green-300" : "bg-purple-500/30 text-purple-300"
                            }`}
                          >
                            {r.status === "credited" ? "✓" : "○"}
                          </span>
                          <div>
                            <p className="text-white font-medium">
                              {r.status === "credited" ? "Bonus earned" : "Pending"}
                            </p>
                            <p className="text-white/50 text-xs">{formatDate(r.created_at)}</p>
                          </div>
                        </div>
                        {r.status === "credited" && r.amount > 0 && (
                          <span className="text-green-400 font-semibold">+₹{r.amount.toFixed(0)}</span>
                        )}
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            </>
          )}
        </div>
      </div>
      <Footer />
    </div>
  );
}

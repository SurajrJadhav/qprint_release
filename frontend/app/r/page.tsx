"use client";

import { Suspense, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Link from "next/link";
import { getAppDownloads, AppDownloadLinks } from "@/lib/api";

/**
 * Referral landing: /r/XXX (path) or /r?code=XXX (query).
 * Vercel rewrite sends /r/:code -> /r?code=:code internally but browser URL stays /r/XXX, so we read code from pathname too.
 * Redirects to register with referral_code; "Create account" link passes it so register page auto-fills.
 */
function ReferralLandingContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [appLinks, setAppLinks] = useState<AppDownloadLinks | null>(null);
  const [codeFromPath, setCodeFromPath] = useState("");
  const [pathChecked, setPathChecked] = useState(false);

  // Code from query (?code=) or from path (/r/XXX) — path is set on client since rewrite keeps browser URL as /r/XXX
  const codeFromQuery = searchParams?.get("code")?.trim() ?? "";
  const code = codeFromQuery || codeFromPath;

  useEffect(() => {
    const match = typeof window !== "undefined" && window.location.pathname.match(/^\/r\/([^/]+)$/);
    if (match) setCodeFromPath(decodeURIComponent(match[1]).trim());
    setPathChecked(true);
  }, []);

  useEffect(() => {
    if (code) {
      router.replace(`/register?referral_code=${encodeURIComponent(code)}`);
    }
  }, [code, router]);

  useEffect(() => {
    getAppDownloads()
      .then(setAppLinks)
      .catch(() => setAppLinks(null));
  }, []);

  const base = appLinks || {
    windows_shopkeeper_url: "",
    android_customer_url: "",
    ios_customer_url: "",
    windows_coming_soon: true,
    android_coming_soon: true,
    ios_coming_soon: true,
  };
  const hasAndroid = !base.android_coming_soon && !!base.android_customer_url;
  const hasIos = !base.ios_coming_soon && !!base.ios_customer_url;
  const showDownloadBlock = hasAndroid || hasIos;

  return (
    <div className="min-h-screen flex flex-col items-center justify-center p-6 bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800">
      <div className="text-center max-w-md w-full space-y-8">
        <div>
          <h1 className="text-4xl font-black text-white mb-2">
            Q<span className="text-pink-400">print</span>
          </h1>
          <p className="text-purple-200 mb-6">You were referred by a friend.</p>
          {code ? (
            <p className="text-white/80 text-sm mb-6">Redirecting you to sign up with the referral code...</p>
          ) : pathChecked ? (
            <p className="text-white/80 text-sm mb-6">Invalid referral link.</p>
          ) : (
            <p className="text-white/80 text-sm mb-6">Loading...</p>
          )}
          <Link
            href={code ? `/register?referral_code=${encodeURIComponent(code)}` : "/register"}
            className="inline-block px-6 py-3 rounded-xl bg-pink-500 hover:bg-pink-600 text-white font-semibold transition-colors"
          >
            Create account
          </Link>
        </div>

        {showDownloadBlock && (
          <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 border border-white/20 text-center">
            <h2 className="text-lg font-bold text-white mb-3">Or get the app</h2>
            <p className="text-purple-200 text-sm mb-4">Use the app on your phone for the best experience.</p>
            <div className="flex flex-col sm:flex-row gap-3 justify-center">
              {hasAndroid && (
                <a
                  href={base.android_customer_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center justify-center gap-2 px-5 py-3 rounded-xl bg-green-600 hover:bg-green-700 text-white font-semibold transition-colors"
                >
                  <span>📱</span> Google Play
                </a>
              )}
              {hasIos && (
                <a
                  href={base.ios_customer_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center justify-center gap-2 px-5 py-3 rounded-xl bg-indigo-600 hover:bg-indigo-700 text-white font-semibold transition-colors"
                >
                  <span>🍎</span> App Store
                </a>
              )}
            </div>
          </div>
        )}

        <p className="text-white/60 text-sm">
          <Link href="/" className="underline hover:text-white">Back to home</Link>
        </p>
      </div>
    </div>
  );
}

export default function ReferralLandingPage() {
  return (
    <Suspense fallback={
      <div className="min-h-screen flex flex-col items-center justify-center p-6 bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800">
        <p className="text-white/80">Loading...</p>
      </div>
    }>
      <ReferralLandingContent />
    </Suspense>
  );
}

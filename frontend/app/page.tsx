"use client";

import Link from 'next/link';
import { useEffect, useState } from 'react';
import Footer from '@/components/Footer';

export default function HomePage() {
    const [mounted, setMounted] = useState(false);

    useEffect(() => {
        setMounted(true);
    }, []);

    return (
        <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800 relative overflow-hidden">
            {/* Animated background elements */}
            <div className="absolute inset-0 overflow-hidden">
                <div className="absolute -top-40 -right-40 w-80 h-80 bg-purple-500 rounded-full mix-blend-multiply filter blur-xl opacity-20 animate-blob"></div>
                <div className="absolute -bottom-40 -left-40 w-80 h-80 bg-pink-500 rounded-full mix-blend-multiply filter blur-xl opacity-20 animate-blob animation-delay-2000"></div>
                <div className="absolute top-1/2 left-1/2 transform -translate-x-1/2 -translate-y-1/2 w-80 h-80 bg-indigo-500 rounded-full mix-blend-multiply filter blur-xl opacity-20 animate-blob animation-delay-4000"></div>
            </div>

            {/* Hero Section */}
            <div id="home" className="relative z-10 flex flex-col items-center justify-center min-h-screen px-4 py-12">
                {/* Logo and Brand */}
                <div className={`text-center mb-12 transition-all duration-1000 ${mounted ? 'opacity-100 translate-y-0' : 'opacity-0 -translate-y-10'}`}>
                    <div className="inline-block mb-6">
                        <div className="relative">
                            <h1 className="text-7xl md:text-8xl font-black text-white mb-2 tracking-tight">
                                Q<span className="text-pink-400">print</span>
                            </h1>
                            <div className="absolute -bottom-2 left-0 right-0 h-1 bg-gradient-to-r from-pink-500 via-purple-500 to-indigo-500 rounded-full"></div>
                        </div>
                    </div>

                    <p className="text-2xl md:text-3xl text-white font-light mb-4">
                        Print Without Standing in Queue
                    </p>
                    <p className="text-lg md:text-xl text-purple-200 max-w-2xl mx-auto mb-6">
                        Two convenient ways to print: Queue Print for scheduled pickups or Private Print for instant collection at any shop
                    </p>
                </div>

                {/* Feature Cards */}
                <div className={`grid md:grid-cols-3 gap-6 mb-12 max-w-5xl w-full transition-all duration-1000 delay-300 ${mounted ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-10'}`}>
                    <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 border border-white/20 hover:bg-white/20 transition-all duration-300 hover:scale-105">
                        <div className="text-4xl mb-4">📤</div>
                        <h3 className="text-xl font-bold text-white mb-2">Upload Anywhere</h3>
                        <p className="text-purple-200">Upload PDF or image files from home, office, or on the go</p>
                    </div>

                    <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 border border-white/20 hover:bg-white/20 transition-all duration-300 hover:scale-105">
                        <div className="text-4xl mb-4">📍</div>
                        <h3 className="text-xl font-bold text-white mb-2">Choose Your Way</h3>
                        <p className="text-purple-200">Queue Print or Private Print - pick what works for you</p>
                    </div>

                    <div className="bg-white/10 backdrop-blur-lg rounded-2xl p-6 border border-white/20 hover:bg-white/20 transition-all duration-300 hover:scale-105">
                        <div className="text-4xl mb-4">🖨️</div>
                        <h3 className="text-xl font-bold text-white mb-2">Collect Prints</h3>
                        <p className="text-purple-200">Track queue position or use OTP code to collect instantly</p>
                    </div>
                </div>

                {/* CTA Buttons */}
                <div className={`flex flex-col sm:flex-row gap-4 transition-all duration-1000 delay-500 ${mounted ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-10'}`}>
                    <Link
                        href="/register"
                        className="group relative px-8 py-4 bg-gradient-to-r from-pink-500 to-purple-600 text-white font-bold text-lg rounded-full hover:from-pink-600 hover:to-purple-700 transition-all duration-300 shadow-lg hover:shadow-2xl hover:scale-105"
                    >
                        <span className="relative z-10">Get Started</span>
                        <div className="absolute inset-0 bg-white/20 rounded-full opacity-0 group-hover:opacity-100 transition-opacity duration-300"></div>
                    </Link>

                    <Link
                        href="/login"
                        className="px-8 py-4 bg-white/10 backdrop-blur-lg text-white font-bold text-lg rounded-full border-2 border-white/30 hover:bg-white/20 transition-all duration-300 shadow-lg hover:shadow-2xl hover:scale-105"
                    >
                        Sign In
                    </Link>

                    <Link
                        href="/download-apps"
                        className="px-8 py-4 bg-white/10 backdrop-blur-lg text-white font-bold text-lg rounded-full border-2 border-white/30 hover:bg-white/20 transition-all duration-300 shadow-lg hover:shadow-2xl hover:scale-105"
                    >
                        Download Apps
                    </Link>
                </div>

                {/* Scroll Indicator */}
                <div className={`mt-16 animate-bounce transition-all duration-1000 delay-700 ${mounted ? 'opacity-100' : 'opacity-0'}`}>
                    <p className="text-purple-200 text-sm mb-2">Scroll to learn more</p>
                    <div className="w-6 h-10 border-2 border-white/30 rounded-full mx-auto flex items-start justify-center p-2">
                        <div className="w-1 h-3 bg-white/50 rounded-full"></div>
                    </div>
                </div>
            </div>

            {/* How It Works Section */}
            <section id="how-it-works" className="relative z-10 py-20 px-4 scroll-mt-20">
                <div className="max-w-6xl mx-auto">
                    <div className="text-center mb-16">
                        <h2 className="text-4xl md:text-5xl font-bold text-white mb-4">
                            How Qprint Works
                        </h2>
                        <p className="text-xl text-purple-200 max-w-2xl mx-auto">
                            Choose the printing method that best fits your needs
                        </p>
                    </div>

                    {/* Queue Print Section */}
                    <div className="mb-20">
                        <div className="bg-white/10 backdrop-blur-lg rounded-3xl p-8 md:p-12 border border-white/20">
                            <div className="flex flex-col md:flex-row items-center gap-8 mb-8">
                                <div className="flex-shrink-0">
                                    <div className="w-24 h-24 bg-blue-500/20 rounded-full flex items-center justify-center">
                                        <span className="text-5xl">📋</span>
                                    </div>
                                </div>
                                <div className="flex-1 text-center md:text-left">
                                    <h3 className="text-3xl md:text-4xl font-bold text-white mb-3">
                                        Queue Print
                                    </h3>
                                    <p className="text-lg text-purple-200">
                                        Perfect when you want to send your print to a specific shop and wait for it to be ready. Track your position in the queue and get notified when your print is done.
                                    </p>
                                </div>
                            </div>

                            <div className="grid md:grid-cols-2 gap-6">
                                <div className="bg-white/5 rounded-xl p-6 border border-white/10">
                                    <div className="flex items-start gap-4">
                                        <div className="flex-shrink-0 w-8 h-8 bg-blue-500/30 rounded-full flex items-center justify-center text-blue-400 font-bold">1</div>
                                        <div>
                                            <h4 className="text-white font-bold mb-2">Select Your File</h4>
                                            <p className="text-purple-200 text-sm">Choose your PDF or image file from your device</p>
                                        </div>
                                    </div>
                                </div>

                                <div className="bg-white/5 rounded-xl p-6 border border-white/10">
                                    <div className="flex items-start gap-4">
                                        <div className="flex-shrink-0 w-8 h-8 bg-blue-500/30 rounded-full flex items-center justify-center text-blue-400 font-bold">2</div>
                                        <div>
                                            <h4 className="text-white font-bold mb-2">Choose Your Shop</h4>
                                            <p className="text-purple-200 text-sm">Select your preferred shop from the list</p>
                                        </div>
                                    </div>
                                </div>

                                <div className="bg-white/5 rounded-xl p-6 border border-white/10">
                                    <div className="flex items-start gap-4">
                                        <div className="flex-shrink-0 w-8 h-8 bg-blue-500/30 rounded-full flex items-center justify-center text-blue-400 font-bold">3</div>
                                        <div>
                                            <h4 className="text-white font-bold mb-2">Configure Settings</h4>
                                            <p className="text-purple-200 text-sm">Set color mode, paper size, copies, and print mode</p>
                                        </div>
                                    </div>
                                </div>

                                <div className="bg-white/5 rounded-xl p-6 border border-white/10">
                                    <div className="flex items-start gap-4">
                                        <div className="flex-shrink-0 w-8 h-8 bg-blue-500/30 rounded-full flex items-center justify-center text-blue-400 font-bold">4</div>
                                        <div>
                                            <h4 className="text-white font-bold mb-2">Track & Collect</h4>
                                            <p className="text-purple-200 text-sm">Monitor your queue position and get status updates. Visit the shop when ready!</p>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>

                    {/* Private Print Section */}
                    <div className="mb-20">
                        <div className="bg-white/10 backdrop-blur-lg rounded-3xl p-8 md:p-12 border border-white/20">
                            <div className="flex flex-col md:flex-row items-center gap-8 mb-8">
                                <div className="flex-shrink-0">
                                    <div className="w-24 h-24 bg-purple-500/20 rounded-full flex items-center justify-center">
                                        <span className="text-5xl">🔒</span>
                                    </div>
                                </div>
                                <div className="flex-1 text-center md:text-left">
                                    <h3 className="text-3xl md:text-4xl font-bold text-white mb-3">
                                        Private Print
                                    </h3>
                                    <p className="text-lg text-purple-200">
                                        Upload your file, get a unique OTP code, visit any registered shop from the map, share your code, and collect your prints instantly!
                                    </p>
                                </div>
                            </div>

                            <div className="grid md:grid-cols-2 gap-6">
                                <div className="bg-white/5 rounded-xl p-6 border border-white/10">
                                    <div className="flex items-start gap-4">
                                        <div className="flex-shrink-0 w-8 h-8 bg-purple-500/30 rounded-full flex items-center justify-center text-purple-400 font-bold">1</div>
                                        <div>
                                            <h4 className="text-white font-bold mb-2">Upload Your File</h4>
                                            <p className="text-purple-200 text-sm">Select your PDF or image file and configure print settings</p>
                                        </div>
                                    </div>
                                </div>

                                <div className="bg-white/5 rounded-xl p-6 border border-white/10">
                                    <div className="flex items-start gap-4">
                                        <div className="flex-shrink-0 w-8 h-8 bg-purple-500/30 rounded-full flex items-center justify-center text-purple-400 font-bold">2</div>
                                        <div>
                                            <h4 className="text-white font-bold mb-2">Get Your OTP Code</h4>
                                            <p className="text-purple-200 text-sm">Receive a unique code after successful upload</p>
                                        </div>
                                    </div>
                                </div>

                                <div className="bg-white/5 rounded-xl p-6 border border-white/10">
                                    <div className="flex items-start gap-4">
                                        <div className="flex-shrink-0 w-8 h-8 bg-purple-500/30 rounded-full flex items-center justify-center text-purple-400 font-bold">3</div>
                                        <div>
                                            <h4 className="text-white font-bold mb-2">View Shops on Map</h4>
                                            <p className="text-purple-200 text-sm">Open the map view to see all registered shops near you</p>
                                        </div>
                                    </div>
                                </div>

                                <div className="bg-white/5 rounded-xl p-6 border border-white/10">
                                    <div className="flex items-start gap-4">
                                        <div className="flex-shrink-0 w-8 h-8 bg-purple-500/30 rounded-full flex items-center justify-center text-purple-400 font-bold">4</div>
                                        <div>
                                            <h4 className="text-white font-bold mb-2">Visit & Collect</h4>
                                            <p className="text-purple-200 text-sm">Go to any shop, share your OTP code, and collect your prints instantly</p>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </section>

            {/* Features Section */}
            <section id="features" className="relative z-10 py-20 px-4 bg-white/5 scroll-mt-20">
                <div className="max-w-6xl mx-auto">
                    <div className="text-center mb-16">
                        <h2 className="text-4xl md:text-5xl font-bold text-white mb-4">
                            Why Choose Qprint?
                        </h2>
                    </div>

                    <div className="grid md:grid-cols-3 gap-8">
                        <div className="text-center">
                            <div className="text-5xl mb-4">⚡</div>
                            <h3 className="text-2xl font-bold text-white mb-3">Fast & Convenient</h3>
                            <p className="text-purple-200">No more waiting in long queues. Upload from anywhere and collect when ready.</p>
                        </div>

                        <div className="text-center">
                            <div className="text-5xl mb-4">🔐</div>
                            <h3 className="text-2xl font-bold text-white mb-3">Secure</h3>
                            <p className="text-purple-200">Unique OTP codes ensure your prints are secure and only accessible by you.</p>
                        </div>

                        <div className="text-center">
                            <div className="text-5xl mb-4">📍</div>
                            <h3 className="text-2xl font-bold text-white mb-3">Flexible</h3>
                            <p className="text-purple-200">Choose any registered shop for Private Print or select a specific shop for Queue Print.</p>
                        </div>

                        <div className="text-center">
                            <div className="text-5xl mb-4">📊</div>
                            <h3 className="text-2xl font-bold text-white mb-3">Track Everything</h3>
                            <p className="text-purple-200">Monitor queue positions, track expenses, and view your print history.</p>
                        </div>

                        <div className="text-center">
                            <div className="text-5xl mb-4">⭐</div>
                            <h3 className="text-2xl font-bold text-white mb-3">Favorite Shops</h3>
                            <p className="text-purple-200">Save your preferred shops for quick access and easy printing.</p>
                        </div>

                        <div className="text-center">
                            <div className="text-5xl mb-4">💳</div>
                            <h3 className="text-2xl font-bold text-white mb-3">Easy Payments</h3>
                            <p className="text-purple-200">Secure payment processing with real-time cost calculation.</p>
                        </div>
                    </div>
                </div>
            </section>

            {/* Final CTA Section */}
            <section className="relative z-10 py-20 px-4">
                <div className="max-w-4xl mx-auto text-center">
                    <h2 className="text-4xl md:text-5xl font-bold text-white mb-6">
                        Ready to Get Started?
                    </h2>
                    <p className="text-xl text-purple-200 mb-8">
                        Join thousands of users who are already printing smarter with Qprint
                    </p>
                    <div className="flex flex-col sm:flex-row gap-4 justify-center">
                        <Link
                            href="/register"
                            className="px-8 py-4 bg-gradient-to-r from-pink-500 to-purple-600 text-white font-bold text-lg rounded-full hover:from-pink-600 hover:to-purple-700 transition-all duration-300 shadow-lg hover:shadow-2xl hover:scale-105"
                        >
                            Create Free Account
                        </Link>
                        <Link
                            href="/login"
                            className="px-8 py-4 bg-white/10 backdrop-blur-lg text-white font-bold text-lg rounded-full border-2 border-white/30 hover:bg-white/20 transition-all duration-300 shadow-lg hover:shadow-2xl hover:scale-105"
                        >
                            Sign In
                        </Link>
                    </div>
                </div>
            </section>

            {/* Footer */}
            <Footer />

            {/* Custom animations */}
            <style jsx>{`
        @keyframes blob {
          0%, 100% {
            transform: translate(0, 0) scale(1);
          }
          33% {
            transform: translate(30px, -50px) scale(1.1);
          }
          66% {
            transform: translate(-20px, 20px) scale(0.9);
          }
        }
        .animate-blob {
          animation: blob 7s infinite;
        }
        .animation-delay-2000 {
          animation-delay: 2s;
        }
        .animation-delay-4000 {
          animation-delay: 4s;
        }
      `}</style>
        </div>
    );
}

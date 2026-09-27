import Link from 'next/link';

export default function Footer() {
    return (
        <footer className="bg-gray-900/50 backdrop-blur-lg border-t border-white/10 mt-auto">
            <div className="max-w-7xl mx-auto px-4 py-8">
                <div className="grid grid-cols-1 md:grid-cols-4 gap-8">
                    {/* Brand */}
                    <div>
                        <h3 className="text-xl font-bold text-white mb-4">
                            Q<span className="text-pink-400">print</span>
                        </h3>
                        <p className="text-gray-400 text-sm">
                            Print Without Standing in Queue
                        </p>
                    </div>

                    {/* Quick Links */}
                    <div>
                        <h4 className="text-white font-semibold mb-4">Quick Links</h4>
                        <ul className="space-y-2">
                            <li>
                                <Link href="/contact" className="text-gray-400 hover:text-purple-300 text-sm transition-colors">
                                    Contact Us
                                </Link>
                            </li>
                            <li>
                                <Link href="/terms" className="text-gray-400 hover:text-purple-300 text-sm transition-colors">
                                    Terms & Conditions
                                </Link>
                            </li>
                            <li>
                                <Link href="/privacy" className="text-gray-400 hover:text-purple-300 text-sm transition-colors">
                                    Privacy Policy
                                </Link>
                            </li>
                        </ul>
                    </div>

                    {/* Policies */}
                    <div>
                        <h4 className="text-white font-semibold mb-4">Policies</h4>
                        <ul className="space-y-2">
                            <li>
                                <Link href="/refund-policy" className="text-gray-400 hover:text-purple-300 text-sm transition-colors">
                                    Refund Policy
                                </Link>
                            </li>
                            <li>
                                <Link href="/shipping-policy" className="text-gray-400 hover:text-purple-300 text-sm transition-colors">
                                    Shipping Policy
                                </Link>
                            </li>
                        </ul>
                    </div>

                    {/* Contact Info */}
                    <div>
                        <h4 className="text-white font-semibold mb-4">Get Help</h4>
                        <ul className="space-y-2 text-sm text-gray-400">
                            <li>
                                <a href="mailto:support@qprint.co.in" className="hover:text-purple-300 transition-colors">
                                    support@qprint.co.in
                                </a>
                            </li>
                            <li>
                                <a href="tel:+919403447459" className="hover:text-purple-300 transition-colors">
                                    +91-9403447459
                                </a>
                            </li>
                        </ul>
                    </div>
                </div>

                {/* Bottom Bar */}
                <div className="mt-8 pt-6 border-t border-white/10 flex flex-col md:flex-row justify-between items-center">
                    <p className="text-gray-400 text-sm">
                        © {new Date().getFullYear()} Qprint. All rights reserved.
                    </p>
                    <div className="flex gap-6 mt-4 md:mt-0">
                        <Link href="/terms" className="text-gray-400 hover:text-purple-300 text-xs transition-colors">
                            Terms
                        </Link>
                        <Link href="/privacy" className="text-gray-400 hover:text-purple-300 text-xs transition-colors">
                            Privacy
                        </Link>
                        <Link href="/contact" className="text-gray-400 hover:text-purple-300 text-xs transition-colors">
                            Contact
                        </Link>
                    </div>
                </div>
            </div>
        </footer>
    );
}

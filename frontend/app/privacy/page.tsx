import Link from 'next/link';

export default function PrivacyPolicyPage() {
    return (
        <div className="min-h-screen bg-gradient-to-br from-purple-900 via-blue-900 to-indigo-900 text-white p-8">
            <div className="max-w-4xl mx-auto">
                <div className="mb-8">
                    <Link href="/" className="text-purple-300 hover:text-purple-200">
                        ← Back to Home
                    </Link>
                </div>

                <h1 className="text-4xl font-bold mb-8 text-center">Privacy Policy</h1>

                <div className="bg-white/10 backdrop-blur-lg rounded-lg p-8 space-y-8">
                    <section>
                        <p className="text-gray-200 mb-6">
                            <strong>Last Updated:</strong> February 2026
                        </p>
                        <p className="text-gray-200">
                            At Qprint, we are committed to protecting your privacy. This policy explains how we collect,
                            use, and safeguard your personal information across our website and our mobile app (Android and iOS).
                        </p>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">1. Information We Collect</h2>
                        <div className="space-y-4 text-gray-200">
                            <div>
                                <strong className="text-purple-300">Account Information:</strong>
                                <ul className="list-disc list-inside ml-4 mt-2">
                                    <li>Username</li>
                                    <li>Password (stored in hashed form; we never store plain-text passwords)</li>
                                    <li>Role (customer, shopkeeper, or admin)</li>
                                </ul>
                            </div>
                            <div>
                                <strong className="text-purple-300">Location Data:</strong>
                                <ul className="list-disc list-inside ml-4 mt-2">
                                    <li>GPS coordinates (used to find nearest print shops; stored for customers and shopkeepers)</li>
                                    <li>Address (for shopkeepers, to display shop location)</li>
                                </ul>
                            </div>
                            <div>
                                <strong className="text-purple-300">Payment and Wallet Information:</strong>
                                <ul className="list-disc list-inside ml-4 mt-2">
                                    <li>Payment order details (amount, status, payment method: card/UPI via Razorpay, wallet, or hybrid)</li>
                                    <li>Wallet balance and wallet transaction history (top-ups, payments, refunds)</li>
                                    <li>We do not store your card, UPI ID, or bank account details; payments and wallet top-ups are processed by Razorpay</li>
                                </ul>
                            </div>
                            <div>
                                <strong className="text-purple-300">File Information:</strong>
                                <ul className="list-disc list-inside ml-4 mt-2">
                                    <li>Uploaded files: PDF, images (PNG, JPG, JPEG), Word (DOC, DOCX), PowerPoint (PPT, PPTX)</li>
                                    <li>Print preferences (copies, single/double-sided, color/black &amp; white, paper size)</li>
                                    <li>File metadata (e.g. page count, cost); file content is stored securely and deleted after printing or withdrawal</li>
                                </ul>
                            </div>
                            <div>
                                <strong className="text-purple-300">Session and Security Data:</strong>
                                <ul className="list-disc list-inside ml-4 mt-2">
                                    <li>Authentication token (to keep you logged in)</li>
                                    <li>CSRF token (to prevent cross-site request forgery on the website)</li>
                                </ul>
                            </div>
                            <div>
                                <strong className="text-purple-300">Preferences (stored on your device):</strong>
                                <ul className="list-disc list-inside ml-4 mt-2">
                                    <li>On the website: favorite shop IDs may be stored in your browser (localStorage)</li>
                                    <li>On the mobile app: auth token (in secure storage where available), username, and similar preferences on the device</li>
                                </ul>
                            </div>
                        </div>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">2. How We Use Your Information</h2>
                        <ul className="list-disc list-inside space-y-2 text-gray-200 ml-4">
                            <li>To provide and improve our print services</li>
                            <li>To process payments and wallet operations (top-up, pay with wallet, refunds to wallet or card/UPI)</li>
                            <li>To connect you with nearby print shops and show your favorite shops</li>
                            <li>To manage your account, wallet balance, and preferences</li>
                            <li>To send service-related notifications (e.g. password reset emails)</li>
                            <li>To protect against fraud and abuse (e.g. CSRF protection, secure sessions)</li>
                            <li>To comply with legal obligations</li>
                        </ul>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">3. Data Storage and Security</h2>
                        <div className="space-y-4 text-gray-200">
                            <p>
                                <strong className="text-purple-300">File Storage:</strong> Uploaded files are stored securely
                                and are automatically deleted after printing or withdrawal.
                            </p>
                            <p>
                                <strong className="text-purple-300">Wallet and Payment Records:</strong> Wallet balance,
                                wallet transactions (top-up, payment, refund), and payment order records are stored on our
                                servers for accounting, support, and dispute resolution. We do not store your card or bank details.
                            </p>
                            <p>
                                <strong className="text-purple-300">Website (Browser):</strong> We may store your auth token and
                                role in localStorage or, when using HTTPS and when cookies are blocked (e.g. in some private
                                browsing modes), in sessionStorage. SessionStorage is cleared when you close the browser tab.
                                We use CSRF tokens for state-changing requests to protect your session.
                            </p>
                            <p>
                                <strong className="text-purple-300">Mobile App:</strong> The Qprint mobile app stores your auth
                                token in secure storage (e.g. Android Keystore / iOS Keychain) where available, with a fallback
                                to device storage. Username and similar non-sensitive preferences may be stored on the device.
                            </p>
                            <p>
                                <strong className="text-purple-300">Data Security:</strong> We use industry-standard security
                                measures including encryption, secure servers, and access controls to protect your data.
                            </p>
                            <p>
                                <strong className="text-purple-300">Payment Security:</strong> All card/UPI payments and wallet
                                top-ups are processed through Razorpay&apos;s secure payment gateway. We do not store your card,
                                UPI, or bank account details.
                            </p>
                        </div>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">4. Data Sharing</h2>
                        <p className="text-gray-200 mb-4">We do NOT sell your personal information. We may share data only in these cases:</p>
                        <ul className="list-disc list-inside space-y-2 text-gray-200 ml-4">
                            <li><strong>With Print Shops:</strong> Order information needed to fulfill your print request (e.g. file, print settings, queue position)</li>
                            <li><strong>Payment Processors:</strong> Razorpay for payment processing and wallet top-ups (as required to complete transactions)</li>
                            <li><strong>Legal Requirements:</strong> When required by law or to protect our rights and users</li>
                        </ul>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">5. Your Rights</h2>
                        <div className="space-y-2 text-gray-200">
                            <p>You have the right to:</p>
                            <ul className="list-disc list-inside space-y-2 ml-4">
                                <li>Access your personal data</li>
                                <li>Correct inaccurate information</li>
                                <li>Request deletion of your account and associated data (including wallet balance and transaction history)</li>
                                <li>Withdraw consent for data processing (subject to legal and contractual limits)</li>
                                <li>Export your data</li>
                            </ul>
                            <p className="mt-4">To exercise these rights, contact us at support@qprint.co.in</p>
                        </div>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">6. Cookies and Local Storage</h2>
                        <p className="text-gray-200 mb-4">
                            We use cookies and similar technologies (including localStorage and sessionStorage on the website) to:
                        </p>
                        <ul className="list-disc list-inside space-y-2 text-gray-200 ml-4">
                            <li>Maintain your login session (e.g. auth token, role, username)</li>
                            <li>Remember your preferences (e.g. favorite shops on the website)</li>
                            <li>Protect against cross-site request forgery (CSRF token)</li>
                        </ul>
                        <p className="text-gray-200 mt-4">
                            On the website, when cookies are not available (e.g. in some incognito or strict privacy modes),
                            we may use sessionStorage for the auth token so you can still log in; that data is cleared when you
                            close the tab. You can control cookies through your browser settings. We do not use third-party
                            advertising or tracking cookies.
                        </p>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">7. Third-Party Services</h2>
                        <div className="space-y-4 text-gray-200">
                            <div>
                                <strong className="text-purple-300">Razorpay:</strong>
                                <p>Payment processing and wallet top-ups. Razorpay receives information necessary to process
                                payments (e.g. order amount, order ID). We do not send them your card or bank details;
                                you enter those in their secure flow. See Razorpay&apos;s privacy policy for their data practices.</p>
                            </div>
                            <div>
                                <strong className="text-purple-300">Cloud Storage:</strong>
                                <p>Uploaded files may be stored on cloud services (e.g. AWS S3 or similar) with encryption
                                and are deleted after printing or withdrawal.</p>
                            </div>
                        </div>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">8. Data Retention</h2>
                        <div className="space-y-2 text-gray-200">
                            <p><strong>Files:</strong> Deleted after printing or withdrawal</p>
                            <p><strong>Account Data:</strong> Retained while your account is active</p>
                            <p><strong>Wallet and Payment Records:</strong> Retained as required for accounting, support, and law (typically up to 7 years for financial records)</p>
                            <p><strong>After Account Deletion:</strong> Your account data, wallet balance, and associated records are deleted within 30 days, except where we must retain data by law</p>
                        </div>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">9. Children&apos;s Privacy</h2>
                        <p className="text-gray-200">
                            Our services are intended for users 18 years and older. We do not knowingly collect
                            information from children under 18.
                        </p>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">10. Changes to This Policy</h2>
                        <p className="text-gray-200">
                            We may update this policy from time to time. We will notify you of significant changes
                            via email or through our platform. Continued use after changes constitutes acceptance.
                            The &quot;Last Updated&quot; date at the top reflects the latest revision.
                        </p>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">11. Contact Us</h2>
                        <p className="text-gray-200 mb-4">
                            For privacy-related questions or requests:
                        </p>
                        <div className="text-gray-200 space-y-2">
                            <p><strong>Email:</strong> support@qprint.co.in</p>
                            <p><strong>Subject:</strong> Privacy Request</p>
                        </div>
                    </section>
                </div>

                <div className="mt-8 text-center text-gray-300">
                    <p>Last updated: February 2026</p>
                </div>
            </div>
        </div>
    );
}

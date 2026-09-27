import Link from 'next/link';

export default function TermsPage() {
    return (
        <div className="min-h-screen bg-gradient-to-br from-purple-900 via-blue-900 to-indigo-900 text-white p-8">
            <div className="max-w-4xl mx-auto">
                <div className="mb-8">
                    <Link href="/" className="text-purple-300 hover:text-purple-200">
                        ← Back to Home
                    </Link>
                </div>

                <h1 className="text-4xl font-bold mb-8 text-center">Terms and Conditions</h1>

                <div className="bg-white/10 backdrop-blur-lg rounded-lg p-8 space-y-8">
                    <section>
                        <p className="text-gray-200 mb-6">
                            <strong>Last Updated:</strong> {new Date().toLocaleDateString()}
                        </p>
                        <p className="text-gray-200">
                            Please read these Terms and Conditions carefully before using Qprint services.
                        </p>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">1. Acceptance of Terms</h2>
                        <p className="text-gray-200 mb-4">
                            By accessing and using Qprint, you accept and agree to be bound by these Terms and Conditions. 
                            If you do not agree, please do not use our services.
                        </p>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">2. Service Description</h2>
                        <p className="text-gray-200 mb-4">
                            Qprint is a digital platform that connects customers with local print shops for document printing services. 
                            We facilitate the upload, payment, and printing process but are not responsible for the actual printing 
                            or quality of prints produced by partner shops.
                        </p>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">3. User Accounts</h2>
                        <div className="space-y-4 text-gray-200">
                            <p>3.1. You must create an account to use our services.</p>
                            <p>3.2. You are responsible for maintaining the confidentiality of your account credentials.</p>
                            <p>3.3. You agree to provide accurate and complete information.</p>
                            <p>3.4. You must be at least 18 years old to use our services.</p>
                        </div>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">4. Payment Terms</h2>
                        <div className="space-y-4 text-gray-200">
                            <p>4.1. All payments must be made before file upload and printing.</p>
                            <p>4.2. Payments are processed through Razorpay payment gateway.</p>
                            <p>4.3. All prices are in Indian Rupees (INR).</p>
                            <p>4.4. Pricing is calculated based on number of pages and copies.</p>
                            <p>4.5. Once payment is made, it is non-refundable except as stated in our Refund Policy.</p>
                        </div>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">5. File Upload and Content</h2>
                        <div className="space-y-4 text-gray-200">
                            <p>5.1. You may upload PDF, images (PNG/JPG/JPEG), Word (DOC/DOCX), or PowerPoint (PPT/PPTX) files.</p>
                            <p>5.2. Maximum file size is 20MB.</p>
                            <p>5.3. You are responsible for ensuring you have the right to print the content.</p>
                            <p>5.4. You agree not to upload illegal, copyrighted, or offensive content.</p>
                            <p>5.5. Files are stored securely and deleted after printing or withdrawal.</p>
                        </div>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">6. Print Service</h2>
                        <div className="space-y-4 text-gray-200">
                            <p>6.1. Print quality depends on the partner shop's equipment and materials.</p>
                            <p>6.2. We are not responsible for print quality issues.</p>
                            <p>6.3. You must collect prints within the specified time period.</p>
                            <p>6.4. Uncollected prints may be discarded after a reasonable period.</p>
                        </div>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">7. Limitation of Liability</h2>
                        <p className="text-gray-200 mb-4">
                            Qprint acts as an intermediary platform. We are not liable for:
                        </p>
                        <ul className="list-disc list-inside space-y-2 text-gray-200 ml-4">
                            <li>Print quality issues</li>
                            <li>Delays in printing or collection</li>
                            <li>Loss or damage to files</li>
                            <li>Issues with partner shops</li>
                            <li>Technical failures beyond our control</li>
                        </ul>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">8. Intellectual Property</h2>
                        <p className="text-gray-200 mb-4">
                            All content on Qprint, including logos, design, and software, is the property of Qprint 
                            and protected by copyright laws.
                        </p>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">9. Termination</h2>
                        <p className="text-gray-200 mb-4">
                            We reserve the right to suspend or terminate your account if you violate these terms 
                            or engage in fraudulent activities.
                        </p>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">10. Changes to Terms</h2>
                        <p className="text-gray-200 mb-4">
                            We may update these terms from time to time. Continued use of our services after 
                            changes constitutes acceptance of the new terms.
                        </p>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">11. Contact</h2>
                        <p className="text-gray-200">
                            For questions about these terms, contact us at{' '}
                            <a href="mailto:support@qprint.co.in" className="text-purple-300 hover:underline">support@qprint.co.in</a>
                        </p>
                    </section>
                </div>

                <div className="mt-8 text-center text-gray-300">
                    <p>Last updated: {new Date().toLocaleDateString()}</p>
                </div>
            </div>
        </div>
    );
}

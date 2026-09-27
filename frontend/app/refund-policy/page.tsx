import Link from 'next/link';

export default function RefundPolicyPage() {
    return (
        <div className="min-h-screen bg-gradient-to-br from-purple-900 via-blue-900 to-indigo-900 text-white p-8">
            <div className="max-w-4xl mx-auto">
                <div className="mb-8">
                    <Link href="/" className="text-purple-300 hover:text-purple-200">
                        ← Back to Home
                    </Link>
                </div>

                <h1 className="text-4xl font-bold mb-8 text-center">Cancellation and Refund Policy</h1>

                <div className="bg-white/10 backdrop-blur-lg rounded-lg p-8 space-y-8">
                    <section>
                        <p className="text-gray-200 mb-6">
                            <strong>Last Updated:</strong> {new Date().toLocaleDateString()}
                        </p>
                        <p className="text-gray-200">
                            This policy outlines the terms for cancellation and refunds on Qprint.
                        </p>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">1. Cancellation Policy</h2>
                        <div className="space-y-4 text-gray-200">
                            <div>
                                <strong className="text-purple-300">Before File Upload:</strong>
                                <p>You may cancel your payment order before uploading the file. Refunds will be processed as per our refund policy.</p>
                            </div>
                            <div>
                                <strong className="text-purple-300">After File Upload (Before Printing):</strong>
                                <p>You may withdraw your print job at any time before it is printed. <strong className="text-purple-300">Automatic refund</strong> will be processed 
                                immediately to your original payment method. The refund typically appears in your account within 5-7 business days.</p>
                            </div>
                            <div>
                                <strong className="text-purple-300">After Printing:</strong>
                                <p>Cancellation is not possible after the document has been printed and collected.</p>
                            </div>
                        </div>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">2. Automatic Refunds</h2>
                        <div className="bg-purple-900/30 rounded-lg p-4 mb-4">
                            <p className="text-gray-200 font-semibold mb-2">
                                ✅ <strong>Automatic Refund for Withdrawals:</strong>
                            </p>
                            <p className="text-gray-200">
                                If you withdraw your print job before it is printed, you will receive an <strong>automatic full refund</strong> 
                                to your original payment method. No manual request needed - the refund is processed immediately when you withdraw.
                            </p>
                        </div>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">3. Refund Eligibility (Manual Requests)</h2>
                        <p className="text-gray-200 mb-4">Refunds may be issued in the following cases (requires manual request):</p>
                        <ul className="list-disc list-inside space-y-2 text-gray-200 ml-4">
                            <li>Payment made but file upload failed due to technical issues</li>
                            <li>Payment made but print service unavailable at selected shop</li>
                            <li>Duplicate payment made by mistake</li>
                            <li>Payment made for incorrect amount (system error)</li>
                            <li>File upload failed after successful payment</li>
                        </ul>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">4. Non-Refundable Cases</h2>
                        <p className="text-gray-200 mb-4">Refunds will NOT be issued for:</p>
                        <ul className="list-disc list-inside space-y-2 text-gray-200 ml-4">
                            <li>Print quality issues (these should be resolved with the shopkeeper directly)</li>
                            <li>Failure to collect prints within the specified time (after printing is complete)</li>
                            <li>Printing completed successfully and document collected</li>
                            <li>User error in selecting print options (if printing has already started)</li>
                        </ul>
                        <p className="text-gray-200 mt-4">
                            <strong>Note:</strong> If you withdraw before printing, you will receive an automatic refund regardless of the reason.
                        </p>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">5. Refund Process</h2>
                        <div className="space-y-4 text-gray-200">
                            <div>
                                <strong className="text-purple-300">Automatic Refund (Withdrawal):</strong>
                                <p>When you withdraw a print job before printing, the refund is processed automatically. 
                                No action required - the refund will appear in your account within 5-7 business days.</p>
                            </div>
                            <div>
                                <strong className="text-purple-300">Manual Refund Request:</strong>
                                <p>For other cases, contact our support team at support@qprint.co.in with your payment order ID and reason for refund.</p>
                            </div>
                            <div>
                                <strong className="text-purple-300">Review Process:</strong>
                                <p>Our team will review manual refund requests within 2-3 business days.</p>
                            </div>
                            <div>
                                <strong className="text-purple-300">Processing Time:</strong>
                                <p>If approved, refund will be processed to your original payment method within 5-7 business days.</p>
                            </div>
                        </div>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">6. Refund Timeline</h2>
                        <div className="space-y-2 text-gray-200">
                            <p><strong>Automatic Refund (Withdrawal):</strong> Processed immediately, appears in account within 5-7 business days</p>
                            <p><strong>Manual Request Review:</strong> 2-3 business days</p>
                            <p><strong>Refund Processing:</strong> 5-7 business days after approval</p>
                            <p><strong>Total Time (Manual):</strong> 7-10 business days from request to refund</p>
                        </div>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">7. Partial Refunds</h2>
                        <p className="text-gray-200 mb-4">
                            In certain cases, partial refunds may be issued if only part of the service was not delivered. 
                            This will be determined on a case-by-case basis.
                        </p>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">8. Dispute Resolution</h2>
                        <p className="text-gray-200 mb-4">
                            If you are not satisfied with a refund decision, you may:
                        </p>
                        <ul className="list-disc list-inside space-y-2 text-gray-200 ml-4">
                            <li>Request a review by contacting support@qprint.co.in</li>
                            <li>Provide additional documentation to support your case</li>
                            <li>Escalate to our management team if needed</li>
                        </ul>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">9. Contact for Refunds</h2>
                        <p className="text-gray-200 mb-4">
                            To request a refund, please contact us:
                        </p>
                        <div className="text-gray-200 space-y-2">
                            <p><strong>Email:</strong> support@qprint.co.in</p>
                            <p><strong>Subject:</strong> Refund Request - [Your Order ID]</p>
                            <p>Please include your payment order ID and reason for refund in your email.</p>
                        </div>
                    </section>
                </div>

                <div className="mt-8 text-center text-gray-300">
                    <p>Last updated: {new Date().toLocaleDateString()}</p>
                </div>
            </div>
        </div>
    );
}

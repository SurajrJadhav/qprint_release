import Link from 'next/link';

export default function ContactPage() {
    return (
        <div className="min-h-screen bg-gradient-to-br from-purple-900 via-blue-900 to-indigo-900 text-white p-8">
            <div className="max-w-4xl mx-auto">
                <div className="mb-8">
                    <Link href="/" className="text-purple-300 hover:text-purple-200">
                        ← Back to Home
                    </Link>
                </div>

                <h1 className="text-4xl font-bold mb-8 text-center">Contact Us</h1>

                <div className="bg-white/10 backdrop-blur-lg rounded-lg p-8 space-y-8">
                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">Get in Touch</h2>
                        <p className="text-gray-200 mb-6">
                            We're here to help! If you have any questions, concerns, or feedback about Qprint, 
                            please don't hesitate to reach out to us.
                        </p>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">Contact Information</h2>
                        <div className="space-y-4 text-gray-200">
                            <div>
                                <strong className="text-purple-300">Email:</strong>
                                <p>support@qprint.co.in</p>
                            </div>
                            <div>
                                <strong className="text-purple-300">Phone:</strong>
                                <p>+91-9403447459</p>
                            </div>
                            <div>
                                <strong className="text-purple-300">Business Hours:</strong>
                                <p>Monday - Saturday: 9:00 AM - 6:00 PM IST</p>
                            </div>
                        </div>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">Support</h2>
                        <p className="text-gray-200 mb-4">
                            For technical support, payment issues, or account-related queries, 
                            please email us at <a href="mailto:support@qprint.co.in" className="text-purple-300 hover:underline">support@qprint.co.in</a>
                        </p>
                        <p className="text-gray-200">
                            We typically respond within 24-48 hours during business days.
                        </p>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">Address</h2>
                        <div className="text-gray-200">
                            <p>Qprint Services</p>
                            <p>SMR VINAY Technopolis</p>
                            <p>Hyderabad, Telanagan - 500084</p>
                            <p>India</p>
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

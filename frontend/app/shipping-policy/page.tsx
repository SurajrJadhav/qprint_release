import Link from 'next/link';

export default function ShippingPolicyPage() {
    return (
        <div className="min-h-screen bg-gradient-to-br from-purple-900 via-blue-900 to-indigo-900 text-white p-8">
            <div className="max-w-4xl mx-auto">
                <div className="mb-8">
                    <Link href="/" className="text-purple-300 hover:text-purple-200">
                        ← Back to Home
                    </Link>
                </div>

                <h1 className="text-4xl font-bold mb-8 text-center">Shipping Policy</h1>

                <div className="bg-white/10 backdrop-blur-lg rounded-lg p-8 space-y-8">
                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">Not Applicable</h2>
                        <p className="text-gray-200 mb-6">
                            Qprint is a digital print service platform that connects customers with local print shops. 
                            We do not ship physical products to customers.
                        </p>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">How It Works</h2>
                        <div className="space-y-4 text-gray-200">
                            <div>
                                <strong className="text-purple-300">1. Digital Upload:</strong>
                                <p>Customers upload their documents digitally through our platform.</p>
                            </div>
                            <div>
                                <strong className="text-purple-300">2. Local Pickup:</strong>
                                <p>Customers collect their printed documents from the selected local print shop.</p>
                            </div>
                            <div>
                                <strong className="text-purple-300">3. No Shipping Required:</strong>
                                <p>Since documents are printed locally and collected in person, no shipping is involved.</p>
                            </div>
                        </div>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">Collection</h2>
                        <p className="text-gray-200 mb-4">
                            For <strong>Queue Prints</strong>: Your documents are printed at the selected shop and 
                            you can collect them from that location.
                        </p>
                        <p className="text-gray-200">
                            For <strong>Private Prints</strong>: You receive a unique code. Visit any participating 
                            shop, provide the code, and collect your prints.
                        </p>
                    </section>

                    <section>
                        <h2 className="text-2xl font-semibold mb-4 text-purple-300">Questions?</h2>
                        <p className="text-gray-200">
                            If you have any questions about document collection, please contact us at{' '}
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

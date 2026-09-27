import Link from 'next/link';

export const metadata = {
    title: 'Delete your data – qprint (QprintSolutions)',
    description: 'How to delete your qprint account and data. In-app or by email request.',
};

export default function DeleteDataPage() {
    const supportEmail = 'support@qprint.co.in';

    return (
        <div className="min-h-screen bg-gradient-to-br from-purple-900 via-blue-900 to-indigo-900 text-white p-8">
            <div className="max-w-4xl mx-auto">
                <div className="mb-8">
                    <Link href="/" className="text-purple-300 hover:text-purple-200">
                        ← Back to Home
                    </Link>
                </div>

                <h1 className="text-4xl font-bold mb-8 text-center">Delete your qprint account and data</h1>

                <div className="bg-amber-500/20 border border-amber-400/50 rounded-lg p-4 mb-6 text-amber-100 text-sm">
                    <strong>This page does not delete any data.</strong> It only explains how you can request deletion. Actual deletion always requires your password (in the app) or verification by our team (by email).
                </div>

                <div className="bg-white/10 backdrop-blur-lg rounded-lg p-8 space-y-6">
                    <p className="text-gray-200">
                        qprint is made by <strong>QprintSolutions</strong>. We store your account data (username, email if provided, and related print history) when you use the app or website.
                    </p>

                    <h2 className="text-2xl font-semibold text-purple-300">How to delete your data</h2>
                    <ol className="list-decimal list-inside space-y-4 text-gray-200">
                        <li>
                            <strong>From the app (recommended):</strong> Open the qprint app, go to <strong>Profile</strong>, tap <strong>Delete Account</strong>, and confirm with your password. This permanently deletes your account and associated data.
                        </li>
                        <li>
                            <strong>From the website:</strong> If you use the web app at qprint.co.in, log in and use the account or profile section to delete your account (if available), or contact us by email below.
                        </li>
                        <li>
                            <strong>If you cannot access the app or website:</strong> Email us at{' '}
                            <a href={`mailto:${supportEmail}?subject=Request to delete my qprint account`} className="text-purple-300 hover:text-purple-200 underline break-all">
                                {supportEmail}
                            </a>{' '}
                            with the email or username you used to register. We will process your deletion request within 30 days.
                        </li>
                    </ol>

                    <p className="text-gray-200">
                        After deletion, we do not retain your account or personal data longer than necessary for legal or operational requirements.
                    </p>
                </div>

                <div className="mt-8 flex flex-wrap gap-4 justify-center">
                    <Link href="/privacy" className="text-purple-300 hover:text-purple-200">
                        Privacy Policy
                    </Link>
                    <Link href="/terms" className="text-purple-300 hover:text-purple-200">
                        Terms &amp; Conditions
                    </Link>
                    <Link href="/" className="text-purple-300 hover:text-purple-200">
                        Home
                    </Link>
                </div>
            </div>
        </div>
    );
}

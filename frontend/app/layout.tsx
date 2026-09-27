import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'
import Header from '@/components/Header'
import ConditionalMain from '@/components/ConditionalMain'

const inter = Inter({ subsets: ['latin'] })

export const metadata: Metadata = {
    title: 'Qprint - Print Without Standing in Queue',
    description: 'Upload documents from anywhere, get a unique code, and collect prints instantly from the nearest shop',
}

export default function RootLayout({
    children,
}: {
    children: React.ReactNode
}) {
    return (
        <html lang="en">
            <body className={inter.className}>
                <Header />
                <ConditionalMain>
                    {children}
                </ConditionalMain>
            </body>
        </html>
    )
}

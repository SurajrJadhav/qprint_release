"use client";

import { usePathname } from 'next/navigation';

export default function ConditionalMain({ children }: { children: React.ReactNode }) {
    const pathname = usePathname();
    
    // Don't add padding on pages that use their own header (dashboard, wallet, refer, admin)
    const hasOwnHeader = pathname?.startsWith('/customer/dashboard') || pathname?.startsWith('/customer/wallet') || pathname?.startsWith('/customer/refer') || pathname?.startsWith('/shopkeeper/dashboard') || pathname?.startsWith('/admin');
    
    return (
        <main className={hasOwnHeader ? '' : 'pt-16 md:pt-20'}>
            {children}
        </main>
    );
}

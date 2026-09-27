// Razorpay integration for web

declare global {
    interface Window {
        Razorpay: any;
    }
}

// Load Razorpay script dynamically
export const loadRazorpay = (): Promise<void> => {
    return new Promise((resolve, reject) => {
        if (window.Razorpay) {
            resolve();
            return;
        }

        const script = document.createElement('script');
        script.src = 'https://checkout.razorpay.com/v1/checkout.js';
        script.onload = () => resolve();
        script.onerror = () => reject(new Error('Failed to load Razorpay'));
        document.body.appendChild(script);
    });
};

// Open Razorpay checkout
export const openRazorpayCheckout = async (options: {
    key: string;
    amount: number;
    order_id: string;
    name: string;
    description: string;
    prefill?: {
        name?: string;
        email?: string;
        contact?: string;
    };
    handler: (response: any) => void;
    onError?: (error: any) => void;
}): Promise<void> => {
    await loadRazorpay();

    const razorpayOptions = {
        key: options.key,
        amount: options.amount,
        currency: 'INR',
        name: options.name,
        description: options.description,
        order_id: options.order_id,
        prefill: options.prefill || {},
        handler: options.handler,
        modal: {
            ondismiss: () => {
                if (options.onError) {
                    options.onError({ code: 'MODAL_CLOSED', description: 'User closed the payment modal' });
                }
            },
        },
        theme: {
            color: '#6366f1',
        },
    };

    const razorpay = new window.Razorpay(razorpayOptions);
    razorpay.open();
};

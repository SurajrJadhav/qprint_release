import axios from 'axios';

const baseURL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8080';

// Separate axios instance for CSRF token fetch (no interceptors to avoid circular dependency)
const csrfClient = axios.create({
    baseURL,
    headers: {
        'Content-Type': 'application/json',
    },
    withCredentials: true,
});

const api = axios.create({
    baseURL,
    headers: {
        'Content-Type': 'application/json',
    },
    withCredentials: true,
});

let csrfTokenPromise: Promise<string> | null = null;

async function getCsrfToken(): Promise<string> {
    if (csrfTokenPromise) return csrfTokenPromise;
    csrfTokenPromise = (async () => {
        const tryFetch = async (): Promise<string> => {
            try {
                // Use csrfClient (not api) to avoid circular dependency with interceptors.
                // Using axios instead of fetch ensures cookie consistency in incognito mode.
                const res = await csrfClient.get('/csrf-token');
                if (typeof window !== 'undefined' && process.env.NODE_ENV === 'development') {
                    console.log('CSRF token fetched successfully');
                }
                return res.data.csrfToken as string;
            } catch (error: any) {
                if (typeof window !== 'undefined') {
                    console.error('CSRF token fetch failed:', {
                        message: error.message,
                        status: error.response?.status,
                        statusText: error.response?.statusText,
                        origin: window.location.origin,
                        apiUrl: baseURL
                    });
                }
                throw error;
            }
        };
        try {
            return await tryFetch();
        } catch (e) {
            if (typeof window !== 'undefined' && process.env.NODE_ENV === 'development') {
                console.log('Retrying CSRF token fetch after 2s...');
            }
            // Retry once after 2s (helps with Render cold start)
            await new Promise((r) => setTimeout(r, 2000));
            return tryFetch();
        }
    })();
    return csrfTokenPromise;
}

// Reset CSRF cache (e.g. after logout or 403) so next request fetches a new token
export function clearCsrfCache() {
    csrfTokenPromise = null;
}

// Request interceptor: add auth (Bearer or cookie) and CSRF for state-changing methods
api.interceptors.request.use(async (config) => {
    const token = typeof window !== 'undefined'
        ? (localStorage.getItem('token') || sessionStorage.getItem('token'))
        : null;
    if (token) {
        config.headers.Authorization = `Bearer ${token}`;
    }
    // Platform hint for backend activity tracking (shopkeeper web inactivity auto-close)
    config.headers['X-Platform'] = 'web';

    const method = (config.method || 'get').toLowerCase();
    if (['post', 'put', 'delete', 'patch'].includes(method)) {
        try {
            config.headers['X-CSRF-Token'] = await getCsrfToken();
        } catch (e) {
            clearCsrfCache();
            // Don't send request without CSRF (would get 403). Propagate so user sees connection error.
            throw e;
        }
    }

    if (config.data instanceof FormData) {
        delete config.headers['Content-Type'];
    }

    return config;
});

api.interceptors.response.use(
    (res) => res,
    (err) => {
        if (err.response?.status === 403 && err.config?.headers?.['X-CSRF-Token']) {
            clearCsrfCache();
        }
        return Promise.reject(err);
    }
);

export async function logout(): Promise<void> {
    try {
        await api.post('/logout');
    } catch {
        // Ignore 401 or any error: session may already be invalid. We still clear local state.
    } finally {
        clearCsrfCache();
        if (typeof window !== 'undefined') {
            localStorage.removeItem('token');
            localStorage.removeItem('role');
            localStorage.removeItem('display_name');
            localStorage.removeItem('username'); // legacy
            sessionStorage.removeItem('token');
        }
    }
}

export async function deleteAccount(password: string): Promise<void> {
    const response = await api.delete('/profile', {
        data: { password },
    });
    
    // Clear local data after successful deletion
    clearCsrfCache();
    if (typeof window !== 'undefined') {
        localStorage.removeItem('token');
        localStorage.removeItem('role');
        localStorage.removeItem('username');
        localStorage.removeItem('favorites');
        sessionStorage.removeItem('token');
    }
    
    return response.data;
}

/** Send OTP to email for sign-up verification (email only). */
export async function registerSendOtp(params: { email: string }): Promise<void> {
    await api.post('/register/send-otp', { email: params.email.trim().toLowerCase() });
}

/** Verify OTP and get short-lived signup token (email only). */
export async function registerVerifyOtp(params: { email: string; code: string }): Promise<{ signup_token: string; email: string }> {
    const response = await api.post('/register/verify-otp', {
        email: params.email.trim().toLowerCase(),
        code: params.code.trim(),
    });
    return response.data;
}

/** Request OTP for login (email only). */
export async function loginRequestOtp(login: string): Promise<void> {
    await api.post('/login/request-otp', { login: login.trim() });
}

/** Verify OTP: returns JWT (login) or needs_signup + signup_token + email (create account). */
export type LoginVerifyOtpResult =
    | { token: string; role: string; display_name: string }
    | { needs_signup: true; signup_token: string; email: string };
export async function loginVerifyOtp(login: string, code: string): Promise<LoginVerifyOtpResult> {
    const response = await api.post('/login/verify-otp', { login: login.trim(), code: code.trim() });
    return response.data;
}

/** Google Sign-In: exchange Google ID token for app JWT (or needs_signup for new shopkeepers). */
export type LoginGoogleResult =
    | { token: string; role: string; display_name: string }
    | { needs_signup: true; signup_token: string; email: string; full_name?: string };
export async function loginWithGoogle(
    idToken: string,
    intent: 'customer' | 'shopkeeper' = 'customer'
): Promise<LoginGoogleResult> {
    const response = await api.post('/login/google', { id_token: idToken, intent });
    return response.data;
}

// Payment API methods
export const calculateCost = async (
    files: File | File[],
    copies: number,
    printMode: string,
    colorMode: string,
    paperSize: string,
    shopId?: number
) => {
    const formData = new FormData();
    const fileArray = Array.isArray(files) ? files : [files];

    fileArray.forEach(file => {
        formData.append('files[]', file);
    });

    formData.append('copies', copies.toString());
    formData.append('print_mode', printMode);
    formData.append('color_mode', colorMode);
    formData.append('paper_size', paperSize);
    if (shopId != null && shopId > 0) {
        formData.append('shop_id', shopId.toString());
    }

    const response = await api.post('/calculate-cost', formData);
    return response.data;
};

/** Cost only from total page count (no file upload). Use when shop or print type changes and client already has page counts. */
export const calculateCostFromPages = async (
    totalPages: number,
    copies: number,
    printMode: string,
    colorMode: string,
    shopId?: number
) => {
    const response = await api.post('/calculate-cost-from-pages', {
        total_pages: totalPages,
        copies,
        print_mode: printMode,
        color_mode: colorMode,
        shop_id: shopId ?? null,
    });
    return response.data;
};

export const createPaymentOrder = async (data: {
    amount: number;
    shopkeeper_id?: number;
    copies: number;
    print_mode: string;
    color_mode: string;
    paper_size: string;
    print_type: 'private' | 'queue';
    comment?: string;
    use_wallet?: boolean;
    wallet_amount?: number;
}) => {
    const response = await api.post('/create-payment-order', data);
    return response.data;
};

// Wallet API
export const getWalletBalance = async (): Promise<{ balance: number }> => {
    const response = await api.get('/wallet/balance');
    return response.data;
};

export const getWalletTransactions = async (params?: { limit?: number; offset?: number }) => {
    const searchParams = new URLSearchParams();
    if (params?.limit != null) searchParams.set('limit', String(params.limit));
    if (params?.offset != null) searchParams.set('offset', String(params.offset));
    const q = searchParams.toString();
    const response = await api.get(`/wallet/transactions${q ? `?${q}` : ''}`);
    return response.data;
};

export const topupWallet = async (amount: number): Promise<{ order_id: string; key_id: string; amount: number }> => {
    const response = await api.post('/wallet/topup', { amount });
    return response.data;
};

export const getPaymentStatus = async (orderId: string) => {
    const response = await api.get(`/payment-order/${orderId}/status`);
    return response.data;
};

/** Get a single shop by id (e.g. after scanning shop QR or entering shop code). */
export const getShopById = async (shopId: number): Promise<{
    id: number;
    shop_name: string;
    lat: number;
    long: number;
    address?: string;
    is_open: boolean;
    distance?: number;
    price_per_page_bw?: number;
    price_per_page_color?: number;
    double_sided_factor?: number;
}> => {
    const response = await api.get(`/shops/${shopId}`);
    return response.data;
};

export const uploadFile = async (
    files: File | File[],
    paymentOrderId: number,
    copies: number,
    printMode: string,
    colorMode: string,
    paperSize: string,
    printType: 'private' | 'queue',
    shopId?: string,
    comment?: string
) => {
    const formData = new FormData();
    const fileArray = Array.isArray(files) ? files : [files];
    
    // Append all files
    fileArray.forEach(file => {
        formData.append('files[]', file);
    });
    
    formData.append('payment_order_id', paymentOrderId.toString());
    formData.append('copies', copies.toString());
    formData.append('print_mode', printMode);
    formData.append('color_mode', colorMode);
    formData.append('paper_size', paperSize);
    formData.append('print_type', printType);
    if (shopId) {
        formData.append('shop_id', shopId);
    }
    if (comment) {
        formData.append('comment', comment);
    }

    // Upload can be slow (large files, Render cold start). Use 2 min timeout.
    const response = await api.post('/upload', formData, { timeout: 120000 });
    return response.data;
};

// App download links (public GET; no auth required). Admin can set URLs and/or mark as "coming soon".
export interface AppDownloadLinks {
    windows_shopkeeper_url: string;
    android_customer_url: string;
    ios_customer_url: string;
    windows_coming_soon?: boolean;
    android_coming_soon?: boolean;
    ios_coming_soon?: boolean;
}

export const getAppDownloads = async (): Promise<AppDownloadLinks> => {
    const response = await api.get<AppDownloadLinks>('/app-downloads');
    return response.data;
};

// Profile (returns id, display_name, full_name, email, phone, referral_code, referral_link, ...)
export const getProfile = async (): Promise<Record<string, unknown>> => {
    const response = await api.get('/profile');
    return response.data;
};

// Referral summary (customer only)
export const getReferralSummary = async (): Promise<{
    total_referred: number;
    total_credited: number;
    total_earnings: number;
    pending_count: number;
}> => {
    const response = await api.get('/referral/summary');
    return response.data;
};

// Referral history (customer only)
export const getReferralHistory = async (params?: { limit?: number; offset?: number }) => {
    const searchParams = new URLSearchParams();
    if (params?.limit != null) searchParams.set('limit', String(params.limit));
    if (params?.offset != null) searchParams.set('offset', String(params.offset));
    const q = searchParams.toString();
    const response = await api.get(`/referral/history${q ? `?${q}` : ''}`);
    return response.data;
};

// Invite by email (customer only). Sends invite email with referral link via backend (Resend).
export const inviteByEmail = async (email: string): Promise<{ ok: boolean; message?: string }> => {
    const response = await api.post('/referral/invite', { email: email.trim().toLowerCase() });
    return response.data;
};

export const updateAppDownloads = async (links: AppDownloadLinks): Promise<void> => {
    await api.put('/admin/app-downloads', links);
};

/** Shopkeeper: cancel a queue order (before printing). Customer is notified and refunded. */
export const cancelQueueOrder = async (fileId: number, reason: string): Promise<void> => {
    await api.post(`/queue/${fileId}/cancel`, { reason: reason.trim() });
};

export default api;

import axios from 'axios';

const api = axios.create({
    baseURL: process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8080',
    withCredentials: true,
    headers: {
        'Content-Type': 'application/json',
    },
});

let csrfToken: string | null = null;

/** Call this when the dashboard (or any admin page) loads so PUT/POST/DELETE can send CSRF token. */
export async function fetchCsrfToken(): Promise<void> {
    try {
        const r = await api.get<{ csrfToken: string }>('/csrf-token');
        csrfToken = r.data?.csrfToken ?? null;
    } catch {
        csrfToken = null;
    }
}

// Request interceptor: add auth token and CSRF token for state-changing methods
api.interceptors.request.use((config) => {
    const token = localStorage.getItem('token');
    if (token) {
        config.headers.Authorization = `Bearer ${token}`;
    }
    const method = config.method?.toLowerCase();
    if (csrfToken && (method === 'post' || method === 'put' || method === 'patch' || method === 'delete')) {
        config.headers['X-CSRF-Token'] = csrfToken;
    }
    return config;
});

// Response interceptor for error handling
api.interceptors.response.use(
    (response) => response,
    (error) => {
        if (error.response) {
            // Server responded with error
            if (error.response.status === 401) {
                // Unauthorized - token invalid or expired
                localStorage.removeItem('token');
                localStorage.removeItem('role');
                localStorage.removeItem('display_name');
                localStorage.removeItem('username');
                if (typeof window !== 'undefined') {
                    window.location.href = '/login';
                }
            }
        } else if (error.request) {
            // Request made but no response
            console.error('No response from server. Is backend running?');
        } else {
            // Error setting up request
            console.error('Request error:', error.message);
        }
        return Promise.reject(error);
    }
);

// App download links (public GET; admin PUT to update). Used on the public Download Apps page.
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

export const updateAppDownloads = async (links: AppDownloadLinks): Promise<void> => {
    await api.put('/admin/app-downloads', links);
};

// Current admin account info (for dashboard)
export interface AdminMe {
    display_name: string;
    email: string;
    full_name: string;
    email_2fa_enabled: boolean;
}

export const getAdminMe = async (): Promise<AdminMe> => {
    const response = await api.get<AdminMe>('/admin/me');
    return response.data;
};

export const updateAdminMe = async (data: { email: string; full_name: string }): Promise<void> => {
    await api.put('/admin/me', data);
};

// 2FA (admin only) — email OTP: code sent to account email after password
export const get2FAStatus = async (): Promise<{ enabled: boolean }> => {
    const response = await api.get<{ enabled: boolean }>('/admin/2fa/status');
    return response.data;
};

export const enable2FA = async (): Promise<void> => {
    await api.post('/admin/2fa/enable');
};

export const disable2FA = async (password: string): Promise<void> => {
    await api.post('/admin/2fa/disable', { password });
};

export default api;

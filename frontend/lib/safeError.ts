/**
 * Safe error handling: never expose API/stack details to the UI.
 * Use generic user-facing messages; log full error only in console.
 */

type AxiosLikeError = {
  response?: { data?: unknown; status?: number };
  message?: string;
  code?: string;
};

export type ErrorContext =
  | 'auth'
  | 'register'
  | 'forgot_password'
  | 'forgot_username'
  | 'reset_password'
  | 'payment'
  | 'upload'
  | 'payout'
  | 'wallet'
  | 'referral'
  | 'user'
  | 'dashboard'
  | 'orders'
  | 'export'
  | 'network'
  | 'shop'
  | 'generic';

const GENERIC_MESSAGES: Record<ErrorContext, string> = {
  auth: 'Invalid credentials. Please try again.',
  register: 'Registration failed. Please check your details and try again.',
  forgot_password: 'Could not send reset email. Please try again later.',
  forgot_username: 'Could not retrieve username. Please try again later.',
  reset_password: 'Could not reset password. Please try again.',
  payment: 'Payment could not be processed. Please try again.',
  upload: 'Upload failed. Please try again.',
  payout: 'Action failed. Please try again.',
  wallet: 'Wallet action failed. Please try again.',
  referral: 'Could not load your referral code. Refresh the page or tap Retry.',
  user: 'Action failed. Please try again.',
  dashboard: 'Could not load data. Please try again.',
  orders: 'Could not load orders. Please try again.',
  export: 'Export failed. Please try again.',
  network: 'Cannot connect. Please check your connection and try again.',
  shop: 'Could not load shop. Please check the code and try again.',
  generic: 'Something went wrong. Please try again.',
};

/** Safe backend messages we can show for register (validation / already in use). */
function getRegisterBackendMessage(data: unknown): string | null {
  const msg =
    typeof data === 'string'
      ? data
      : data != null && typeof data === 'object'
        ? (data as { message?: string }).message ?? (data as { error?: string }).error
        : null;
  if (typeof msg !== 'string' || msg.length > 200) return null;
  const s = msg.toLowerCase();
  if (
    s.includes('already in use') ||
    s.includes('required') ||
    s.includes('invalid') ||
    s.includes('must be') ||
    s.includes('can only contain') ||
    s.includes('characters') ||
    s.includes('digits') ||
    s.includes('format')
  ) {
    return msg;
  }
  return null;
}

/**
 * Returns a safe user-facing message. Never returns raw API/stack details.
 * For register, passes through known safe backend validation messages.
 */
export function getSafeErrorMessage(
  err: unknown,
  context: ErrorContext = 'generic'
): string {
  if (typeof err !== 'object' || err === null) {
    return GENERIC_MESSAGES[context];
  }
  const e = err as AxiosLikeError;
  const isNetwork =
    e.code === 'ERR_NETWORK' ||
    e.message === 'Network Error' ||
    (e.response?.status === undefined && e.message);
  if (isNetwork) {
    return GENERIC_MESSAGES.network;
  }
  if (context === 'register' && e.response?.status === 400 && e.response?.data != null) {
    const backendMsg = getRegisterBackendMessage(e.response.data);
    if (backendMsg) return backendMsg;
  }
  const fileValidationMsg = (data: unknown): string | null => {
    const msg =
      typeof data === 'string'
        ? data
        : data != null && typeof data === 'object'
          ? (data as { error?: string }).error
          : null;
    if (typeof msg !== 'string' || msg.length === 0 || msg.length >= 400) return null;
    const s = msg.toLowerCase();
    if (
      s.includes('corrupted') ||
      s.includes('invalid') ||
      s.includes('does not match') ||
      s.includes('valid pdf') ||
      s.includes('valid png') ||
      s.includes('valid jpeg') ||
      s.includes('valid jpg') ||
      s.includes('exceeds') ||
      s.includes('not supported')
    ) {
      return msg;
    }
    return null;
  };
  if (context === 'upload' && e.response?.data != null) {
    const msg = fileValidationMsg(e.response.data);
    if (msg) return msg;
  }
  if (context === 'payment' && e.response?.status === 400 && e.response?.data != null) {
    const msg = fileValidationMsg(e.response.data);
    if (msg) return msg;
  }
  return GENERIC_MESSAGES[context];
}

import { apiRequest } from './api.js';
import { clearState, patchState, getState } from './storage.js';

export async function sendOtp(email, tenantSlug) {
  patchState({ tenantSlug });
  return apiRequest('/auth/send-otp', { body: { email, tenant_slug: tenantSlug } });
}

export async function verifyOtp(email, otp, tenantSlug) {
  const response = await apiRequest('/auth/verify-otp', {
    body: { email, otp, tenant_slug: tenantSlug },
  });

  patchState({
    tenantSlug,
    accessToken: response?.data?.access_token,
    refreshToken: response?.data?.refresh_token,
  });

  return response;
}

export async function refreshAuth() {
  const state = getState();
  if (!state.refreshToken) {
    throw new Error('No refresh token found');
  }

  const response = await apiRequest('/auth/refresh', {
    body: { refresh_token: state.refreshToken },
  });

  patchState({
    accessToken: response?.data?.access_token,
    refreshToken: response?.data?.refresh_token,
  });

  return response;
}

export function logoutLocal() {
  clearState();
}

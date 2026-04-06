import { APP_CONFIG } from './config.js';
import { getState, patchState } from './storage.js';

function buildHeaders(extra = {}) {
  const state = getState();
  const headers = {
    'Content-Type': 'application/json',
    ...extra,
  };

  if (state.accessToken) {
    headers.Authorization = `Bearer ${state.accessToken}`;
  }

  return headers;
}

async function parseJson(response) {
  const text = await response.text();
  return text ? JSON.parse(text) : {};
}

export async function apiRequest(path, { method = 'POST', body, headers } = {}) {
  const state = getState();
  const payload = body ? { tenant_slug: state.tenantSlug || APP_CONFIG.tenantDefault, ...body } : undefined;

  const response = await fetch(`${APP_CONFIG.apiBase}${path}`, {
    method,
    headers: buildHeaders(headers),
    body: payload ? JSON.stringify(payload) : undefined,
  });

  const data = await parseJson(response);

  if (!response.ok) {
    throw {
      status: response.status,
      code: data?.error?.code || data?.error || 'REQUEST_FAILED',
      message: data?.error?.message || data?.error || 'Request failed',
      raw: data,
    };
  }

  if (data?.data?.refresh_token) {
    patchState({ refreshToken: data.data.refresh_token });
  }

  return data;
}

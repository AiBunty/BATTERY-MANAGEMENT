import { apiRequest } from './api.js';
import { getState } from './storage.js';

export async function fetchClaims(status = '', limit = 20) {
  const body = { dealer_email: getState().userEmail || '', limit };
  if (status) body.status = status;
  return apiRequest('/claims/list', { method: 'POST', body });
}

export async function checkSerial(serial) {
  return apiRequest('/claims/check-serial', {
    method: 'POST',
    body: { serial },
  });
}

export async function createClaim({ serial, complaint }) {
  const key = `${Date.now()}-${serial}`;
  return apiRequest('/claims', {
    method: 'POST',
    body: {
      serial,
      complaint,
      dealer_email: getState().userEmail || '',
    },
    headers: { 'Idempotency-Key': key },
  });
}

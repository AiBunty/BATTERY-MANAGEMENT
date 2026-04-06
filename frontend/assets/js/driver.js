import { apiRequest } from './api.js';
import { getState } from './storage.js';

export async function fetchActiveRoute() {
  const state = getState();
  return apiRequest('/driver/routes/active', {
    method: 'POST',
    body: { driver_email: state.userEmail || '' },
  });
}

export async function completePodTask({ taskId, batchPhoto, dealerSignature }) {
  return apiRequest('/driver/tasks/complete', {
    method: 'POST',
    body: {
      task_id: taskId,
      batch_photo: batchPhoto,
      dealer_signature: dealerSignature,
    },
  });
}

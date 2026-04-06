import { apiRequest } from './api.js';

export async function fetchDashboardStats() {
  return apiRequest('/crm/dashboard-stats', {
    method: 'POST',
    body: {},
  });
}

export async function fetchCustomers(lifecycleStage = '', limit = 20) {
  const body = { limit };
  if (lifecycleStage) body.lifecycle_stage = lifecycleStage;
  return apiRequest('/crm/customers/list', {
    method: 'POST',
    body,
  });
}

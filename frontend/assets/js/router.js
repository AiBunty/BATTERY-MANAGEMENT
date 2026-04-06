import { PAGE_PERMISSIONS } from './roles.js';

export function isPageAllowed(pageKey, role) {
  const allowed = PAGE_PERMISSIONS[pageKey];
  if (!allowed) return true;
  if (allowed.includes('PUBLIC') && !role) return true;
  return allowed.includes(role || '');
}

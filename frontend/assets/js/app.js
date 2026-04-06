import { getState, patchState } from './storage.js';
import { ROLE_MENU } from './roles.js';
import { isPageAllowed } from './router.js';
import { logoutLocal } from './auth.js';
import { showToast } from './ui.js';

function inPagesDirectory() {
  return window.location.pathname.includes('/pages/');
}

function partialPrefix() {
  return inPagesDirectory() ? '../../' : './';
}

function pageHref(path) {
  return inPagesDirectory() ? `../${path}` : `./pages/${path}`;
}

async function loadPartial(path) {
  const response = await fetch(path);
  return response.text();
}

function renderMenu(role, pageFileName) {
  const menu = ROLE_MENU[role] || [];
  return menu
    .map((item) => {
      const href = pageHref(item.path);
      const active = pageFileName.endsWith(item.path.split('/').pop()) ? 'is-active' : '';
      return `<li class="menu-item"><a class="menu-link ${active}" href="${href}">${item.label}</a></li>`;
    })
    .join('');
}

function renderDenied() {
  const slot = document.getElementById('page-slot');
  if (!slot) return;
  slot.innerHTML = '<div class="state">Permission denied for this page.</div>';
}

async function boot() {
  const shellRoot = document.getElementById('app-shell');
  if (!shellRoot) return;

  const state = getState();
  if (!state.tenantSlug) {
    patchState({ tenantSlug: 'default' });
  }

  const role = document.body.dataset.role || state.role || 'ADMIN';
  const pageKey = document.body.dataset.page || '';
  const pageFileName = window.location.pathname.split('/').pop() || '';

  const shellHtml = await loadPartial(`${partialPrefix()}partials/shell.html`);
  shellRoot.innerHTML = shellHtml;

  const sidebar = document.getElementById('sidebar-slot');
  const topbar = document.getElementById('topbar-slot');

  if (sidebar) {
    const sidebarHtml = await loadPartial(`${partialPrefix()}partials/sidebar.html`);
    sidebar.innerHTML = sidebarHtml;
    const roleMenu = document.getElementById('role-menu');
    if (roleMenu) roleMenu.innerHTML = renderMenu(role, pageFileName);
  }

  if (topbar) {
    const topbarHtml = await loadPartial(`${partialPrefix()}partials/topbar.html`);
    topbar.innerHTML = topbarHtml;
    const roleBadge = document.getElementById('role-badge');
    if (roleBadge) roleBadge.textContent = `Role: ${role}`;
    const tenantBadge = document.getElementById('tenant-badge');
    if (tenantBadge) tenantBadge.textContent = `Tenant: ${getState().tenantSlug || 'default'}`;
  }

  if (!isPageAllowed(pageKey, role)) {
    renderDenied();
    return;
  }

  const section = document.querySelector('section[data-page-content]');
  const pageSlot = document.getElementById('page-slot');
  if (section && pageSlot) {
    pageSlot.appendChild(section);
  }

  const logoutBtn = document.querySelector('[data-action="logout"]');
  if (logoutBtn) {
    logoutBtn.addEventListener('click', () => {
      logoutLocal();
      showToast('Logged out', 'success');
      window.location.href = inPagesDirectory() ? '../../index.html' : './index.html';
    });
  }
}

boot().catch((error) => {
  console.error(error);
  showToast('Frontend initialization failed', 'error');
});

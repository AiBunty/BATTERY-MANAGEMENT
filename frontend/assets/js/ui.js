export function showToast(message, type = 'success') {
  const root = document.getElementById('toast-root');
  if (!root) return;

  const tone = type === 'error' ? 'danger' : type;
  const el = document.createElement('div');
  el.className = `toast toast--${tone}`;
  el.setAttribute('role', 'status');
  el.textContent = message;
  root.appendChild(el);

  setTimeout(() => {
    el.remove();
  }, 2400);
}

export function setHtml(id, html) {
  const node = document.getElementById(id);
  if (node) node.innerHTML = html;
}

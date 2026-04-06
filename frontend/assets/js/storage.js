const KEY = 'bm_frontend_state';

export function getState() {
  try {
    const raw = localStorage.getItem(KEY);
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

export function setState(next) {
  localStorage.setItem(KEY, JSON.stringify(next));
}

export function patchState(patch) {
  const current = getState();
  const merged = { ...current, ...patch };
  setState(merged);
  return merged;
}

export function clearState() {
  localStorage.removeItem(KEY);
}

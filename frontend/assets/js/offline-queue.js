const KEY = 'bm_driver_offline_queue';

export function getQueue() {
  try {
    const raw = localStorage.getItem(KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

export function enqueue(item) {
  const queue = getQueue();
  queue.push({ ...item, queuedAt: new Date().toISOString() });
  localStorage.setItem(KEY, JSON.stringify(queue));
  return queue.length;
}

export function clearQueue() {
  localStorage.removeItem(KEY);
}

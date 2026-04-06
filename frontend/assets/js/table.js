export function createClientTableModel(rows, { query = '', page = 1, perPage = 10 } = {}) {
  const lowered = query.trim().toLowerCase();
  const filtered = lowered
    ? rows.filter((row) => JSON.stringify(row).toLowerCase().includes(lowered))
    : rows;
  const start = (page - 1) * perPage;
  return {
    total: filtered.length,
    rows: filtered.slice(start, start + perPage),
  };
}

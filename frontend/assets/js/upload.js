export function validateUpload(file, { maxSizeMb = 5, allowedTypes = [] } = {}) {
  if (!file) return { ok: false, message: 'No file selected' };
  if (file.size > maxSizeMb * 1024 * 1024) {
    return { ok: false, message: `File exceeds ${maxSizeMb}MB` };
  }
  if (allowedTypes.length && !allowedTypes.includes(file.type)) {
    return { ok: false, message: 'Unsupported file type' };
  }
  return { ok: true };
}

export function createPreviewUrl(file) {
  return URL.createObjectURL(file);
}

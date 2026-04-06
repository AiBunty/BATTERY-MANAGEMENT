export function validateRequired(fields) {
  const errors = {};
  Object.entries(fields).forEach(([key, value]) => {
    if (value === null || value === undefined || String(value).trim() === '') {
      errors[key] = 'Required';
    }
  });
  return errors;
}

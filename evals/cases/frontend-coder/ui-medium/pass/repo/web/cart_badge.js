export function render(cart) {
  const error = cart.error ? `<p role="alert" class="field-error">${cart.error}</p>` : "";
  return `<span class="badge">${cart.count}</span>${error}`;
}

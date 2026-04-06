export function initMapPanel(containerId, center = { lat: 18.5204, lng: 73.8567 }, zoom = 11) {
  if (!window.google || !window.google.maps) {
    return null;
  }

  const container = document.getElementById(containerId);
  if (!container) return null;

  return new window.google.maps.Map(container, {
    center,
    zoom,
    disableDefaultUI: true,
  });
}

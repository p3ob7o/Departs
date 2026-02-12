import { vi } from "vitest";

const mapboxgl = {
  Map: vi.fn(() => ({
    on: vi.fn(),
    off: vi.fn(),
    remove: vi.fn(),
    getCanvas: vi.fn(() => ({ style: {} })),
    addControl: vi.fn(),
    removeControl: vi.fn(),
    setCenter: vi.fn(),
    setZoom: vi.fn(),
    fitBounds: vi.fn(),
    resize: vi.fn(),
  })),
  NavigationControl: vi.fn(),
  GeolocateControl: vi.fn(),
  Marker: vi.fn(() => ({
    setLngLat: vi.fn().mockReturnThis(),
    addTo: vi.fn().mockReturnThis(),
    remove: vi.fn(),
  })),
  Popup: vi.fn(() => ({
    setLngLat: vi.fn().mockReturnThis(),
    setHTML: vi.fn().mockReturnThis(),
    addTo: vi.fn().mockReturnThis(),
    remove: vi.fn(),
  })),
  accessToken: "",
};

export default mapboxgl;

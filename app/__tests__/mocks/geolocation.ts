type SuccessCallback = (position: GeolocationPosition) => void;
type ErrorCallback = (error: GeolocationPositionError) => void;

interface MockGeolocation {
  getCurrentPosition: ReturnType<typeof vi.fn>;
  watchPosition: ReturnType<typeof vi.fn>;
  clearWatch: ReturnType<typeof vi.fn>;
  mockSuccess: (coords?: { latitude: number; longitude: number }) => void;
  mockError: (code: number, message?: string) => void;
}

import { vi } from "vitest";

export function createMockGeolocation(): MockGeolocation {
  let successCb: SuccessCallback | null = null;
  let errorCb: ErrorCallback | null = null;

  const mock: MockGeolocation = {
    getCurrentPosition: vi.fn(
      (success: SuccessCallback, error?: ErrorCallback) => {
        successCb = success;
        errorCb = error ?? null;
      }
    ),
    watchPosition: vi.fn(),
    clearWatch: vi.fn(),
    mockSuccess(coords = { latitude: 52.52, longitude: 13.405 }) {
      if (successCb) {
        successCb({
          coords: {
            ...coords,
            accuracy: 10,
            altitude: null,
            altitudeAccuracy: null,
            heading: null,
            speed: null,
          },
          timestamp: Date.now(),
        } as GeolocationPosition);
      }
    },
    mockError(code: number, message = "Geolocation error") {
      if (errorCb) {
        errorCb({
          code,
          message,
          PERMISSION_DENIED: 1,
          POSITION_UNAVAILABLE: 2,
          TIMEOUT: 3,
        } as GeolocationPositionError);
      }
    },
  };

  return mock;
}

export function installMockGeolocation(mock: MockGeolocation) {
  Object.defineProperty(navigator, "geolocation", {
    value: mock,
    writable: true,
    configurable: true,
  });
}

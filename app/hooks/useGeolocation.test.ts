import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { renderHook, act } from "@testing-library/react";
import { useGeolocation } from "@/app/hooks/useGeolocation";
import {
  createMockGeolocation,
  installMockGeolocation,
} from "@/app/__tests__/mocks/geolocation";

describe("useGeolocation", () => {
  let mockGeo: ReturnType<typeof createMockGeolocation>;

  beforeEach(() => {
    mockGeo = createMockGeolocation();
    installMockGeolocation(mockGeo);
  });

  afterEach(() => {
    // @ts-expect-error — resetting mock
    delete navigator.geolocation;
  });

  it("starts in loading state", () => {
    const { result } = renderHook(() => useGeolocation());

    expect(result.current.loading).toBe(true);
    expect(result.current.coords).toBeNull();
    expect(result.current.error).toBeNull();
  });

  it("calls getCurrentPosition on mount", () => {
    renderHook(() => useGeolocation());

    expect(mockGeo.getCurrentPosition).toHaveBeenCalledTimes(1);
  });

  it("returns coordinates on success", async () => {
    const { result } = renderHook(() => useGeolocation());

    act(() => {
      mockGeo.mockSuccess({ latitude: 52.52, longitude: 13.405 });
    });

    expect(result.current.loading).toBe(false);
    expect(result.current.coords).toEqual({ lat: 52.52, lon: 13.405 });
    expect(result.current.error).toBeNull();
  });

  it("returns permission denied error", async () => {
    const { result } = renderHook(() => useGeolocation());

    act(() => {
      mockGeo.mockError(1, "User denied Geolocation");
    });

    expect(result.current.loading).toBe(false);
    expect(result.current.coords).toBeNull();
    expect(result.current.error).toBe("permission_denied");
  });

  it("returns position unavailable error", async () => {
    const { result } = renderHook(() => useGeolocation());

    act(() => {
      mockGeo.mockError(2, "Position unavailable");
    });

    expect(result.current.loading).toBe(false);
    expect(result.current.error).toBe("position_unavailable");
  });

  it("returns timeout error", async () => {
    const { result } = renderHook(() => useGeolocation());

    act(() => {
      mockGeo.mockError(3, "Timeout");
    });

    expect(result.current.loading).toBe(false);
    expect(result.current.error).toBe("timeout");
  });

  it("provides a retry function that re-triggers geolocation", async () => {
    const { result } = renderHook(() => useGeolocation());

    act(() => {
      mockGeo.mockError(1);
    });

    expect(result.current.error).toBe("permission_denied");

    act(() => {
      result.current.retry();
    });

    expect(result.current.loading).toBe(true);
    expect(mockGeo.getCurrentPosition).toHaveBeenCalledTimes(2);
  });

  it("passes high accuracy and timeout options", () => {
    renderHook(() => useGeolocation());

    const options = mockGeo.getCurrentPosition.mock.calls[0][2];
    expect(options?.enableHighAccuracy).toBe(true);
    expect(options?.timeout).toBe(10000);
  });
});

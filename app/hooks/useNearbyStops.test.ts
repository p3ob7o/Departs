import { describe, it, expect, vi } from "vitest";
import { renderHook, waitFor } from "@testing-library/react";
import { useNearbyStops } from "@/app/hooks/useNearbyStops";
import { nearbyStops } from "@/app/__tests__/fixtures/nearby-stops";

// Mock the api module
vi.mock("@/app/lib/api", () => ({
  fetchNearbyStops: vi.fn(),
}));

describe("useNearbyStops", () => {
  it("starts in loading state when coords are provided", () => {
    const { result } = renderHook(() =>
      useNearbyStops({ lat: 52.52, lon: 13.405 })
    );

    expect(result.current.loading).toBe(true);
    expect(result.current.stops).toEqual([]);
    expect(result.current.error).toBeNull();
  });

  it("does not fetch when coords are null", () => {
    const { result } = renderHook(() => useNearbyStops(null));

    expect(result.current.loading).toBe(false);
    expect(result.current.stops).toEqual([]);
  });

  it("returns stops on successful fetch", async () => {
    const { fetchNearbyStops } = await import("@/app/lib/api");
    vi.mocked(fetchNearbyStops).mockResolvedValueOnce(nearbyStops);

    const { result } = renderHook(() =>
      useNearbyStops({ lat: 52.52, lon: 13.405 })
    );

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(result.current.stops).toEqual(nearbyStops);
    expect(result.current.error).toBeNull();
  });

  it("returns error on fetch failure", async () => {
    const { fetchNearbyStops } = await import("@/app/lib/api");
    vi.mocked(fetchNearbyStops).mockRejectedValueOnce(new Error("Network error"));

    const { result } = renderHook(() =>
      useNearbyStops({ lat: 52.52, lon: 13.405 })
    );

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(result.current.stops).toEqual([]);
    expect(result.current.error).toBe("network");
  });

  it("refetches when coordinates change", async () => {
    const { fetchNearbyStops } = await import("@/app/lib/api");
    vi.mocked(fetchNearbyStops).mockResolvedValue(nearbyStops);

    const { result, rerender } = renderHook(
      (coords) => useNearbyStops(coords),
      { initialProps: { lat: 52.52, lon: 13.405 } as { lat: number; lon: number } }
    );

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    rerender({ lat: 52.53, lon: 13.41 });

    await waitFor(() => {
      expect(fetchNearbyStops).toHaveBeenCalledTimes(2);
    });
  });
});

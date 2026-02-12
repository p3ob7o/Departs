import { describe, it, expect, vi } from "vitest";
import { renderHook, waitFor } from "@testing-library/react";
import { useDepartures } from "@/app/hooks/useDepartures";
import { departures } from "@/app/__tests__/fixtures/departures";
import { walkingRoute } from "@/app/__tests__/fixtures/walking-route";

// Mock the api module
vi.mock("@/app/lib/api", () => ({
  fetchDepartures: vi.fn(),
  fetchDirections: vi.fn(),
}));

describe("useDepartures", () => {
  const userCoords = { lat: 52.5195, lon: 13.4 };
  const stopLocation = { lat: 52.52, lon: 13.405 };

  it("starts in loading state when stopId is provided", () => {
    const { result } = renderHook(() =>
      useDepartures("stop-1", userCoords, stopLocation)
    );

    expect(result.current.loading).toBe(true);
    expect(result.current.departures).toEqual([]);
    expect(result.current.walkingRoute).toBeNull();
  });

  it("does not fetch when stopId is null", () => {
    const { result } = renderHook(() =>
      useDepartures(null, userCoords, stopLocation)
    );

    expect(result.current.loading).toBe(false);
    expect(result.current.departures).toEqual([]);
  });

  it("fetches departures and directions in parallel", async () => {
    const { fetchDepartures, fetchDirections } = await import("@/app/lib/api");
    vi.mocked(fetchDepartures).mockResolvedValueOnce(departures);
    vi.mocked(fetchDirections).mockResolvedValueOnce(walkingRoute);

    const { result } = renderHook(() =>
      useDepartures("stop-1", userCoords, stopLocation)
    );

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(result.current.departures).toEqual(departures);
    expect(result.current.walkingRoute).toEqual(walkingRoute);
  });

  it("still shows departures when directions fail (graceful degradation)", async () => {
    const { fetchDepartures, fetchDirections } = await import("@/app/lib/api");
    vi.mocked(fetchDepartures).mockResolvedValueOnce(departures);
    vi.mocked(fetchDirections).mockRejectedValueOnce(new Error("API error"));

    const { result } = renderHook(() =>
      useDepartures("stop-1", userCoords, stopLocation)
    );

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(result.current.departures).toEqual(departures);
    expect(result.current.walkingRoute).toBeNull();
    expect(result.current.error).toBeNull();
  });

  it("returns error when departures fetch fails", async () => {
    const { fetchDepartures, fetchDirections } = await import("@/app/lib/api");
    vi.mocked(fetchDepartures).mockRejectedValueOnce(new Error("Network error"));
    vi.mocked(fetchDirections).mockResolvedValueOnce(walkingRoute);

    const { result } = renderHook(() =>
      useDepartures("stop-1", userCoords, stopLocation)
    );

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(result.current.departures).toEqual([]);
    expect(result.current.error).toBe("network");
  });

  it("refetches when stopId changes", async () => {
    const { fetchDepartures, fetchDirections } = await import("@/app/lib/api");
    vi.mocked(fetchDepartures).mockResolvedValue(departures);
    vi.mocked(fetchDirections).mockResolvedValue(walkingRoute);

    const { result, rerender } = renderHook(
      ({ stopId }) => useDepartures(stopId, userCoords, stopLocation),
      { initialProps: { stopId: "stop-1" as string | null } }
    );

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    rerender({ stopId: "stop-2" });

    await waitFor(() => {
      expect(fetchDepartures).toHaveBeenCalledTimes(2);
    });
  });
});

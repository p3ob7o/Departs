import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import Home from "@/app/page";
import {
  createMockGeolocation,
  installMockGeolocation,
} from "@/app/__tests__/mocks/geolocation";
import { nearbyStops } from "@/app/__tests__/fixtures/nearby-stops";
import { departures } from "@/app/__tests__/fixtures/departures";
import { walkingRoute } from "@/app/__tests__/fixtures/walking-route";

// Mock hooks
vi.mock("@/app/hooks/useGeolocation", () => ({
  useGeolocation: vi.fn(),
}));

vi.mock("@/app/hooks/useNearbyStops", () => ({
  useNearbyStops: vi.fn(),
}));

vi.mock("@/app/hooks/useDepartures", () => ({
  useDepartures: vi.fn(),
}));

describe("Home page", () => {
  let mockGeo: ReturnType<typeof createMockGeolocation>;

  beforeEach(() => {
    mockGeo = createMockGeolocation();
    installMockGeolocation(mockGeo);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("shows loading state initially", async () => {
    const { useGeolocation } = await import("@/app/hooks/useGeolocation");
    vi.mocked(useGeolocation).mockReturnValue({
      loading: true,
      coords: null,
      error: null,
      retry: vi.fn(),
    });

    const { useNearbyStops } = await import("@/app/hooks/useNearbyStops");
    vi.mocked(useNearbyStops).mockReturnValue({
      loading: false,
      stops: [],
      error: null,
    });

    const { useDepartures } = await import("@/app/hooks/useDepartures");
    vi.mocked(useDepartures).mockReturnValue({
      loading: false,
      departures: [],
      walkingRoute: null,
      error: null,
    });

    render(<Home />);

    expect(screen.getByRole("status")).toBeInTheDocument();
  });

  it("transitions to nearby stops view after geolocation + fetch", async () => {
    const { useGeolocation } = await import("@/app/hooks/useGeolocation");
    vi.mocked(useGeolocation).mockReturnValue({
      loading: false,
      coords: { lat: 52.52, lon: 13.405 },
      error: null,
      retry: vi.fn(),
    });

    const { useNearbyStops } = await import("@/app/hooks/useNearbyStops");
    vi.mocked(useNearbyStops).mockReturnValue({
      loading: false,
      stops: nearbyStops,
      error: null,
    });

    const { useDepartures } = await import("@/app/hooks/useDepartures");
    vi.mocked(useDepartures).mockReturnValue({
      loading: false,
      departures: [],
      walkingRoute: null,
      error: null,
    });

    render(<Home />);

    expect(screen.getByText("Central Station")).toBeInTheDocument();
    expect(screen.getByText("Market Square")).toBeInTheDocument();
  });

  it("transitions to departure detail when a stop is selected", async () => {
    const user = userEvent.setup();

    const { useGeolocation } = await import("@/app/hooks/useGeolocation");
    vi.mocked(useGeolocation).mockReturnValue({
      loading: false,
      coords: { lat: 52.52, lon: 13.405 },
      error: null,
      retry: vi.fn(),
    });

    const { useNearbyStops } = await import("@/app/hooks/useNearbyStops");
    vi.mocked(useNearbyStops).mockReturnValue({
      loading: false,
      stops: nearbyStops,
      error: null,
    });

    const { useDepartures } = await import("@/app/hooks/useDepartures");
    vi.mocked(useDepartures).mockReturnValue({
      loading: false,
      departures: departures,
      walkingRoute: walkingRoute,
      error: null,
    });

    render(<Home />);

    // Tap on a stop
    await user.click(screen.getAllByRole("button")[0]);

    // Should show departure times
    await waitFor(() => {
      expect(screen.getAllByRole("time")).toHaveLength(4);
    });
  });

  it("shows error state when geolocation is denied", async () => {
    const { useGeolocation } = await import("@/app/hooks/useGeolocation");
    vi.mocked(useGeolocation).mockReturnValue({
      loading: false,
      coords: null,
      error: "permission_denied",
      retry: vi.fn(),
    });

    const { useNearbyStops } = await import("@/app/hooks/useNearbyStops");
    vi.mocked(useNearbyStops).mockReturnValue({
      loading: false,
      stops: [],
      error: null,
    });

    const { useDepartures } = await import("@/app/hooks/useDepartures");
    vi.mocked(useDepartures).mockReturnValue({
      loading: false,
      departures: [],
      walkingRoute: null,
      error: null,
    });

    render(<Home />);

    expect(screen.getByText(/location permission/i)).toBeInTheDocument();
  });

  it("shows error state when API fetch fails", async () => {
    const { useGeolocation } = await import("@/app/hooks/useGeolocation");
    vi.mocked(useGeolocation).mockReturnValue({
      loading: false,
      coords: { lat: 52.52, lon: 13.405 },
      error: null,
      retry: vi.fn(),
    });

    const { useNearbyStops } = await import("@/app/hooks/useNearbyStops");
    vi.mocked(useNearbyStops).mockReturnValue({
      loading: false,
      stops: [],
      error: "network",
    });

    const { useDepartures } = await import("@/app/hooks/useDepartures");
    vi.mocked(useDepartures).mockReturnValue({
      loading: false,
      departures: [],
      walkingRoute: null,
      error: null,
    });

    render(<Home />);

    expect(screen.getByText(/couldn't load/i)).toBeInTheDocument();
  });

  it("allows retry from error state", async () => {
    const retryFn = vi.fn();
    const user = userEvent.setup();

    const { useGeolocation } = await import("@/app/hooks/useGeolocation");
    vi.mocked(useGeolocation).mockReturnValue({
      loading: false,
      coords: null,
      error: "permission_denied",
      retry: retryFn,
    });

    const { useNearbyStops } = await import("@/app/hooks/useNearbyStops");
    vi.mocked(useNearbyStops).mockReturnValue({
      loading: false,
      stops: [],
      error: null,
    });

    const { useDepartures } = await import("@/app/hooks/useDepartures");
    vi.mocked(useDepartures).mockReturnValue({
      loading: false,
      departures: [],
      walkingRoute: null,
      error: null,
    });

    render(<Home />);

    await user.click(screen.getByRole("button", { name: /retry/i }));

    expect(retryFn).toHaveBeenCalledTimes(1);
  });
});

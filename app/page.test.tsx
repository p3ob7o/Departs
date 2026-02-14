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

/** Helper: set up all three hooks with the given overrides */
async function setupHooks(overrides: {
  geo?: Partial<ReturnType<typeof import("@/app/hooks/useGeolocation").useGeolocation>>;
  stops?: Partial<ReturnType<typeof import("@/app/hooks/useNearbyStops").useNearbyStops>>;
  deps?: Partial<ReturnType<typeof import("@/app/hooks/useDepartures").useDepartures>>;
} = {}) {
  const { useGeolocation } = await import("@/app/hooks/useGeolocation");
  vi.mocked(useGeolocation).mockReturnValue({
    loading: false,
    coords: { lat: 52.52, lon: 13.405 },
    error: null,
    retry: vi.fn(),
    ...overrides.geo,
  });

  const { useNearbyStops } = await import("@/app/hooks/useNearbyStops");
  vi.mocked(useNearbyStops).mockReturnValue({
    loading: false,
    stops: nearbyStops,
    error: null,
    ...overrides.stops,
  });

  const { useDepartures } = await import("@/app/hooks/useDepartures");
  vi.mocked(useDepartures).mockReturnValue({
    loading: false,
    departures: departures,
    walkingRoute: walkingRoute,
    error: null,
    ...overrides.deps,
  });
}

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
    await setupHooks({ geo: { loading: true, coords: null } });
    render(<Home />);
    expect(screen.getByRole("status")).toBeInTheDocument();
  });

  it("transitions to nearby stops view after geolocation + fetch", async () => {
    await setupHooks();
    render(<Home />);
    expect(screen.getByText("Central Station")).toBeInTheDocument();
    expect(screen.getByText("Market Square")).toBeInTheDocument();
  });

  it("transitions to departure detail when a stop is selected", async () => {
    const user = userEvent.setup();
    await setupHooks();
    render(<Home />);

    // Tap on a stop
    await user.click(screen.getAllByRole("button")[0]);

    // Should show departure times
    await waitFor(() => {
      expect(screen.getAllByRole("time")).toHaveLength(4);
    });
  });

  it("shows error state when geolocation is denied", async () => {
    await setupHooks({
      geo: { loading: false, coords: null, error: "permission_denied" },
      stops: { stops: [] },
    });
    render(<Home />);
    expect(screen.getByText(/location permission/i)).toBeInTheDocument();
  });

  it("shows error state when API fetch fails", async () => {
    await setupHooks({
      stops: { stops: [], error: "network" },
    });
    render(<Home />);
    expect(screen.getByText(/couldn't load/i)).toBeInTheDocument();
  });

  it("allows retry from error state", async () => {
    const retryFn = vi.fn();
    const user = userEvent.setup();
    await setupHooks({
      geo: { loading: false, coords: null, error: "permission_denied", retry: retryFn },
      stops: { stops: [] },
    });
    render(<Home />);
    await user.click(screen.getByRole("button", { name: /retry/i }));
    expect(retryFn).toHaveBeenCalledTimes(1);
  });

  // --- Integration tests: MapView and BottomSheet are rendered ---

  it("renders the map in the stops view", async () => {
    await setupHooks();
    render(<Home />);
    expect(screen.getByTestId("map")).toBeInTheDocument();
  });

  it("renders the bottom sheet in the stops view", async () => {
    await setupHooks();
    render(<Home />);
    expect(screen.getByTestId("bottom-sheet")).toBeInTheDocument();
    expect(screen.getByTestId("drag-handle")).toBeInTheDocument();
  });

  it("renders stop markers on the map for all nearby stops", async () => {
    await setupHooks();
    render(<Home />);
    // user marker + one per stop
    const markers = screen.getAllByTestId("marker");
    expect(markers.length).toBeGreaterThanOrEqual(nearbyStops.length);
  });

  it("renders the map in departure detail view", async () => {
    const user = userEvent.setup();
    await setupHooks();
    render(<Home />);

    // Select a stop to switch to departure detail
    await user.click(screen.getAllByRole("button")[0]);
    await waitFor(() => {
      expect(screen.getByTestId("map")).toBeInTheDocument();
    });
  });

  it("renders the bottom sheet in departure detail view", async () => {
    const user = userEvent.setup();
    await setupHooks();
    render(<Home />);

    await user.click(screen.getAllByRole("button")[0]);
    await waitFor(() => {
      expect(screen.getByTestId("bottom-sheet")).toBeInTheDocument();
    });
  });

  it("renders walking route on the map when available", async () => {
    const user = userEvent.setup();
    await setupHooks();
    render(<Home />);

    await user.click(screen.getAllByRole("button")[0]);
    await waitFor(() => {
      expect(screen.getByTestId("source")).toBeInTheDocument();
      expect(screen.getByTestId("layer")).toBeInTheDocument();
    });
  });

  it("does not render map or bottom sheet during loading", async () => {
    await setupHooks({ geo: { loading: true, coords: null } });
    render(<Home />);
    expect(screen.queryByTestId("map")).not.toBeInTheDocument();
    expect(screen.queryByTestId("bottom-sheet")).not.toBeInTheDocument();
  });

  it("does not render map or bottom sheet during error", async () => {
    await setupHooks({
      geo: { loading: false, coords: null, error: "permission_denied" },
      stops: { stops: [] },
    });
    render(<Home />);
    expect(screen.queryByTestId("map")).not.toBeInTheDocument();
    expect(screen.queryByTestId("bottom-sheet")).not.toBeInTheDocument();
  });
});

import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { MapView } from "@/app/components/Map";
import { nearbyStops } from "@/app/__tests__/fixtures/nearby-stops";
import { walkingRoute } from "@/app/__tests__/fixtures/walking-route";

describe("MapView", () => {
  const userCoords = { lat: 52.52, lon: 13.405 };

  it("renders the map container", () => {
    render(<MapView userCoords={userCoords} stops={nearbyStops} />);

    expect(screen.getByTestId("map")).toBeInTheDocument();
  });

  it("passes user coordinates to the map", () => {
    render(<MapView userCoords={userCoords} stops={nearbyStops} />);

    const map = screen.getByTestId("map");
    expect(map).toHaveAttribute("data-latitude", "52.52");
    expect(map).toHaveAttribute("data-longitude", "13.405");
  });

  it("uses light style by default", () => {
    render(<MapView userCoords={userCoords} stops={nearbyStops} />);

    const map = screen.getByTestId("map");
    expect(map).toHaveAttribute(
      "data-mapstyle",
      expect.stringContaining("light-v11")
    );
  });

  it("renders user location marker", () => {
    render(<MapView userCoords={userCoords} stops={nearbyStops} />);

    const markers = screen.getAllByTestId("marker");
    expect(markers.length).toBeGreaterThanOrEqual(1);
  });

  it("renders markers for each stop on Screen 1", () => {
    render(<MapView userCoords={userCoords} stops={nearbyStops} />);

    const markers = screen.getAllByTestId("marker");
    // User marker + stop markers
    expect(markers.length).toBeGreaterThanOrEqual(nearbyStops.length);
  });

  it("renders walking route when provided", () => {
    render(
      <MapView
        userCoords={userCoords}
        stops={[nearbyStops[0]]}
        walkingRoute={walkingRoute}
      />
    );

    expect(screen.getByTestId("source")).toBeInTheDocument();
    expect(screen.getByTestId("layer")).toBeInTheDocument();
  });

  it("does not render walking route source when no walking route", () => {
    render(<MapView userCoords={userCoords} stops={nearbyStops} />);

    // The 250m radius circle source should be present, but no walking-route source
    const sources = screen.getAllByTestId("source");
    const hasWalkingRoute = sources.some(
      (s) => s.getAttribute("id") === "walking-route"
    );
    expect(hasWalkingRoute).toBe(false);
  });

  it("renders 250m circle on Screen 1", () => {
    render(<MapView userCoords={userCoords} stops={nearbyStops} />);

    // Should have source elements for the radius circle
    const sources = screen.getAllByTestId("source");
    expect(sources.length).toBeGreaterThanOrEqual(1);
  });

  it("renders green stop pin on Screen 2", () => {
    render(
      <MapView
        userCoords={userCoords}
        stops={[nearbyStops[0]]}
        walkingRoute={walkingRoute}
      />
    );

    // The stop marker should show the transport type name
    expect(screen.getByText(/Subway/)).toBeInTheDocument();
  });
});

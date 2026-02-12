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

  it("uses dark style when darkMode is true", () => {
    render(
      <MapView userCoords={userCoords} stops={nearbyStops} darkMode={true} />
    );

    const map = screen.getByTestId("map");
    expect(map).toHaveAttribute(
      "data-mapstyle",
      expect.stringContaining("dark-v11")
    );
  });

  it("renders markers for each stop", () => {
    render(<MapView userCoords={userCoords} stops={nearbyStops} />);

    const markers = screen.getAllByTestId("marker");
    // User marker + stop markers
    expect(markers.length).toBeGreaterThanOrEqual(nearbyStops.length);
  });

  it("renders walking route when provided", () => {
    render(
      <MapView
        userCoords={userCoords}
        stops={nearbyStops}
        walkingRoute={walkingRoute}
      />
    );

    expect(screen.getByTestId("source")).toBeInTheDocument();
    expect(screen.getByTestId("layer")).toBeInTheDocument();
  });

  it("does not render route layer when no walking route", () => {
    render(<MapView userCoords={userCoords} stops={nearbyStops} />);

    expect(screen.queryByTestId("source")).not.toBeInTheDocument();
  });
});

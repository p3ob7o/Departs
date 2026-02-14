import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { DepartureDetail } from "@/app/components/DepartureDetail";
import { nearbyStops } from "@/app/__tests__/fixtures/nearby-stops";
import { departures } from "@/app/__tests__/fixtures/departures";
import { walkingRoute } from "@/app/__tests__/fixtures/walking-route";

describe("DepartureDetail", () => {
  const stop = nearbyStops[0];
  const onBack = vi.fn();

  it("renders the departures heading", () => {
    render(
      <DepartureDetail
        stop={stop}
        departures={departures}
        walkingRoute={walkingRoute}
        onBack={onBack}
      />
    );

    expect(screen.getByText("Departures:")).toBeInTheDocument();
  });

  it("renders departure rows", () => {
    render(
      <DepartureDetail
        stop={stop}
        departures={departures}
        walkingRoute={walkingRoute}
        onBack={onBack}
      />
    );

    const timeElements = screen.getAllByRole("time");
    expect(timeElements).toHaveLength(4);
  });

  it("renders a back button", () => {
    render(
      <DepartureDetail
        stop={stop}
        departures={departures}
        walkingRoute={walkingRoute}
        onBack={onBack}
      />
    );

    expect(screen.getByRole("button", { name: /back/i })).toBeInTheDocument();
  });

  it("calls onBack when back button is tapped", async () => {
    const user = userEvent.setup();
    render(
      <DepartureDetail
        stop={stop}
        departures={departures}
        walkingRoute={walkingRoute}
        onBack={onBack}
      />
    );

    await user.click(screen.getByRole("button", { name: /back/i }));

    expect(onBack).toHaveBeenCalledTimes(1);
  });

  it("shows walking duration", () => {
    render(
      <DepartureDetail
        stop={stop}
        departures={departures}
        walkingRoute={walkingRoute}
        onBack={onBack}
      />
    );

    // 145.2 seconds ≈ 2 min walk
    expect(screen.getByText(/2\s*min walk/i)).toBeInTheDocument();
  });

  it("gracefully handles null walking route", () => {
    render(
      <DepartureDetail
        stop={stop}
        departures={departures}
        walkingRoute={null}
        onBack={onBack}
      />
    );

    // Should still render departures
    const timeElements = screen.getAllByRole("time");
    expect(timeElements).toHaveLength(4);

    // Walking duration should not be shown
    expect(screen.queryByText(/min walk/i)).not.toBeInTheDocument();
  });

  it("shows line info in the header", () => {
    render(
      <DepartureDetail
        stop={stop}
        departures={departures}
        walkingRoute={walkingRoute}
        onBack={onBack}
      />
    );

    expect(screen.getByText(/U2/)).toBeInTheDocument();
    expect(screen.getByText(/Pankow/)).toBeInTheDocument();
  });
});

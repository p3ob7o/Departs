import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { DepartureRow } from "@/app/components/DepartureRow";
import { departures } from "@/app/__tests__/fixtures/departures";

describe("DepartureRow", () => {
  it("renders the departure time", () => {
    render(<DepartureRow departure={departures[0]} />);

    expect(screen.getByText(/10:05/)).toBeInTheDocument();
  });

  it("uses a semantic <time> element", () => {
    render(<DepartureRow departure={departures[0]} />);

    const timeEl = screen.getByRole("time");
    expect(timeEl).toHaveAttribute("dateTime", "2024-01-15T10:05:00+01:00");
  });

  it("shows real-time indicator when realTime is true", () => {
    render(<DepartureRow departure={departures[1]} />);

    expect(screen.getByTestId("realtime-indicator")).toBeInTheDocument();
  });

  it("does not show real-time indicator when realTime is false", () => {
    render(<DepartureRow departure={departures[0]} />);

    expect(screen.queryByTestId("realtime-indicator")).not.toBeInTheDocument();
  });

  it("shows delay when present", () => {
    render(<DepartureRow departure={departures[1]} />);

    // 120 seconds = +2 min
    expect(screen.getByText(/\+2\s*min/i)).toBeInTheDocument();
  });

  it("does not show delay when delay is null", () => {
    render(<DepartureRow departure={departures[0]} />);

    expect(screen.queryByText(/min/i)).not.toBeInTheDocument();
  });

  it("shows on-time indicator when delay is 0", () => {
    render(<DepartureRow departure={departures[3]} />);

    expect(screen.getByText(/on time/i)).toBeInTheDocument();
  });
});

import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { StopList } from "@/app/components/StopList";
import { nearbyStops } from "@/app/__tests__/fixtures/nearby-stops";

describe("StopList", () => {
  const onSelectStop = vi.fn();

  it("renders a row for each stop", () => {
    render(<StopList stops={nearbyStops} onSelectStop={onSelectStop} />);

    expect(screen.getByText("Central Station")).toBeInTheDocument();
    expect(screen.getByText("Market Square")).toBeInTheDocument();
    expect(screen.getByText("Park Avenue")).toBeInTheDocument();
  });

  it("renders stops sorted by distance", () => {
    render(<StopList stops={nearbyStops} onSelectStop={onSelectStop} />);

    const buttons = screen.getAllByRole("button");
    expect(buttons).toHaveLength(3);
  });

  it("calls onSelectStop when a stop is tapped", async () => {
    const user = userEvent.setup();
    render(<StopList stops={nearbyStops} onSelectStop={onSelectStop} />);

    await user.click(screen.getByText("Central Station"));

    expect(onSelectStop).toHaveBeenCalledWith(nearbyStops[0]);
  });

  it("renders empty state when no stops provided", () => {
    render(<StopList stops={[]} onSelectStop={onSelectStop} />);

    expect(screen.getByText(/no stops/i)).toBeInTheDocument();
  });
});

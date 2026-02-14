import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { StopRow } from "@/app/components/StopRow";
import { nearbyStops } from "@/app/__tests__/fixtures/nearby-stops";

describe("StopRow", () => {
  const stop = nearbyStops[0];
  const onTap = vi.fn();

  it("renders the transport icon", () => {
    render(<StopRow stop={stop} onTap={onTap} />);

    expect(screen.getByTestId("transport-icon-subway")).toBeInTheDocument();
  });

  it("displays the transport type name", () => {
    render(<StopRow stop={stop} onTap={onTap} />);

    expect(screen.getByText("Subway")).toBeInTheDocument();
  });

  it("displays the first line with direction", () => {
    render(<StopRow stop={stop} onTap={onTap} />);

    expect(screen.getByText(/U2/)).toBeInTheDocument();
    expect(screen.getByText(/Pankow/)).toBeInTheDocument();
  });

  it("renders a chevron indicator", () => {
    render(<StopRow stop={stop} onTap={onTap} />);

    expect(screen.getByLabelText(/view departures/i)).toBeInTheDocument();
  });

  it("calls onTap with stop when clicked", async () => {
    const user = userEvent.setup();
    render(<StopRow stop={stop} onTap={onTap} />);

    await user.click(screen.getByRole("button"));

    expect(onTap).toHaveBeenCalledWith(stop);
  });

  it("has 64px row height", () => {
    render(<StopRow stop={stop} onTap={onTap} />);

    const button = screen.getByRole("button");
    expect(button).toHaveStyle({ height: "64px" });
  });

  it("has bottom border divider", () => {
    render(<StopRow stop={stop} onTap={onTap} />);

    const button = screen.getByRole("button");
    const style = button.getAttribute("style") || "";
    expect(style).toContain("border-bottom");
  });
});

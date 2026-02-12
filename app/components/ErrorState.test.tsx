import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { ErrorState } from "@/app/components/ErrorState";

describe("ErrorState", () => {
  it("renders permission denied error", () => {
    render(<ErrorState type="permission" onRetry={vi.fn()} />);

    expect(screen.getByText(/location permission/i)).toBeInTheDocument();
  });

  it("renders network error", () => {
    render(<ErrorState type="network" onRetry={vi.fn()} />);

    expect(screen.getByText(/couldn't load/i)).toBeInTheDocument();
  });

  it("renders timeout error", () => {
    render(<ErrorState type="timeout" onRetry={vi.fn()} />);

    expect(screen.getByText(/taking too long/i)).toBeInTheDocument();
  });

  it("renders empty state", () => {
    render(<ErrorState type="empty" onRetry={vi.fn()} />);

    expect(screen.getByText(/no public transit/i)).toBeInTheDocument();
  });

  it("renders offline error", () => {
    render(<ErrorState type="offline" onRetry={vi.fn()} />);

    expect(screen.getByText(/appear to be offline/i)).toBeInTheDocument();
  });

  it("calls onRetry when retry button is tapped", async () => {
    const user = userEvent.setup();
    const onRetry = vi.fn();
    render(<ErrorState type="network" onRetry={onRetry} />);

    await user.click(screen.getByRole("button", { name: /retry/i }));

    expect(onRetry).toHaveBeenCalledTimes(1);
  });

  it("does not show retry button for empty state", () => {
    render(<ErrorState type="empty" onRetry={vi.fn()} />);

    expect(screen.queryByRole("button", { name: /retry/i })).not.toBeInTheDocument();
  });
});

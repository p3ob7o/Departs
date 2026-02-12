import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { LoadingState } from "@/app/components/LoadingState";

describe("LoadingState", () => {
  it("renders a loading spinner", () => {
    render(<LoadingState />);

    expect(screen.getByRole("status")).toBeInTheDocument();
  });

  it("displays loading text", () => {
    render(<LoadingState />);

    expect(screen.getByText(/finding nearby stops/i)).toBeInTheDocument();
  });

  it("has an accessible label for screen readers", () => {
    render(<LoadingState />);

    const status = screen.getByRole("status");
    expect(status).toHaveAccessibleName();
  });

  it("renders with custom message when provided", () => {
    render(<LoadingState message="Loading departures..." />);

    expect(screen.getByText("Loading departures...")).toBeInTheDocument();
  });
});

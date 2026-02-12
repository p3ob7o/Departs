import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { TransportIcon } from "@/app/components/TransportIcon";

describe("TransportIcon", () => {
  it("renders subway icon", () => {
    render(<TransportIcon type="subway" />);

    expect(screen.getByTestId("transport-icon-subway")).toBeInTheDocument();
  });

  it("renders tram icon", () => {
    render(<TransportIcon type="tram" />);

    expect(screen.getByTestId("transport-icon-tram")).toBeInTheDocument();
  });

  it("renders bus icon", () => {
    render(<TransportIcon type="bus" />);

    expect(screen.getByTestId("transport-icon-bus")).toBeInTheDocument();
  });

  it("renders rail icon", () => {
    render(<TransportIcon type="rail" />);

    expect(screen.getByTestId("transport-icon-rail")).toBeInTheDocument();
  });

  it("has 40x40px dimensions", () => {
    render(<TransportIcon type="subway" />);

    const icon = screen.getByTestId("transport-icon-subway");
    expect(icon).toHaveClass("w-10", "h-10");
  });

  it("includes accessible label", () => {
    render(<TransportIcon type="bus" />);

    expect(screen.getByLabelText(/bus/i)).toBeInTheDocument();
  });
});

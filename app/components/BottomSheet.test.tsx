import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { BottomSheet } from "@/app/components/BottomSheet";

describe("BottomSheet", () => {
  it("renders children content", () => {
    render(
      <BottomSheet>
        <div data-testid="child">Content</div>
      </BottomSheet>
    );

    expect(screen.getByTestId("child")).toBeInTheDocument();
  });

  it("renders a drag handle", () => {
    render(<BottomSheet><div /></BottomSheet>);

    expect(screen.getByTestId("drag-handle")).toBeInTheDocument();
  });

  it("has rounded top corners", () => {
    render(<BottomSheet><div /></BottomSheet>);

    const sheet = screen.getByTestId("bottom-sheet");
    expect(sheet).toHaveClass("rounded-t-2xl");
  });

  it("has horizontal padding", () => {
    render(<BottomSheet><div /></BottomSheet>);

    const sheet = screen.getByTestId("bottom-sheet");
    expect(sheet).toHaveClass("px-4");
  });

  it("is scrollable", () => {
    render(<BottomSheet><div /></BottomSheet>);

    const sheet = screen.getByTestId("bottom-sheet");
    expect(sheet).toHaveClass("overflow-y-auto");
  });

  it("accounts for safe area inset", () => {
    render(<BottomSheet><div /></BottomSheet>);

    const sheet = screen.getByTestId("bottom-sheet");
    expect(sheet).toHaveStyle({
      paddingBottom: "env(safe-area-inset-bottom)",
    });
  });
});

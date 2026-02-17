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

  it("sits flush against the map (no rounded corners or drag handle)", () => {
    render(<BottomSheet><div /></BottomSheet>);

    const sheet = screen.getByTestId("bottom-sheet");
    expect(sheet).not.toHaveClass("rounded-t-2xl");
    expect(screen.queryByTestId("drag-handle")).not.toBeInTheDocument();
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

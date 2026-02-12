import React from "react";
import { vi } from "vitest";

export const Map = vi.fn(({ children, ...props }: Record<string, unknown>) =>
  React.createElement(
    "div",
    { "data-testid": "map", ...props },
    children as React.ReactNode
  )
);

export const Marker = vi.fn((props: Record<string, unknown>) =>
  React.createElement("div", {
    "data-testid": "marker",
    "data-longitude": props.longitude,
    "data-latitude": props.latitude,
  })
);

export const Source = vi.fn(
  ({ children, ...props }: Record<string, unknown>) =>
    React.createElement(
      "div",
      { "data-testid": "source", ...props },
      children as React.ReactNode
    )
);

export const Layer = vi.fn((props: Record<string, unknown>) =>
  React.createElement("div", { "data-testid": "layer", ...props })
);

export default Map;

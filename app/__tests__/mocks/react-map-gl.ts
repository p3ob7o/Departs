import React from "react";
import { vi } from "vitest";

export const Map = React.forwardRef(function MockMap(
  { children, ...props }: Record<string, unknown>,
  ref: React.Ref<unknown>
) {
  React.useImperativeHandle(ref, () => ({
    fitBounds: vi.fn(),
    flyTo: vi.fn(),
    getMap: vi.fn(),
  }));
  return React.createElement(
    "div",
    { "data-testid": "map", ...props },
    children as React.ReactNode
  );
});

export const Marker = ({ children, ...props }: Record<string, unknown>) =>
  React.createElement(
    "div",
    {
      "data-testid": "marker",
      "data-longitude": props.longitude,
      "data-latitude": props.latitude,
    },
    children as React.ReactNode
  );

export const Source = ({ children, ...props }: Record<string, unknown>) =>
  React.createElement(
    "div",
    { "data-testid": "source", ...props },
    children as React.ReactNode
  );

export const Layer = (props: Record<string, unknown>) =>
  React.createElement("div", { "data-testid": "layer", ...props });

export default Map;

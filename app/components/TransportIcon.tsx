import type { TransportType } from "@/app/types";

const iconLabels: Record<TransportType, string> = {
  subway: "M",
  tram: "T",
  bus: "B",
  rail: "R",
};

const typeNames: Record<TransportType, string> = {
  subway: "Subway",
  tram: "Tram",
  bus: "Bus",
  rail: "Rail",
};

export const STOP_PALETTE = [
  "#7BA3C9", // powder blue
  "#C9887B", // terra cotta
  "#82B882", // soft green
  "#9B82C9", // soft purple
  "#7BC9BD", // teal
  "#C97B95", // soft rose
  "#B8A87B", // sand
  "#7B95C9", // periwinkle
  "#C9B27B", // gold
  "#82C9A3", // mint
];

export function getStopColor(index: number): string {
  return STOP_PALETTE[index % STOP_PALETTE.length];
}

export function getTransportName(type: TransportType): string {
  return typeNames[type];
}

export function TransportIcon({
  type,
  color,
}: {
  type: TransportType;
  color?: string;
}) {
  return (
    <div
      data-testid={`transport-icon-${type}`}
      className="w-10 h-10 flex items-center justify-center rounded-full text-sm font-bold"
      style={{
        backgroundColor: color ?? "#8E8E93",
        color: "#FFFFFF",
      }}
      aria-label={type}
    >
      {iconLabels[type]}
    </div>
  );
}

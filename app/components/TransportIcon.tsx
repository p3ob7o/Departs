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

export function getTransportName(type: TransportType): string {
  return typeNames[type];
}

export function TransportIcon({ type }: { type: TransportType }) {
  return (
    <div
      data-testid={`transport-icon-${type}`}
      className="w-10 h-10 flex items-center justify-center rounded-full text-sm font-bold"
      style={{
        backgroundColor: "#3A3A3C",
        color: "#FFFFFF",
      }}
      aria-label={type}
    >
      {iconLabels[type]}
    </div>
  );
}

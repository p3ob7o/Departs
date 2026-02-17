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

const transportColorVars: Record<TransportType, string> = {
  subway: "var(--color-transport-subway)",
  tram: "var(--color-transport-tram)",
  bus: "var(--color-transport-bus)",
  rail: "var(--color-transport-rail)",
};

export function getTransportColor(type: TransportType): string {
  return transportColorVars[type];
}

export function getTransportName(type: TransportType): string {
  return typeNames[type];
}

export function TransportIcon({ type }: { type: TransportType }) {
  return (
    <div
      data-testid={`transport-icon-${type}`}
      className="w-10 h-10 flex items-center justify-center rounded-full text-sm font-bold"
      style={{
        backgroundColor: getTransportColor(type),
        color: "#FFFFFF",
      }}
      aria-label={type}
    >
      {iconLabels[type]}
    </div>
  );
}

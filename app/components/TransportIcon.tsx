import type { TransportType } from "@/app/types";

const iconLabels: Record<TransportType, string> = {
  subway: "M",
  tram: "T",
  bus: "B",
  rail: "R",
};

export function TransportIcon({ type }: { type: TransportType }) {
  return (
    <div
      data-testid={`transport-icon-${type}`}
      className="w-10 h-10 flex items-center justify-center rounded-full bg-zinc-200 text-sm font-bold"
      aria-label={type}
    >
      {iconLabels[type]}
    </div>
  );
}

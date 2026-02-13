import type { TransportType } from "@/app/types";

const iconByType: Record<TransportType, string> = {
  subway: "M",
  tram: "T",
  bus: "B",
  rail: "R",
};

export function TransportIcon(props: { type: TransportType }) {
  return (
    <div
      data-testid={`transport-icon-${props.type}`}
      aria-label={`${props.type} icon`}
      className="w-10 h-10 rounded-full bg-zinc-900 text-white flex items-center justify-center font-semibold"
    >
      {iconByType[props.type]}
    </div>
  );
}

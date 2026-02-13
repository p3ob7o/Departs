import type { NearbyStop } from "@/app/types";
import { TransportIcon } from "./TransportIcon";

export function StopRow({
  stop,
  onTap,
}: {
  stop: NearbyStop;
  onTap: (stop: NearbyStop) => void;
}) {
  const firstLine = stop.lines[0];

  return (
    <button
      className="min-h-[44px] w-full flex items-center gap-3 px-2 py-2 text-left"
      onClick={() => onTap(stop)}
    >
      <TransportIcon type={stop.type} />
      <div className="flex-1 min-w-0">
        <div className="font-medium">{stop.name}</div>
        {firstLine && (
          <div className="text-sm text-zinc-500">
            {firstLine.name} → {firstLine.direction}
          </div>
        )}
      </div>
      <span className="text-sm text-zinc-400">{stop.distance} m</span>
      <span aria-label="View departures" className="text-zinc-400">
        ›
      </span>
    </button>
  );
}

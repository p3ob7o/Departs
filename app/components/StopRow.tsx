import type { NearbyStop } from "@/app/types";
import { TransportIcon } from "@/app/components/TransportIcon";

export function StopRow(props: {
  stop: NearbyStop;
  onTap: (stop: NearbyStop) => void;
}) {
  const firstLine = props.stop.lines[0];

  return (
    <button
      type="button"
      onClick={() => props.onTap(props.stop)}
      className="w-full min-h-[44px] flex items-center gap-3 py-3 border-b border-zinc-200 dark:border-zinc-800 text-left"
    >
      <TransportIcon type={props.stop.type} />
      <div className="flex-1">
        <p className="font-semibold">{props.stop.name}</p>
        <p className="text-sm text-zinc-600 dark:text-zinc-300">
          {firstLine ? `${firstLine.name} to ${firstLine.direction}` : "No line info"}
        </p>
        <p className="text-xs text-zinc-500">{props.stop.distance} m</p>
      </div>
      <span aria-label="View departures" className="text-zinc-400 text-xl leading-none">
        ›
      </span>
    </button>
  );
}

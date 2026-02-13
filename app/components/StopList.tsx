import type { NearbyStop } from "@/app/types";
import { StopRow } from "@/app/components/StopRow";

export function StopList(props: {
  stops: NearbyStop[];
  onSelectStop: (stop: NearbyStop) => void;
}) {
  if (props.stops.length === 0) {
    return <p className="py-6 text-sm text-zinc-600 dark:text-zinc-300">No stops nearby</p>;
  }

  const sortedStops = [...props.stops].sort((a, b) => a.distance - b.distance);

  return (
    <div>
      {sortedStops.map((stop) => (
        <StopRow key={stop.id} stop={stop} onTap={props.onSelectStop} />
      ))}
    </div>
  );
}

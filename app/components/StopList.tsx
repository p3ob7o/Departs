import type { NearbyStop } from "@/app/types";
import { StopRow } from "./StopRow";

export function StopList({
  stops,
  onSelectStop,
}: {
  stops: NearbyStop[];
  onSelectStop: (stop: NearbyStop) => void;
}) {
  if (stops.length === 0) {
    return <p>No stops nearby</p>;
  }

  return (
    <div>
      {stops.map((stop) => (
        <StopRow key={stop.id} stop={stop} onTap={onSelectStop} />
      ))}
    </div>
  );
}

import type { NearbyStop, Departure, WalkingRoute } from "@/app/types";
import { DepartureRow } from "./DepartureRow";

export function DepartureDetail({
  stop,
  departures,
  walkingRoute,
  onBack,
}: {
  stop: NearbyStop;
  departures: Departure[];
  walkingRoute: WalkingRoute | null;
  onBack: () => void;
}) {
  const firstLine = stop.lines[0];

  return (
    <div>
      <button aria-label="Back" onClick={onBack} className="mb-2">
        ← Back
      </button>
      <h2 className="text-lg font-semibold">{stop.name}</h2>
      {firstLine && (
        <p className="text-sm text-zinc-500">
          {firstLine.name} → {firstLine.direction}
        </p>
      )}
      {walkingRoute && (
        <p className="text-sm text-zinc-500">
          {Math.round(walkingRoute.duration / 60)} min walk
        </p>
      )}
      <div className="mt-3">
        {departures.map((dep, i) => (
          <DepartureRow key={i} departure={dep} />
        ))}
      </div>
    </div>
  );
}

import type { NearbyStop, Departure, WalkingRoute } from "@/app/types";
import { DepartureRow } from "@/app/components/DepartureRow";

function formatWalkDuration(seconds: number): string {
  return `${Math.max(1, Math.round(seconds / 60))} min walk`;
}

export function DepartureDetail(props: {
  stop: NearbyStop;
  departures: Departure[];
  walkingRoute: WalkingRoute | null;
  onBack: () => void;
}) {
  const primaryLine = props.stop.lines[0];

  return (
    <div>
      <button
        type="button"
        onClick={props.onBack}
        className="mb-3 text-sm font-medium text-blue-600 dark:text-blue-400"
      >
        Back
      </button>

      <h2 className="text-xl font-bold">{props.stop.name}</h2>
      {primaryLine ? (
        <p className="mb-2 text-sm text-zinc-600 dark:text-zinc-300">
          {primaryLine.name} to {primaryLine.direction}
        </p>
      ) : null}

      {props.walkingRoute ? (
        <p className="mb-3 text-sm text-zinc-600 dark:text-zinc-300">
          {formatWalkDuration(props.walkingRoute.duration)}
        </p>
      ) : null}

      <div>
        {props.departures.map((departure) => (
          <DepartureRow key={`${props.stop.id}-${departure.time}`} departure={departure} />
        ))}
      </div>
    </div>
  );
}

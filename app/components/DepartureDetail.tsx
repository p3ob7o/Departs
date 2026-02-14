import type { NearbyStop, Departure, WalkingRoute } from "@/app/types";
import { DepartureRow } from "./DepartureRow";
import { getTransportName } from "./TransportIcon";

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
      <button
        aria-label="Back"
        onClick={onBack}
        className="mb-4"
        style={{ fontSize: "24px", color: "var(--color-text-primary)" }}
      >
        ←
      </button>
      <h2
        className="font-bold"
        style={{
          fontSize: "22px",
          lineHeight: "28px",
          color: "var(--color-text-primary)",
        }}
      >
        Departures:
      </h2>
      {firstLine && (
        <p
          style={{
            fontSize: "15px",
            lineHeight: "20px",
            color: "var(--color-text-secondary)",
            marginTop: "8px",
          }}
        >
          {getTransportName(stop.type)} {firstLine.name} to {firstLine.direction}
        </p>
      )}
      {walkingRoute && (
        <p
          style={{
            fontSize: "15px",
            lineHeight: "20px",
            color: "var(--color-text-secondary)",
            marginTop: "4px",
          }}
        >
          {Math.round(walkingRoute.duration / 60)} min walk
        </p>
      )}
      <div style={{ marginTop: "20px" }}>
        {departures.map((dep, i) => (
          <DepartureRow key={i} departure={dep} />
        ))}
      </div>
    </div>
  );
}

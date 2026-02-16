import type { NearbyStop, Departure, WalkingRoute } from "@/app/types";
import { DepartureRow } from "./DepartureRow";
import { getTransportName } from "./TransportIcon";

export function DepartureDetail({
  stop,
  departures,
  walkingRoute,
  loading,
  error,
  onBack,
}: {
  stop: NearbyStop;
  departures: Departure[];
  walkingRoute: WalkingRoute | null;
  loading: boolean;
  error: string | null;
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
        {loading ? (
          <div
            role="status"
            aria-label="Loading departures"
            className="flex items-center justify-center"
            style={{ padding: "24px 0" }}
          >
            <div
              className="animate-spin h-6 w-6 border-3 rounded-full"
              style={{
                borderColor: "var(--color-bg-tertiary)",
                borderTopColor: "var(--color-accent)",
              }}
            />
            <span
              style={{
                marginLeft: "12px",
                fontSize: "15px",
                color: "var(--color-text-secondary)",
              }}
            >
              Loading departures…
            </span>
          </div>
        ) : error ? (
          <p
            style={{
              fontSize: "15px",
              lineHeight: "20px",
              color: "var(--color-text-secondary)",
              padding: "24px 0",
              textAlign: "center",
            }}
          >
            Couldn't load departure times.
          </p>
        ) : departures.length === 0 ? (
          <p
            style={{
              fontSize: "15px",
              lineHeight: "20px",
              color: "var(--color-text-secondary)",
              padding: "24px 0",
              textAlign: "center",
            }}
          >
            No upcoming departures found.
          </p>
        ) : (
          departures.map((dep, i) => (
            <DepartureRow key={i} departure={dep} />
          ))
        )}
      </div>
    </div>
  );
}

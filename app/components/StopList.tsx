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
    return (
      <div
        className="flex flex-col items-center text-center"
        style={{ padding: "32px 16px", color: "var(--color-text-secondary)" }}
      >
        <p
          className="font-semibold"
          style={{ fontSize: "17px", color: "var(--color-text-primary)", marginBottom: "8px" }}
        >
          No public transit stops nearby
        </p>
        <p style={{ fontSize: "15px" }}>
          We couldn&apos;t find any stops nearby. Try moving to a different area.
        </p>
      </div>
    );
  }

  return (
    <div>
      {stops.map((stop) => (
        <StopRow key={stop.id} stop={stop} onTap={onSelectStop} />
      ))}
    </div>
  );
}

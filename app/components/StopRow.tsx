import type { NearbyStop } from "@/app/types";
import { TransportIcon, getTransportName } from "./TransportIcon";

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
      className="w-full flex items-center gap-3 px-3 text-left"
      style={{
        height: "64px",
        borderBottom: "1px solid var(--color-bg-tertiary)",
        marginLeft: "0px",
        paddingLeft: "0px",
      }}
      onClick={() => onTap(stop)}
    >
      <TransportIcon type={stop.type} />
      <div
        className="flex-1 min-w-0"
        style={{
          borderBottom: "none",
        }}
      >
        <div
          className="font-semibold"
          style={{ fontSize: "17px", lineHeight: "22px", color: "var(--color-text-primary)" }}
        >
          {getTransportName(stop.type)}
        </div>
        {firstLine && (
          <div
            style={{ fontSize: "15px", lineHeight: "20px", color: "var(--color-text-secondary)" }}
          >
            {firstLine.name} to {firstLine.direction}
          </div>
        )}
      </div>
      <span
        style={{ fontSize: "16px", color: "var(--color-text-tertiary)" }}
        aria-label="View departures"
      >
        ›
      </span>
    </button>
  );
}

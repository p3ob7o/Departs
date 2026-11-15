import type { LineInfo, NearbyStop } from "@/app/types";
import { TransportIcon, getTransportName } from "./TransportIcon";

export function StopRow({
  stop,
  line = stop.lines[0],
  color,
  onTap,
}: {
  stop: NearbyStop;
  line?: LineInfo;
  color?: string;
  onTap: (stop: NearbyStop, line: LineInfo) => void;
}) {
  const firstLine = line;

  return (
    <button
      className="w-full flex items-center gap-3 px-3 text-left"
      style={{
        minHeight: "88px",
        paddingTop: "8px",
        paddingBottom: "8px",
        borderBottom: "1px solid var(--color-bg-tertiary)",
        marginLeft: "0px",
        paddingLeft: "0px",
      }}
      onClick={() => firstLine && onTap(stop, firstLine)}
    >
      <TransportIcon type={firstLine?.type ?? stop.type} color={color} />
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
          {getTransportName(firstLine?.type ?? stop.type)}
        </div>
        <div style={{ fontSize: "15px", color: "var(--color-text-secondary)" }}>{stop.name}</div>
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

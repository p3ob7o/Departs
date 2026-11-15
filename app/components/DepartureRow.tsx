import type { Departure } from "@/app/types";

export function formatDepartureTime(isoTime: string, locale?: string): string {
  // HERE timestamps carry the station's offset. Format that wall clock, even
  // when the device timezone differs, while respecting its 12/24-hour locale.
  const stationClock = new Date(isoTime.replace(/(?:Z|[+-]\d{2}:\d{2})$/, "Z"));
  return stationClock.toLocaleTimeString(locale, { hour: "numeric", minute: "2-digit", timeZone: "UTC" });
}

function ClockIcon() {
  return (
    <svg
      width="20"
      height="20"
      viewBox="0 0 20 20"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      style={{ color: "var(--color-text-secondary)", flexShrink: 0 }}
    >
      <circle cx="10" cy="10" r="8.5" stroke="currentColor" strokeWidth="1.5" />
      <path d="M10 5.5V10L13 12.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export function DepartureRow({ departure }: { departure: Departure }) {
  const { time, realTime, delay } = departure;

  return (
    <div
      className="flex items-center"
      style={{
        height: "52px",
        borderBottom: "1px solid var(--color-bg-tertiary)",
      }}
    >
      <time
        role="time"
        dateTime={time}
        className="flex-1"
        style={{
          fontSize: "17px",
          lineHeight: "22px",
          color: "var(--color-text-primary)",
        }}
      >
        {formatDepartureTime(time)}
      </time>
      {realTime && (
        <span data-testid="realtime-indicator" className="w-2 h-2 rounded-full bg-green-500 mr-2" />
      )}
      {delay !== null && delay > 0 && (
        <span className="text-red-500 mr-3 text-sm">+{Math.round(delay / 60)} min</span>
      )}
      {delay === 0 && <span className="text-green-600 mr-3 text-sm">On time</span>}
      <ClockIcon />
    </div>
  );
}

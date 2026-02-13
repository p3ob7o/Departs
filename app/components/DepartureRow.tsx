import type { Departure } from "@/app/types";

function formatTime(iso: string): string {
  const match = iso.match(/T(\d{2}:\d{2})/);
  return match ? match[1] : iso;
}

function formatDelay(delaySeconds: number): string {
  const minutes = Math.round(delaySeconds / 60);
  return `+${minutes} min`;
}

export function DepartureRow(props: { departure: Departure }) {
  const { departure } = props;

  return (
    <div className="flex items-center justify-between py-3 border-b border-zinc-200 dark:border-zinc-800">
      <div className="flex items-center gap-2">
        <time role="time" dateTime={departure.time} className="text-lg">
          {formatTime(departure.time)}
        </time>
        {departure.realTime ? (
          <span
            data-testid="realtime-indicator"
            className="rounded bg-green-600 px-1.5 py-0.5 text-xs text-white"
          >
            RT
          </span>
        ) : null}
      </div>
      <div className="text-sm text-zinc-600 dark:text-zinc-300">
        {departure.delay === null ? null : departure.delay === 0 ? "On time" : formatDelay(departure.delay)}
      </div>
    </div>
  );
}

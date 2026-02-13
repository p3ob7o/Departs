import type { Departure } from "@/app/types";

function formatTime(isoTime: string): string {
  const date = new Date(isoTime);
  const hours = date.getHours().toString().padStart(2, "0");
  const minutes = date.getMinutes().toString().padStart(2, "0");
  return `${hours}:${minutes}`;
}

export function DepartureRow({ departure }: { departure: Departure }) {
  const { time, realTime, delay } = departure;

  return (
    <div className="flex items-center gap-3 py-2">
      <time role="time" dateTime={time}>
        {formatTime(time)}
      </time>
      {realTime && <span data-testid="realtime-indicator" className="w-2 h-2 rounded-full bg-green-500" />}
      {delay !== null && delay > 0 && (
        <span className="text-red-500">+{Math.round(delay / 60)} min</span>
      )}
      {delay === 0 && <span className="text-green-600">On time</span>}
    </div>
  );
}

import type { NearbyStop, Departure, LineInfo, WalkingRoute } from "@/app/types";
import { transformStations, transformDepartures } from "./transitProvider";

export async function fetchNearbyStops(
  lat: number,
  lon: number,
  signal?: AbortSignal
): Promise<NearbyStop[]> {
  if (isNaN(lat) || isNaN(lon)) throw new Error("Invalid coordinates");
  const res = await fetch(`/api/stops/nearby?lat=${lat}&lon=${lon}`, { signal });
  if (!res.ok) throw new Error(`Failed to fetch nearby stops: ${res.status}`);
  return transformStations(await res.json());
}

export async function fetchDepartures(
  stopId: string,
  line?: Pick<LineInfo, "name" | "direction">,
  signal?: AbortSignal
): Promise<Departure[]> {
  const params = new URLSearchParams({ stopId });
  if (line) {
    params.set("lineName", line.name);
    params.set("direction", line.direction);
  }
  const res = await fetch(`/api/departures?${params}`, { signal });
  if (!res.ok) throw new Error(`Failed to fetch departures: ${res.status}`);
  return transformDepartures(await res.json());
}

export async function fetchDirections(
  from: { lat: number; lon: number },
  to: { lat: number; lon: number },
  signal?: AbortSignal
): Promise<WalkingRoute> {
  const res = await fetch(
    `/api/directions?from=${from.lat},${from.lon}&to=${to.lat},${to.lon}`,
    { signal }
  );
  if (!res.ok) throw new Error(`Failed to fetch directions: ${res.status}`);
  const data = await res.json();
  return {
    geometry: data.geometry,
    duration: data.duration,
    distance: data.distance,
  };
}

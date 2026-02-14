import type { NearbyStop, Departure, WalkingRoute } from "@/app/types";
import { transformStations, transformDepartures } from "./transitProvider";

export async function fetchNearbyStops(
  lat: number,
  lon: number
): Promise<NearbyStop[]> {
  if (isNaN(lat) || isNaN(lon)) throw new Error("Invalid coordinates");
  const res = await fetch(`/api/stops/nearby?lat=${lat}&lon=${lon}`);
  if (!res.ok) throw new Error(`Failed to fetch nearby stops: ${res.status}`);
  return transformStations(await res.json());
}

export async function fetchDepartures(stopId: string): Promise<Departure[]> {
  const res = await fetch(`/api/departures?stopId=${stopId}`);
  if (!res.ok) throw new Error(`Failed to fetch departures: ${res.status}`);
  return transformDepartures(await res.json());
}

export async function fetchDirections(
  from: { lat: number; lon: number },
  to: { lat: number; lon: number }
): Promise<WalkingRoute> {
  const res = await fetch(
    `/api/directions?from=${from.lat},${from.lon}&to=${to.lat},${to.lon}`
  );
  if (!res.ok) throw new Error(`Failed to fetch directions: ${res.status}`);
  const data = await res.json();
  return {
    geometry: data.geometry,
    duration: data.duration,
    distance: data.distance,
  };
}

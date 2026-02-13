import type { NearbyStop, Departure, WalkingRoute } from "@/app/types";
import { transformDepartures, transformStations } from "@/app/lib/transitProvider";

type MapboxDirectionsResponse = {
  routes?: Array<{
    geometry?: GeoJSON.LineString;
    duration?: number;
    distance?: number;
  }>;
};

function isWalkingRoute(value: unknown): value is WalkingRoute {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const maybe = value as Partial<WalkingRoute>;

  return (
    typeof maybe.duration === "number" &&
    typeof maybe.distance === "number" &&
    typeof maybe.geometry === "object" &&
    maybe.geometry !== null
  );
}

async function fetchJson(url: string): Promise<unknown> {
  const response = await fetch(url);

  if (!response.ok) {
    throw new Error(`Request failed: ${response.status}`);
  }

  return response.json();
}

export async function fetchNearbyStops(
  lat: number,
  lon: number
): Promise<NearbyStop[]> {
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
    throw new Error("Invalid coordinates");
  }

  const data = await fetchJson(`/api/stops/nearby?lat=${lat}&lon=${lon}`);

  if (Array.isArray(data)) {
    return data as NearbyStop[];
  }

  return transformStations(data as Parameters<typeof transformStations>[0]);
}

export async function fetchDepartures(stopId: string): Promise<Departure[]> {
  if (!stopId) {
    throw new Error("Missing stopId");
  }

  const data = await fetchJson(`/api/departures?stopId=${encodeURIComponent(stopId)}`);

  if (Array.isArray(data)) {
    return data as Departure[];
  }

  return transformDepartures(data as Parameters<typeof transformDepartures>[0]);
}

export async function fetchDirections(
  from: { lat: number; lon: number },
  to: { lat: number; lon: number }
): Promise<WalkingRoute> {
  if (
    !Number.isFinite(from.lat) ||
    !Number.isFinite(from.lon) ||
    !Number.isFinite(to.lat) ||
    !Number.isFinite(to.lon)
  ) {
    throw new Error("Invalid coordinates");
  }

  const data = await fetchJson(
    `/api/directions?from=${from.lat},${from.lon}&to=${to.lat},${to.lon}`
  );

  if (isWalkingRoute(data)) {
    return data;
  }

  const route = (data as MapboxDirectionsResponse).routes?.[0];

  if (!route?.geometry) {
    throw new Error("Invalid directions response");
  }

  return {
    geometry: route.geometry,
    duration: Number(route.duration ?? 0),
    distance: Number(route.distance ?? 0),
  };
}

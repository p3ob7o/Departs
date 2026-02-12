// TODO: Implement client-side API fetch helpers
import type { NearbyStop, Departure, WalkingRoute } from "@/app/types";

export async function fetchNearbyStops(
  _lat: number,
  _lon: number
): Promise<NearbyStop[]> {
  throw new Error("Not implemented");
}

export async function fetchDepartures(_stopId: string): Promise<Departure[]> {
  throw new Error("Not implemented");
}

export async function fetchDirections(
  _from: { lat: number; lon: number },
  _to: { lat: number; lon: number }
): Promise<WalkingRoute> {
  throw new Error("Not implemented");
}

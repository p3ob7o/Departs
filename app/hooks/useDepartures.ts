// TODO: Implement departures hook
import type { Departure, WalkingRoute } from "@/app/types";

export function useDepartures(
  _stopId: string | null,
  _userCoords: { lat: number; lon: number },
  _stopLocation: { lat: number; lon: number }
) {
  return {
    loading: false,
    departures: [] as Departure[],
    walkingRoute: null as WalkingRoute | null,
    error: null as string | null,
  };
}

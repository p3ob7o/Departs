// TODO: Implement nearby stops hook
import type { NearbyStop } from "@/app/types";

export function useNearbyStops(
  _coords: { lat: number; lon: number } | null
) {
  return {
    loading: false,
    stops: [] as NearbyStop[],
    error: null as string | null,
  };
}

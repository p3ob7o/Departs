import { useEffect, useState } from "react";
import type { Departure, WalkingRoute } from "@/app/types";
import { fetchDepartures, fetchDirections } from "@/app/lib/api";

export function useDepartures(
  stopId: string | null,
  userCoords: { lat: number; lon: number },
  stopLocation: { lat: number; lon: number }
) {
  const [loading, setLoading] = useState(Boolean(stopId));
  const [departures, setDepartures] = useState<Departure[]>([]);
  const [walkingRoute, setWalkingRoute] = useState<WalkingRoute | null>(null);
  const [error, setError] = useState<string | null>(null);
  const userLat = userCoords.lat;
  const userLon = userCoords.lon;
  const stopLat = stopLocation.lat;
  const stopLon = stopLocation.lon;

  useEffect(() => {
    let cancelled = false;
    let timerId: ReturnType<typeof setTimeout> | null = null;

    if (!stopId) {
      setLoading(false);
      setDepartures([]);
      setWalkingRoute(null);
      setError(null);
      return;
    }

    async function loadDepartureData() {
      setLoading(true);
      setError(null);

      try {
        const [nextDepartures, nextRoute] = await Promise.all([
          fetchDepartures(stopId),
          fetchDirections(
            { lat: userLat, lon: userLon },
            { lat: stopLat, lon: stopLon }
          ).catch(() => null),
        ]);

        if (!cancelled) {
          setDepartures(nextDepartures);
          setWalkingRoute(nextRoute);
        }
      } catch {
        if (!cancelled) {
          setDepartures([]);
          setWalkingRoute(null);
          setError("network");
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    timerId = setTimeout(() => {
      void loadDepartureData();
    }, 0);

    return () => {
      cancelled = true;
      if (timerId) {
        clearTimeout(timerId);
      }
    };
  }, [stopId, userLat, userLon, stopLat, stopLon]);

  return {
    loading,
    departures,
    walkingRoute,
    error,
  };
}

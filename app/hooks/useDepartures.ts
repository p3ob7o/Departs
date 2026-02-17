import { useState, useEffect } from "react";
import type { Departure, WalkingRoute } from "@/app/types";
import { fetchDepartures, fetchDirections } from "@/app/lib/api";

export function useDepartures(
  stopId: string | null,
  userCoords: { lat: number; lon: number },
  stopLocation: { lat: number; lon: number }
) {
  const [loading, setLoading] = useState(stopId !== null);
  const [departures, setDepartures] = useState<Departure[]>([]);
  const [walkingRoute, setWalkingRoute] = useState<WalkingRoute | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!stopId) {
      setDepartures([]);
      setWalkingRoute(null);
      setError(null);
      setLoading(false);
      return;
    }

    let cancelled = false;
    setLoading(true);
    setError(null);
    setDepartures([]);
    setWalkingRoute(null);

    Promise.allSettled([
      fetchDepartures(stopId),
      fetchDirections(userCoords, stopLocation),
    ]).then(([depResult, dirResult]) => {
      if (cancelled) return;

      if (depResult.status === "fulfilled") {
        setDepartures(depResult.value);
      } else {
        setError("network");
      }

      if (dirResult.status === "fulfilled") {
        setWalkingRoute(dirResult.value);
      }

      setLoading(false);
    });

    return () => {
      cancelled = true;
    };
  }, [stopId]);

  return { loading, departures, walkingRoute, error };
}

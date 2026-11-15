import { useState, useEffect, useCallback } from "react";
import type { NearbyStop } from "@/app/types";
import { fetchNearbyStops } from "@/app/lib/api";

export function useNearbyStops(coords: { lat: number; lon: number } | null) {
  const [attempt, setAttempt] = useState(0);
  const retry = useCallback(() => setAttempt((value) => value + 1), []);
  const lat = coords?.lat;
  const lon = coords?.lon;
  const key = JSON.stringify([lat, lon, attempt]);
  const [result, setResult] = useState<{ key: string; stops: NearbyStop[]; error: string | null }>();

  useEffect(() => {
    if (lat === undefined || lon === undefined) return;
    const controller = new AbortController();
    void (async () => {
      try {
        const stops = await fetchNearbyStops(lat, lon, controller.signal);
        if (!controller.signal.aborted) setResult({ key, stops, error: null });
      } catch {
        if (!controller.signal.aborted) setResult({ key, stops: [], error: "network" });
      }
    })();
    return () => controller.abort();
  }, [lat, lon, key]);

  const current = coords && result?.key === key ? result : undefined;
  return { loading: !!coords && !current, stops: current?.stops ?? [], error: current?.error ?? null, retry };
}

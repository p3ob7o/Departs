import { useState, useEffect } from "react";
import type { NearbyStop } from "@/app/types";
import { fetchNearbyStops } from "@/app/lib/api";

export function useNearbyStops(
  coords: { lat: number; lon: number } | null
) {
  const [loading, setLoading] = useState(coords !== null);
  const [stops, setStops] = useState<NearbyStop[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!coords) return;

    let cancelled = false;
    setLoading(true);
    setError(null);

    (async () => {
      try {
        const result = await fetchNearbyStops(coords.lat, coords.lon);
        if (!cancelled) {
          setStops(result);
          setLoading(false);
        }
      } catch {
        if (!cancelled) {
          setError("network");
          setLoading(false);
        }
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [coords?.lat, coords?.lon]);

  return { loading, stops, error };
}

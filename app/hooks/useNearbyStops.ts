import { useEffect, useState } from "react";
import type { NearbyStop } from "@/app/types";
import { fetchNearbyStops } from "@/app/lib/api";

export function useNearbyStops(
  coords: { lat: number; lon: number } | null
) {
  const [loading, setLoading] = useState(Boolean(coords));
  const [stops, setStops] = useState<NearbyStop[]>([]);
  const [error, setError] = useState<string | null>(null);
  const lat = coords?.lat;
  const lon = coords?.lon;

  useEffect(() => {
    let cancelled = false;

    if (lat === undefined || lon === undefined) {
      setLoading(false);
      setStops([]);
      setError(null);
      return;
    }

    async function loadStops() {
      setLoading(true);
      setError(null);

      try {
        const nextStops = await fetchNearbyStops(lat, lon);
        if (!cancelled) {
          setStops(nextStops);
        }
      } catch {
        if (!cancelled) {
          setStops([]);
          setError("network");
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    void loadStops();

    return () => {
      cancelled = true;
    };
  }, [lat, lon]);

  return {
    loading,
    stops,
    error,
  };
}

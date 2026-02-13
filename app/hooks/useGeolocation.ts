import { useState, useEffect, useCallback } from "react";

type GeoError = "permission_denied" | "position_unavailable" | "timeout";

const errorMap: Record<number, GeoError> = {
  1: "permission_denied",
  2: "position_unavailable",
  3: "timeout",
};

export function useGeolocation() {
  const [loading, setLoading] = useState(true);
  const [coords, setCoords] = useState<{ lat: number; lon: number } | null>(
    null
  );
  const [error, setError] = useState<GeoError | null>(null);
  const [trigger, setTrigger] = useState(0);

  const retry = useCallback(() => {
    setLoading(true);
    setCoords(null);
    setError(null);
    setTrigger((t) => t + 1);
  }, []);

  useEffect(() => {
    navigator.geolocation.getCurrentPosition(
      (position) => {
        setCoords({
          lat: position.coords.latitude,
          lon: position.coords.longitude,
        });
        setLoading(false);
      },
      (err) => {
        setError(errorMap[err.code] ?? "position_unavailable");
        setLoading(false);
      },
      { enableHighAccuracy: true, timeout: 10000 }
    );
  }, [trigger]);

  return { loading, coords, error, retry };
}

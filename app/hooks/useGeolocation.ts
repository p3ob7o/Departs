import { useCallback, useEffect, useState } from "react";

type GeolocationErrorType =
  | "permission_denied"
  | "position_unavailable"
  | "timeout"
  | "unknown";

type Coordinates = { lat: number; lon: number };

function mapGeolocationErrorCode(code: number): GeolocationErrorType {
  switch (code) {
    case 1:
      return "permission_denied";
    case 2:
      return "position_unavailable";
    case 3:
      return "timeout";
    default:
      return "unknown";
  }
}

export function useGeolocation() {
  const [loading, setLoading] = useState(true);
  const [coords, setCoords] = useState<Coordinates | null>(null);
  const [error, setError] = useState<string | null>(null);

  const getPosition = useCallback(() => {
    if (!navigator.geolocation) {
      setLoading(false);
      setError("position_unavailable");
      return;
    }

    setLoading(true);
    setError(null);

    navigator.geolocation.getCurrentPosition(
      (position) => {
        setCoords({
          lat: position.coords.latitude,
          lon: position.coords.longitude,
        });
        setLoading(false);
      },
      (geoError) => {
        setCoords(null);
        setLoading(false);
        setError(mapGeolocationErrorCode(geoError.code));
      },
      {
        enableHighAccuracy: true,
        timeout: 10000,
        maximumAge: 60000,
      }
    );
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    getPosition();
  }, [getPosition]);

  return {
    loading,
    coords,
    error,
    retry: getPosition,
  };
}

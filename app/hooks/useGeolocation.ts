// TODO: Implement geolocation hook
export function useGeolocation() {
  return {
    loading: false,
    coords: null as { lat: number; lon: number } | null,
    error: null as string | null,
    retry: () => {},
  };
}

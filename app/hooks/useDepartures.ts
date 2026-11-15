import { useState, useEffect, useCallback } from "react";
import type { Departure, LineInfo, WalkingRoute } from "@/app/types";
import { fetchDepartures, fetchDirections } from "@/app/lib/api";

export function useDepartures(
  stopId: string | null,
  userCoords: { lat: number; lon: number },
  stopLocation: { lat: number; lon: number },
  line?: Pick<LineInfo, "name" | "direction">
) {
  const [attempt, setAttempt] = useState(0);
  const retry = useCallback(() => setAttempt((value) => value + 1), []);
  const { lat: fromLat, lon: fromLon } = userCoords;
  const { lat: toLat, lon: toLon } = stopLocation;
  const lineName = line?.name;
  const direction = line?.direction;
  const key = JSON.stringify([stopId, lineName, direction, fromLat, fromLon, toLat, toLon, attempt]);
  const [board, setBoard] = useState<{ key: string; departures: Departure[]; error: string | null }>();
  const [route, setRoute] = useState<{ key: string; value: WalkingRoute }>();

  useEffect(() => {
    if (!stopId) return;
    const controller = new AbortController();
    // These requests are independent: directions must never hold up the board.
    void (async () => {
      try {
        const departures = await fetchDepartures(
          stopId,
          lineName && direction ? { name: lineName, direction } : undefined,
          controller.signal
        );
        if (!controller.signal.aborted) setBoard({ key, departures, error: null });
      } catch {
        if (!controller.signal.aborted) setBoard({ key, departures: [], error: "network" });
      }
    })();
    void (async () => {
      try {
        const value = await fetchDirections(
          { lat: fromLat, lon: fromLon }, { lat: toLat, lon: toLon }, controller.signal
        );
        if (!controller.signal.aborted) setRoute({ key, value });
      } catch {
        // The board remains usable without a walking route.
      }
    })();
    return () => controller.abort();
  }, [stopId, lineName, direction, fromLat, fromLon, toLat, toLon, key]);

  const currentBoard = stopId && board?.key === key ? board : undefined;
  return {
    loading: !!stopId && !currentBoard,
    departures: currentBoard?.departures ?? [],
    walkingRoute: stopId && route?.key === key ? route.value : null,
    error: currentBoard?.error ?? null,
    retry,
  };
}

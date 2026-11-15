"use client";

import { useState, useMemo } from "react";
import dynamic from "next/dynamic";
import type { LineInfo, NearbyStop } from "@/app/types";
import { useGeolocation } from "@/app/hooks/useGeolocation";
import { useNearbyStops } from "@/app/hooks/useNearbyStops";
import { useDepartures } from "@/app/hooks/useDepartures";
import { LoadingState } from "@/app/components/LoadingState";
import { ErrorState } from "@/app/components/ErrorState";
import { StopList } from "@/app/components/StopList";
import { DepartureDetail } from "@/app/components/DepartureDetail";
import { BottomSheet } from "@/app/components/BottomSheet";
import { getStopColor } from "@/app/components/TransportIcon";

const MapView = dynamic(() => import("@/app/components/Map").then((module) => module.MapView), { ssr: false });

export default function Home() {
  const [selection, setSelection] = useState<{ stop: NearbyStop; line: LineInfo } | null>(null);
  const selectedStop = selection?.stop;
  const geo = useGeolocation();
  const stopsHook = useNearbyStops(geo.coords);
  const depsHook = useDepartures(
    selectedStop?.id ?? null,
    geo.coords ?? { lat: 0, lon: 0 },
    selectedStop?.location ?? { lat: 0, lon: 0 },
    selection?.line
  );

  const stopColors = useMemo(
    () => new Map(stopsHook.stops.map((s, i) => [s.id, getStopColor(i)])),
    [stopsHook.stops]
  );

  if (geo.loading || stopsHook.loading) {
    return <LoadingState />;
  }

  if (geo.error === "permission_denied") {
    return <ErrorState type="permission" onRetry={geo.retry} />;
  }

  if (geo.error || !geo.coords) {
    return <ErrorState type={geo.error === "timeout" ? "timeout" : "location"} onRetry={geo.retry} />;
  }

  if (stopsHook.error === "network") {
    return <ErrorState type="network" onRetry={stopsHook.retry} />;
  }

  const userCoords = geo.coords;

  return (
    <div className="app-layout">
      <div className="map-container" aria-label="Transit map">
        <MapView
          userCoords={userCoords}
          stops={selectedStop ? [selectedStop] : stopsHook.stops}
          stopColors={stopColors}
          walkingRoute={selectedStop ? depsHook.walkingRoute ?? undefined : undefined}
        />
      </div>
      <BottomSheet>
        {selectedStop ? (
          <DepartureDetail
            stop={selectedStop}
            line={selection?.line}
            departures={depsHook.departures}
            walkingRoute={depsHook.walkingRoute}
            loading={depsHook.loading}
            error={depsHook.error}
            onBack={() => setSelection(null)}
            onRetry={depsHook.retry}
          />
        ) : (
          <StopList stops={stopsHook.stops} stopColors={stopColors} onSelectStop={(stop, line) => setSelection({ stop, line })} />
        )}
      </BottomSheet>
    </div>
  );
}

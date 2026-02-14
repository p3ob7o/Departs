"use client";

import { useState } from "react";
import type { NearbyStop } from "@/app/types";
import { useGeolocation } from "@/app/hooks/useGeolocation";
import { useNearbyStops } from "@/app/hooks/useNearbyStops";
import { useDepartures } from "@/app/hooks/useDepartures";
import { LoadingState } from "@/app/components/LoadingState";
import { ErrorState } from "@/app/components/ErrorState";
import { StopList } from "@/app/components/StopList";
import { DepartureDetail } from "@/app/components/DepartureDetail";
import { MapView } from "@/app/components/Map";
import { BottomSheet } from "@/app/components/BottomSheet";

export default function Home() {
  const [selectedStop, setSelectedStop] = useState<NearbyStop | null>(null);
  const geo = useGeolocation();
  const stopsHook = useNearbyStops(geo.coords);
  const depsHook = useDepartures(
    selectedStop?.id ?? null,
    geo.coords ?? { lat: 0, lon: 0 },
    selectedStop?.location ?? { lat: 0, lon: 0 }
  );

  if (geo.loading || stopsHook.loading) {
    return <LoadingState />;
  }

  if (geo.error === "permission_denied") {
    return <ErrorState type="permission" onRetry={geo.retry} />;
  }

  if (stopsHook.error === "network") {
    return <ErrorState type="network" onRetry={geo.retry} />;
  }

  const userCoords = geo.coords!;

  return (
    <div className="app-layout">
      <div className="map-container">
        <MapView
          userCoords={userCoords}
          stops={selectedStop ? [selectedStop] : stopsHook.stops}
          walkingRoute={depsHook.walkingRoute ?? undefined}
        />
      </div>
      <BottomSheet>
        {selectedStop ? (
          <DepartureDetail
            stop={selectedStop}
            departures={depsHook.departures}
            walkingRoute={depsHook.walkingRoute}
            onBack={() => setSelectedStop(null)}
          />
        ) : (
          <StopList stops={stopsHook.stops} onSelectStop={setSelectedStop} />
        )}
      </BottomSheet>
    </div>
  );
}

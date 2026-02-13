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

  if (selectedStop) {
    return (
      <DepartureDetail
        stop={selectedStop}
        departures={depsHook.departures}
        walkingRoute={depsHook.walkingRoute}
        onBack={() => setSelectedStop(null)}
      />
    );
  }

  return <StopList stops={stopsHook.stops} onSelectStop={setSelectedStop} />;
}

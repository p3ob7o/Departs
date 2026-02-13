"use client";

import { useState } from "react";
import type { NearbyStop } from "@/app/types";
import { BottomSheet } from "@/app/components/BottomSheet";
import { DepartureDetail } from "@/app/components/DepartureDetail";
import { ErrorState } from "@/app/components/ErrorState";
import { LoadingState } from "@/app/components/LoadingState";
import { MapView } from "@/app/components/Map";
import { StopList } from "@/app/components/StopList";
import { useDepartures } from "@/app/hooks/useDepartures";
import { useGeolocation } from "@/app/hooks/useGeolocation";
import { useNearbyStops } from "@/app/hooks/useNearbyStops";

function mapGeolocationErrorToView(
  error: string | null
): "permission" | "network" | "timeout" {
  if (error === "permission_denied") {
    return "permission";
  }

  if (error === "timeout") {
    return "timeout";
  }

  return "network";
}

export default function Home() {
  const [selectedStop, setSelectedStop] = useState<NearbyStop | null>(null);
  const geolocation = useGeolocation();
  const nearbyStops = useNearbyStops(geolocation.coords);

  const departures = useDepartures(
    selectedStop?.id ?? null,
    geolocation.coords ?? { lat: 0, lon: 0 },
    selectedStop?.location ?? { lat: 0, lon: 0 }
  );

  if (geolocation.loading) {
    return <LoadingState />;
  }

  if (geolocation.error) {
    return (
      <ErrorState
        type={mapGeolocationErrorToView(geolocation.error)}
        onRetry={geolocation.retry}
      />
    );
  }

  if (!geolocation.coords) {
    return <ErrorState type="network" onRetry={geolocation.retry} />;
  }

  if (nearbyStops.loading && !selectedStop) {
    return <LoadingState message="Loading nearby stops..." />;
  }

  if (nearbyStops.error && !selectedStop) {
    return <ErrorState type="network" onRetry={geolocation.retry} />;
  }

  if (!selectedStop && nearbyStops.stops.length === 0) {
    return <ErrorState type="empty" onRetry={geolocation.retry} />;
  }

  if (selectedStop && departures.error) {
    return <ErrorState type="network" onRetry={() => setSelectedStop(null)} />;
  }

  if (selectedStop) {
    return (
      <main className="mx-auto min-h-screen w-full max-w-[430px] bg-zinc-50 dark:bg-black">
        <MapView
          userCoords={geolocation.coords}
          stops={[selectedStop]}
          walkingRoute={departures.walkingRoute ?? undefined}
        />
        <BottomSheet>
          {departures.loading ? (
            <LoadingState message="Loading departures..." />
          ) : (
            <DepartureDetail
              stop={selectedStop}
              departures={departures.departures}
              walkingRoute={departures.walkingRoute}
              onBack={() => setSelectedStop(null)}
            />
          )}
        </BottomSheet>
      </main>
    );
  }

  return (
    <main className="mx-auto min-h-screen w-full max-w-[430px] bg-zinc-50 dark:bg-black">
      <MapView userCoords={geolocation.coords} stops={nearbyStops.stops} />
      <BottomSheet>
        <StopList stops={nearbyStops.stops} onSelectStop={setSelectedStop} />
      </BottomSheet>
    </main>
  );
}

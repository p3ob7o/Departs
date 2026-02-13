import { Map, Marker, Source, Layer } from "react-map-gl/mapbox";
import type { NearbyStop, WalkingRoute } from "@/app/types";

export function MapView({
  userCoords,
  stops,
  walkingRoute,
  darkMode,
}: {
  userCoords: { lat: number; lon: number };
  stops: NearbyStop[];
  walkingRoute?: WalkingRoute;
  darkMode?: boolean;
}) {
  const mapStyle = darkMode
    ? "mapbox://styles/mapbox/dark-v11"
    : "mapbox://styles/mapbox/light-v11";

  return (
    <Map
      data-latitude={userCoords.lat}
      data-longitude={userCoords.lon}
      data-mapstyle={mapStyle}
      initialViewState={{
        latitude: userCoords.lat,
        longitude: userCoords.lon,
        zoom: 15,
      }}
      mapStyle={mapStyle}
      mapboxAccessToken={process.env.NEXT_PUBLIC_MAPBOX_TOKEN}
    >
      <Marker latitude={userCoords.lat} longitude={userCoords.lon} />
      {stops.map((stop) => (
        <Marker
          key={stop.id}
          latitude={stop.location.lat}
          longitude={stop.location.lon}
        />
      ))}
      {walkingRoute && (
        <Source
          type="geojson"
          data={{
            type: "Feature",
            properties: {},
            geometry: walkingRoute.geometry,
          }}
        >
          <Layer
            type="line"
            paint={{
              "line-color": "#3b82f6",
              "line-width": 4,
            }}
          />
        </Source>
      )}
    </Map>
  );
}

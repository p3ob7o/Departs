import type { NearbyStop, WalkingRoute } from "@/app/types";

const LIGHT_MAP_STYLE = "mapbox://styles/mapbox/light-v11";
const DARK_MAP_STYLE = "mapbox://styles/mapbox/dark-v11";

export function MapView(props: {
  userCoords: { lat: number; lon: number };
  stops: NearbyStop[];
  walkingRoute?: WalkingRoute;
  darkMode?: boolean;
}) {
  const mapStyle = props.darkMode ? DARK_MAP_STYLE : LIGHT_MAP_STYLE;

  return (
    <div
      data-testid="map"
      data-latitude={props.userCoords.lat}
      data-longitude={props.userCoords.lon}
      data-mapstyle={mapStyle}
      className="h-[55vh] w-full bg-zinc-100 dark:bg-zinc-900"
    >
      <div
        data-testid="marker"
        data-latitude={props.userCoords.lat}
        data-longitude={props.userCoords.lon}
      />
      {props.stops.map((stop) => (
        <div
          key={stop.id}
          data-testid="marker"
          data-latitude={stop.location.lat}
          data-longitude={stop.location.lon}
        />
      ))}
      {props.walkingRoute ? (
        <div data-testid="source">
          <div data-testid="layer" />
        </div>
      ) : null}
    </div>
  );
}

"use client";

import { useRef, useEffect, useState, useCallback } from "react";
import { Map, Marker, Source, Layer } from "react-map-gl/mapbox";
import type { MapRef } from "react-map-gl/mapbox";
import "mapbox-gl/dist/mapbox-gl.css";
import type { NearbyStop, WalkingRoute } from "@/app/types";
import { getTransportName } from "./TransportIcon";

function useDarkMode(): boolean {
  const [dark, setDark] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    setDark(mq.matches);
    const handler = (e: MediaQueryListEvent) => setDark(e.matches);
    mq.addEventListener("change", handler);
    return () => mq.removeEventListener("change", handler);
  }, []);
  return dark;
}

export function MapView({
  userCoords,
  stops,
  walkingRoute,
  onBoundsReady,
}: {
  userCoords: { lat: number; lon: number };
  stops: NearbyStop[];
  walkingRoute?: WalkingRoute;
  onBoundsReady?: (bounds: { north: number; south: number; east: number; west: number }) => void;
}) {
  const mapRef = useRef<MapRef>(null);
  const darkMode = useDarkMode();
  const isScreen2 = !!walkingRoute;
  const selectedStop = isScreen2 ? stops[0] : null;

  const mapStyle = darkMode
    ? "mapbox://styles/mapbox/dark-v11"
    : "mapbox://styles/mapbox/light-v11";

  const userDotColor = darkMode ? "#0A84FF" : "#007AFF";
  const routeColor = darkMode ? "#FFFFFF" : "#007AFF";
  const stopPinColor = darkMode ? "#30D158" : "#34C759";

  const fitRouteBounds = useCallback(() => {
    if (!walkingRoute || !mapRef.current) return;
    const coords = walkingRoute.geometry.coordinates as [number, number][];
    if (coords.length === 0) return;

    let minLng = coords[0][0], maxLng = coords[0][0];
    let minLat = coords[0][1], maxLat = coords[0][1];
    for (const [lng, lat] of coords) {
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
    }
    mapRef.current.fitBounds(
      [[minLng, minLat], [maxLng, maxLat]],
      { padding: 60, duration: 300 }
    );
  }, [walkingRoute]);

  useEffect(() => {
    if (walkingRoute) {
      const timer = setTimeout(fitRouteBounds, 100);
      return () => clearTimeout(timer);
    } else if (mapRef.current) {
      mapRef.current.flyTo({
        center: [userCoords.lon, userCoords.lat],
        zoom: 15,
        duration: 300,
      });
    }
  }, [walkingRoute, fitRouteBounds, userCoords.lat, userCoords.lon]);

  return (
    <Map
      ref={mapRef}
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
      scrollZoom={false}
      dragPan={false}
      dragRotate={false}
      touchZoomRotate={false}
      doubleClickZoom={false}
      onLoad={() => {
        const b = onBoundsReady && mapRef.current?.getBounds();
        if (b) {
          onBoundsReady({
            north: b.getNorth(),
            south: b.getSouth(),
            east: b.getEast(),
            west: b.getWest(),
          });
        }
      }}
    >
      {/* User location: blue dot + halo */}
      <Marker latitude={userCoords.lat} longitude={userCoords.lon} anchor="center">
        <div style={{ position: "relative", width: "24px", height: "24px" }}>
          <div
            className="pulse-halo"
            style={{
              position: "absolute",
              top: "50%",
              left: "50%",
              transform: "translate(-50%, -50%)",
              width: "24px",
              height: "24px",
              borderRadius: "50%",
              backgroundColor: userDotColor,
              opacity: 0.2,
              animation: "pulse-halo 2s ease-in-out infinite",
            }}
          />
          <div
            style={{
              position: "absolute",
              top: "50%",
              left: "50%",
              transform: "translate(-50%, -50%)",
              width: "12px",
              height: "12px",
              borderRadius: "50%",
              backgroundColor: userDotColor,
              border: "2px solid white",
              boxShadow: "0 0 4px rgba(0,0,0,0.3)",
            }}
          />
        </div>
      </Marker>

      {/* Screen 2: Green stop pin */}
      {selectedStop && (
        <Marker
          latitude={selectedStop.location.lat}
          longitude={selectedStop.location.lon}
          anchor="bottom"
        >
          <div style={{ display: "flex", flexDirection: "column", alignItems: "center" }}>
            <div
              style={{
                width: "32px",
                height: "32px",
                borderRadius: "50%",
                backgroundColor: stopPinColor,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                color: "white",
                fontSize: "14px",
                fontWeight: "bold",
                boxShadow: "0 2px 6px rgba(0,0,0,0.3)",
              }}
            >
              {selectedStop.type === "subway"
                ? "U"
                : selectedStop.type === "tram"
                  ? "T"
                  : selectedStop.type === "bus"
                    ? "B"
                    : "R"}
            </div>
            <div
              style={{
                marginTop: "2px",
                fontSize: "13px",
                lineHeight: "18px",
                color: darkMode ? "#fff" : "#1C1C1E",
                textShadow: darkMode
                  ? "0 1px 3px rgba(0,0,0,0.8)"
                  : "0 1px 3px rgba(255,255,255,0.8)",
                fontWeight: 500,
                whiteSpace: "nowrap",
              }}
            >
              {getTransportName(selectedStop.type)} · {selectedStop.name}
            </div>
          </div>
        </Marker>
      )}

      {/* Screen 1: stop markers with transport letter */}
      {!isScreen2 &&
        stops.map((stop) => (
          <Marker
            key={stop.id}
            latitude={stop.location.lat}
            longitude={stop.location.lon}
            anchor="center"
          >
            <div
              style={{
                width: "28px",
                height: "28px",
                borderRadius: "50%",
                backgroundColor: stopPinColor,
                border: "2px solid white",
                boxShadow: "0 1px 3px rgba(0,0,0,0.3)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                color: "white",
                fontSize: "13px",
                fontWeight: "bold",
              }}
            >
              {stop.type === "subway"
                ? "U"
                : stop.type === "tram"
                  ? "T"
                  : stop.type === "bus"
                    ? "B"
                    : "R"}
            </div>
          </Marker>
        ))}

      {/* Walking route: dashed line */}
      {walkingRoute && (
        <Source
          id="walking-route"
          type="geojson"
          data={{
            type: "Feature",
            properties: {},
            geometry: walkingRoute.geometry,
          }}
        >
          <Layer
            id="walking-route-line"
            type="line"
            paint={{
              "line-color": routeColor,
              "line-width": 3,
              "line-dasharray": [2, 1.5],
            }}
          />
        </Source>
      )}
    </Map>
  );
}

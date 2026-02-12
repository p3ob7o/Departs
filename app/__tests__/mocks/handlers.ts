import { http, HttpResponse } from "msw";
import hereStationsResponse from "../fixtures/here-stations-response.json";
import hereBoardsResponse from "../fixtures/here-boards-response.json";
import mapboxDirectionsResponse from "../fixtures/mapbox-directions-response.json";

export const handlers = [
  // HERE Stations (nearby stops) — proxied through Next.js
  http.get("/api/stops/nearby", ({ request }) => {
    const url = new URL(request.url);
    const lat = url.searchParams.get("lat");
    const lon = url.searchParams.get("lon");

    if (!lat || !lon) {
      return HttpResponse.json(
        { error: "Missing lat/lon parameters" },
        { status: 400 }
      );
    }

    return HttpResponse.json(hereStationsResponse);
  }),

  // HERE Departures — proxied through Next.js
  http.get("/api/departures", ({ request }) => {
    const url = new URL(request.url);
    const stopId = url.searchParams.get("stopId");

    if (!stopId) {
      return HttpResponse.json(
        { error: "Missing stopId parameter" },
        { status: 400 }
      );
    }

    return HttpResponse.json(hereBoardsResponse);
  }),

  // Mapbox Walking Directions — proxied through Next.js
  http.get("/api/directions", ({ request }) => {
    const url = new URL(request.url);
    const from = url.searchParams.get("from");
    const to = url.searchParams.get("to");

    if (!from || !to) {
      return HttpResponse.json(
        { error: "Missing from/to parameters" },
        { status: 400 }
      );
    }

    return HttpResponse.json(mapboxDirectionsResponse);
  }),

  // Direct HERE API (for API route tests in node env)
  http.get("https://transit.hereapi.com/v8/stations", () => {
    return HttpResponse.json(hereStationsResponse);
  }),

  http.get("https://transit.hereapi.com/v8/boards", () => {
    return HttpResponse.json(hereBoardsResponse);
  }),

  // Direct Mapbox API (for API route tests in node env)
  http.get("https://api.mapbox.com/directions/v5/mapbox/walking/*", () => {
    return HttpResponse.json(mapboxDirectionsResponse);
  }),
];

import type { WalkingRoute } from "@/app/types";

type Coordinates = { lat: number; lon: number };

type MapboxDirectionsResponse = {
  routes?: Array<{
    geometry?: GeoJSON.LineString;
    duration?: number;
    distance?: number;
  }>;
};

function jsonResponse(body: unknown, init?: ResponseInit): Response {
  const headers = new Headers(init?.headers);
  headers.set("Content-Type", "application/json");
  return new Response(JSON.stringify(body), { ...init, headers });
}

function parseCoordinates(value: string | null): Coordinates | null {
  if (!value) {
    return null;
  }

  const [latString, lonString] = value.split(",");
  const lat = Number(latString);
  const lon = Number(lonString);

  if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
    return null;
  }

  return { lat, lon };
}

function toWalkingRoute(data: MapboxDirectionsResponse): WalkingRoute | null {
  const route = data.routes?.[0];

  if (!route?.geometry) {
    return null;
  }

  return {
    geometry: route.geometry,
    duration: Number(route.duration ?? 0),
    distance: Number(route.distance ?? 0),
  };
}

export async function GET(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const fromParam = url.searchParams.get("from");
  const toParam = url.searchParams.get("to");

  if (!fromParam) {
    return jsonResponse({ error: "Missing from parameter" }, { status: 400 });
  }

  if (!toParam) {
    return jsonResponse({ error: "Missing to parameter" }, { status: 400 });
  }

  const from = parseCoordinates(fromParam);
  const to = parseCoordinates(toParam);

  if (!from || !to) {
    return jsonResponse({ error: "Invalid coordinates" }, { status: 400 });
  }

  const token =
    process.env.MAPBOX_SECRET_TOKEN ?? process.env.NEXT_PUBLIC_MAPBOX_TOKEN ?? "";
  const upstreamUrl = new URL(
    `https://api.mapbox.com/directions/v5/mapbox/walking/${from.lon},${from.lat};${to.lon},${to.lat}`
  );
  upstreamUrl.searchParams.set("geometries", "geojson");
  upstreamUrl.searchParams.set("access_token", token);

  try {
    const upstreamResponse = await fetch(upstreamUrl.toString());

    if (!upstreamResponse.ok) {
      return jsonResponse({ error: "Failed to fetch directions" }, { status: 500 });
    }

    const rawData = (await upstreamResponse.json()) as MapboxDirectionsResponse;
    const walkingRoute = toWalkingRoute(rawData);

    if (!walkingRoute) {
      return jsonResponse({ error: "Invalid directions response" }, { status: 500 });
    }

    return jsonResponse(walkingRoute, {
      status: 200,
      headers: {
        "Cache-Control": "public, max-age=3600, s-maxage=3600",
      },
    });
  } catch {
    return jsonResponse({ error: "Failed to fetch directions" }, { status: 500 });
  }
}

import { isValidCoordinate } from "@/app/lib/coordinates";

export async function walkingDirections(request: Request, apiKey: string | undefined): Promise<Response> {
  const { searchParams } = new URL(request.url);
  const fromStr = searchParams.get("from");
  const toStr = searchParams.get("to");

  if (!fromStr || !toStr) {
    return Response.json(
      { error: "Missing from/to parameters" },
      { status: 400 }
    );
  }

  const fromParts = fromStr.split(",");
  const toParts = toStr.split(",");
  const [fromLat, fromLon] = fromParts.map(Number);
  const [toLat, toLon] = toParts.map(Number);

  if (
    fromParts.some((part) => !part.trim()) ||
    toParts.some((part) => !part.trim()) ||
    fromParts.length !== 2 ||
    toParts.length !== 2 ||
    !isValidCoordinate(fromLat, fromLon) ||
    !isValidCoordinate(toLat, toLon)
  ) {
    return Response.json(
      { error: "Invalid coordinate format" },
      { status: 400 }
    );
  }

  try {
    const res = await fetch(
      `https://api.mapbox.com/directions/v5/mapbox/walking/${fromLon},${fromLat};${toLon},${toLat}?geometries=geojson&access_token=${apiKey}`,
      { signal: AbortSignal.timeout(10_000) }
    );

    if (!res.ok) throw new Error(`Mapbox API error: ${res.status}`);

    const data = await res.json();
    const route = data.routes?.[0];

    if (
      route?.geometry?.type !== "LineString" ||
      !Array.isArray(route.geometry.coordinates) ||
      route.geometry.coordinates.length < 2 ||
      !route.geometry.coordinates.every((point: unknown) =>
        Array.isArray(point) && point.length >= 2 && isValidCoordinate(point[1], point[0])
      ) ||
      !Number.isFinite(route.duration) || route.duration < 0 ||
      !Number.isFinite(route.distance) || route.distance < 0
    ) {
      return Response.json(
        { error: "No walking route found" },
        { status: 502 }
      );
    }

    return Response.json(
      {
        geometry: route.geometry,
        duration: route.duration,
        distance: route.distance,
      },
      {
        headers: { "Cache-Control": "public, max-age=3600" },
      }
    );
  } catch {
    return Response.json(
      { error: "Failed to fetch directions" },
      { status: 500 }
    );
  }
}

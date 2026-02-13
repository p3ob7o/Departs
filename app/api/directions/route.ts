export async function GET(request: Request): Promise<Response> {
  const { searchParams } = new URL(request.url);
  const fromStr = searchParams.get("from");
  const toStr = searchParams.get("to");

  if (!fromStr || !toStr) {
    return Response.json(
      { error: "Missing from/to parameters" },
      { status: 400 }
    );
  }

  const [fromLat, fromLon] = fromStr.split(",").map(Number);
  const [toLat, toLon] = toStr.split(",").map(Number);

  if ([fromLat, fromLon, toLat, toLon].some(isNaN)) {
    return Response.json(
      { error: "Invalid coordinate format" },
      { status: 400 }
    );
  }

  try {
    const res = await fetch(
      `https://api.mapbox.com/directions/v5/mapbox/walking/${fromLon},${fromLat};${toLon},${toLat}?geometries=geojson&access_token=${process.env.MAPBOX_SECRET_TOKEN}`
    );

    if (!res.ok) throw new Error(`Mapbox API error: ${res.status}`);

    const data = await res.json();
    const route = data.routes[0];

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

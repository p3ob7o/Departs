function isValidLatLon(lat: number, lon: number): boolean {
  return (
    Number.isFinite(lat) &&
    Number.isFinite(lon) &&
    lat >= -90 &&
    lat <= 90 &&
    lon >= -180 &&
    lon <= 180
  );
}

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

  const fromParts = fromStr.split(",");
  const toParts = toStr.split(",");
  const [fromLat, fromLon] = fromParts.map(Number);
  const [toLat, toLon] = toParts.map(Number);

  if (
    fromParts.length !== 2 ||
    toParts.length !== 2 ||
    !isValidLatLon(fromLat, fromLon) ||
    !isValidLatLon(toLat, toLon)
  ) {
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
    const route = data.routes?.[0];

    if (
      !route?.geometry ||
      typeof route.duration !== "number" ||
      typeof route.distance !== "number"
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

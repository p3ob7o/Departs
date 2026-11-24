import { isValidCoordinate } from "@/app/lib/coordinates";
import { transformStations } from "@/app/lib/transitProvider";

export async function nearbyStops(request: Request, apiKey: string | undefined): Promise<Response> {
  const { searchParams } = new URL(request.url);
  const latStr = searchParams.get("lat");
  const lonStr = searchParams.get("lon");
  const radiusStr = searchParams.get("radius");
  const radius = radiusStr === null ? 400 : Number(radiusStr);

  if (!latStr?.trim() || !lonStr?.trim()) {
    return Response.json(
      { error: "Missing lat/lon parameters" },
      { status: 400 }
    );
  }

  const lat = Number(latStr);
  const lon = Number(lonStr);

  if (!isValidCoordinate(lat, lon)) {
    return Response.json(
      { error: "Invalid lat/lon parameters" },
      { status: 400 }
    );
  }

  if (radiusStr?.trim() === "" || !Number.isInteger(radius) || radius < 100 || radius > 2000) {
    return Response.json(
      { error: "radius must be a whole number between 100 and 2000 metres" },
      { status: 400 }
    );
  }

  try {
    const params = new URLSearchParams({
      in: `${lat},${lon};r=${radius}`,
      maxPlaces: "50",
      return: "transport",
      apiKey: apiKey ?? "",
    });
    const res = await fetch(
      `https://transit.hereapi.com/v8/stations?${params}`,
      { signal: AbortSignal.timeout(10_000) }
    );

    if (!res.ok) throw new Error(`HERE API error: ${res.status}`);

    const data = await res.json();
    const stops = transformStations(data);

    return Response.json(stops, {
      headers: { "Cache-Control": "public, max-age=86400" },
    });
  } catch {
    return Response.json(
      { error: "Failed to fetch nearby stops" },
      { status: 500 }
    );
  }
}

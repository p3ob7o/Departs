import { transformStations } from "@/app/lib/transitProvider";

export async function GET(request: Request): Promise<Response> {
  const { searchParams } = new URL(request.url);
  const latStr = searchParams.get("lat");
  const lonStr = searchParams.get("lon");

  if (!latStr || !lonStr) {
    return Response.json(
      { error: "Missing lat/lon parameters" },
      { status: 400 }
    );
  }

  const lat = Number(latStr);
  const lon = Number(lonStr);

  if (isNaN(lat) || isNaN(lon)) {
    return Response.json(
      { error: "Invalid lat/lon parameters" },
      { status: 400 }
    );
  }

  try {
    const res = await fetch(
      `https://transit.hereapi.com/v8/stations?in=${lat},${lon};r=250&return=transport&apiKey=${process.env.HERE_API_KEY}`
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

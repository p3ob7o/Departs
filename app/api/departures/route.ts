import { transformDepartures } from "@/app/lib/transitProvider";

export async function GET(request: Request): Promise<Response> {
  const { searchParams } = new URL(request.url);
  const stopId = searchParams.get("stopId");

  if (!stopId) {
    return Response.json(
      { error: "Missing stopId parameter" },
      { status: 400 }
    );
  }

  try {
    const res = await fetch(
      `https://transit.hereapi.com/v8/departures?ids=${encodeURIComponent(stopId)}&maxPerBoard=4&apiKey=${process.env.HERE_API_KEY}`
    );

    if (!res.ok) throw new Error(`HERE API error: ${res.status}`);

    const data = await res.json();
    const departures = transformDepartures(data);

    return Response.json(departures, {
      headers: { "Cache-Control": "public, max-age=30" },
    });
  } catch {
    return Response.json(
      { error: "Failed to fetch departures" },
      { status: 500 }
    );
  }
}

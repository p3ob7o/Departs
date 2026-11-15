import { transformDepartures } from "@/app/lib/transitProvider";

export async function GET(request: Request): Promise<Response> {
  const { searchParams } = new URL(request.url);
  const stopId = searchParams.get("stopId");
  const lineName = searchParams.get("lineName");
  const direction = searchParams.get("direction");

  if (!stopId) {
    return Response.json(
      { error: "Missing stopId parameter" },
      { status: 400 }
    );
  }

  if ((lineName && !direction) || (!lineName && direction)) {
    return Response.json(
      { error: "lineName and direction must be provided together" },
      { status: 400 }
    );
  }

  try {
    const hereParams = new URLSearchParams({
      ids: stopId,
      // HERE sorts by scheduled time. Fetch enough to reorder by predicted time.
      maxPerBoard: "50",
      maxPerTransport: "4",
      apiKey: process.env.HERE_API_KEY ?? "",
    });
    const res = await fetch(
      `https://transit.hereapi.com/v8/departures?${hereParams.toString()}`,
      { signal: AbortSignal.timeout(10_000) }
    );

    if (!res.ok) throw new Error(`HERE API error: ${res.status}`);

    const data = await res.json();
    const departures = transformDepartures(data)
      .filter((departure) => {
        if (!lineName || !direction) return true;
        return (
          departure.line?.name === lineName &&
          departure.line.direction === direction
        );
      })
      .sort((a, b) => Date.parse(a.time) - Date.parse(b.time))
      .slice(0, 4);

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

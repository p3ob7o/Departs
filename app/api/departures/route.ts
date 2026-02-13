import { transformDepartures } from "@/app/lib/transitProvider";

function jsonResponse(body: unknown, init?: ResponseInit): Response {
  const headers = new Headers(init?.headers);
  headers.set("Content-Type", "application/json");
  return new Response(JSON.stringify(body), { ...init, headers });
}

export async function GET(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const stopId = url.searchParams.get("stopId");

  if (!stopId) {
    return jsonResponse({ error: "Missing stopId parameter" }, { status: 400 });
  }

  const upstreamUrl = new URL("https://transit.hereapi.com/v8/boards");
  upstreamUrl.searchParams.set("ids", stopId);
  upstreamUrl.searchParams.set("maxPerBoard", "4");

  if (process.env.HERE_API_KEY) {
    upstreamUrl.searchParams.set("apiKey", process.env.HERE_API_KEY);
  }

  try {
    const upstreamResponse = await fetch(upstreamUrl.toString());

    if (!upstreamResponse.ok) {
      return jsonResponse({ error: "Failed to fetch departures" }, { status: 500 });
    }

    const rawData = await upstreamResponse.json();
    const departures = transformDepartures(rawData);

    return jsonResponse(departures, {
      status: 200,
      headers: {
        "Cache-Control": "public, max-age=30, s-maxage=30",
      },
    });
  } catch {
    return jsonResponse({ error: "Failed to fetch departures" }, { status: 500 });
  }
}

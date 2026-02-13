import { transformStations } from "@/app/lib/transitProvider";

function jsonResponse(body: unknown, init?: ResponseInit): Response {
  const headers = new Headers(init?.headers);
  headers.set("Content-Type", "application/json");
  return new Response(JSON.stringify(body), { ...init, headers });
}

export async function GET(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const latParam = url.searchParams.get("lat");
  const lonParam = url.searchParams.get("lon");

  if (!latParam || !lonParam) {
    return jsonResponse({ error: "Missing lat/lon parameters" }, { status: 400 });
  }

  const lat = Number(latParam);
  const lon = Number(lonParam);

  if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
    return jsonResponse({ error: "Invalid lat/lon parameters" }, { status: 400 });
  }

  const radius = process.env.NEXT_PUBLIC_SEARCH_RADIUS ?? "250";
  const upstreamUrl = new URL("https://transit.hereapi.com/v8/stations");
  upstreamUrl.searchParams.set("in", `${lat},${lon};r=${radius}`);

  if (process.env.HERE_API_KEY) {
    upstreamUrl.searchParams.set("apiKey", process.env.HERE_API_KEY);
  }

  try {
    const upstreamResponse = await fetch(upstreamUrl.toString());

    if (!upstreamResponse.ok) {
      return jsonResponse({ error: "Failed to fetch nearby stops" }, { status: 500 });
    }

    const rawData = await upstreamResponse.json();
    const stops = transformStations(rawData);

    return jsonResponse(stops, {
      status: 200,
      headers: {
        "Cache-Control": "public, max-age=86400, s-maxage=86400",
      },
    });
  } catch {
    return jsonResponse({ error: "Failed to fetch nearby stops" }, { status: 500 });
  }
}

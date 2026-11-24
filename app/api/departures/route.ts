import type { Departure } from "@/app/types";
import { transformDepartures } from "@/app/lib/transitProvider";

type FailureKind = "HTTPError" | "NetworkError" | "TimeoutError" | "InvalidResponse";

class UpstreamFailure extends Error {
  constructor(readonly kind: FailureKind, readonly status?: number) {
    super(kind);
  }
}

async function requestDepartures(ids: string, perTransport: number) {
  const params = new URLSearchParams({
    ids,
    maxPerBoard: "50",
    maxPerTransport: String(perTransport),
    apiKey: process.env.HERE_API_KEY ?? "",
  });
  for (let attempt = 0; attempt < 2; attempt++) {
    // Keep this timestamp in the cached response: receipt at the client is later.
    const fetchedAt = new Date().toISOString();
    try {
      const response = await fetch(`https://transit.hereapi.com/v8/departures?${params}`, {
        signal: AbortSignal.timeout(10_000),
        cache: "no-store",
      });
      if (!response.ok) {
        // Releasing an unread/teed body must not delay the retry or error reply.
        void response.body?.cancel().catch(() => {});
        throw new UpstreamFailure("HTTPError", response.status);
      }
      const data = await response.json();
      return { data, fetchedAt };
    } catch (error) {
      // Never retain an upstream URL, response body, or error message: they can
      // contain credentials. These fixed categories are the only logged values.
      const failure = error instanceof UpstreamFailure ? error
        : error instanceof SyntaxError ? new UpstreamFailure("InvalidResponse")
        : error instanceof DOMException && ["TimeoutError", "AbortError"].includes(error.name)
          ? new UpstreamFailure("TimeoutError") : new UpstreamFailure("NetworkError");
      const retryable = failure.kind === "NetworkError" || failure.kind === "TimeoutError"
        || (failure.status !== undefined && failure.status >= 500);
      if (attempt === 1 || !retryable) throw failure;
    }
  }
  throw new UpstreamFailure("NetworkError");
}

function upstreamError(error: unknown, status: number) {
  const failure = error instanceof UpstreamFailure ? error : new UpstreamFailure("InvalidResponse");
  console.error("departures upstream failure", {
    errorClass: failure.kind,
    ...(failure.status === undefined ? {} : { status: failure.status }),
  });
  return Response.json({ error: "Failed to fetch departures" }, { status });
}

function groupDepartures(departures: Departure[], limit: number) {
  const groups = new Map<string, { line: NonNullable<Departure["line"]>; departures: Departure[] }>();
  for (const departure of departures) {
    if (!departure.line) continue;
    const key = JSON.stringify([departure.line.type, departure.line.name, departure.line.direction]);
    let group = groups.get(key);
    if (!group) {
      group = { line: departure.line, departures: [] };
      groups.set(key, group);
    }
    if (group.departures.length < limit) group.departures.push(departure);
  }
  return [...groups.values()];
}

async function batchDepartures(params: URLSearchParams): Promise<Response> {
  const ids = (params.get("stopIds") ?? "").split(",").map((id) => id.trim());
  if (params.getAll("stopIds").length !== 1 || ids.length > 50 || ids.some((id) => !id)
    || ["stopId", "lineName", "direction", "groupBy"].some((name) => params.has(name))) {
    return Response.json({ error: "Provide 1 to 50 stopIds without single-stop filters" }, { status: 400 });
  }
  const requested = [...new Set(ids)];
  try {
    const { data, fetchedAt } = await requestDepartures(requested.join(","), 2);
    if (!data || !Array.isArray(data.boards)) throw new UpstreamFailure("InvalidResponse");
    const platforms = new Map<string, Departure[]>();
    for (const board of data.boards) {
      if (typeof board?.place?.id !== "string" || !Array.isArray(board.departures)) {
        throw new UpstreamFailure("InvalidResponse");
      }
      const id: string = board.place.id;
      if (!requested.includes(id)) continue;
      const departures = transformDepartures({ boards: [board] });
      platforms.set(id, [...(platforms.get(id) ?? []), ...departures]);
    }
    const boards = requested.flatMap((stopId) => {
      const departures = platforms.get(stopId);
      if (!departures) return [];
      departures.sort((a, b) => Date.parse(a.time) - Date.parse(b.time));
      return [{ stopId, groups: groupDepartures(departures, 2) }];
    });
    return Response.json({ fetchedAt, boards, missing: requested.filter((id) => !platforms.has(id)) }, {
      headers: { "Cache-Control": "public, max-age=30" },
    });
  } catch (error) {
    return upstreamError(error, 502);
  }
}

export async function GET(request: Request): Promise<Response> {
  const { searchParams } = new URL(request.url);
  if (searchParams.has("stopIds")) return batchDepartures(searchParams);
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
    const { data } = await requestDepartures(stopId, 4);
    const allDepartures = transformDepartures(data)
      .sort((a, b) => Date.parse(a.time) - Date.parse(b.time));
    if (searchParams.get("groupBy") === "line") {
      const groups = groupDepartures(allDepartures, 4);
      // HERE caps each platform board, before transformation or flattening.
      // Missing lines at a capped hub have limited timetable coverage; another
      // filtered request has the same cap and cannot recover later times.
      const complete = Array.isArray(data.boards) && data.boards.every(
        (board: { departures?: unknown[] }) => Array.isArray(board.departures) && board.departures.length < 50
      );
      return Response.json({ groups, complete }, {
        headers: { "Cache-Control": "public, max-age=30" },
      });
    }
    // Installed iOS builds send a raw "+" (direction=S+U%20Pankow), which
    // searchParams reads as a space. Match "+" and " " as the same character.
    const matchable = (value: string) => value.replace(/\+/g, " ");
    const departures = allDepartures
      .filter((departure) => {
        if (!lineName || !direction) return true;
        return (
          departure.line !== undefined &&
          matchable(departure.line.name) === matchable(lineName) &&
          matchable(departure.line.direction) === matchable(direction)
        );
      })
      .sort((a, b) => Date.parse(a.time) - Date.parse(b.time))
      .slice(0, 4);

    return Response.json(departures, {
      headers: { "Cache-Control": "public, max-age=30" },
    });
  } catch (error) {
    // Preserve the installed builds' error contract as well as their payloads.
    return upstreamError(error, 500);
  }
}

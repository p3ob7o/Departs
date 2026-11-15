// @vitest-environment node
import { describe, it, expect } from "vitest";
import { GET } from "@/app/api/departures/route";

describe("GET /api/departures", () => {
  it("returns 400 when stopId is missing", async () => {
    const request = new Request("http://localhost/api/departures");
    const response = await GET(request);

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.error).toBeDefined();
  });

  it("proxies request to HERE boards API", async () => {
    const request = new Request(
      "http://localhost/api/departures?stopId=stop-1"
    );
    const response = await GET(request);

    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body).toHaveLength(4);
  });

  it("returns the next four departures for a selected line and direction", async () => {
    const { server } = await import("@/app/__tests__/setup");
    const { http, HttpResponse } = await import("msw");

    server.use(
      http.get("https://transit.hereapi.com/v8/departures", ({ request }) => {
        const url = new URL(request.url);

        expect(url.searchParams.get("maxPerBoard")).toBe("50");

        return HttpResponse.json({
          boards: [
            {
              departures: [
                {
                  time: "2024-01-15T10:00:00+01:00",
                  transport: { mode: "subway", name: "17", headsign: "Alvik" },
                },
                {
                  time: "2024-01-15T10:02:00+01:00",
                  transport: { mode: "subway", name: "18", headsign: "Farsta strand" },
                },
                {
                  time: "2024-01-15T10:05:00+01:00",
                  transport: { mode: "subway", name: "17", headsign: "Alvik" },
                },
                {
                  time: "2024-01-15T10:10:00+01:00",
                  transport: { mode: "subway", name: "17", headsign: "Alvik" },
                },
                {
                  time: "2024-01-15T10:15:00+01:00",
                  transport: { mode: "subway", name: "17", headsign: "Alvik" },
                },
                {
                  time: "2024-01-15T10:20:00+01:00",
                  transport: { mode: "subway", name: "17", headsign: "Alvik" },
                },
              ],
            },
          ],
        });
      })
    );

    const request = new Request(
      "http://localhost/api/departures?stopId=stop-1&lineName=17&direction=Alvik"
    );
    const response = await GET(request);

    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body).toHaveLength(4);
    expect(body.map((dep: { time: string }) => dep.time)).toEqual([
      "2024-01-15T10:00:00+01:00",
      "2024-01-15T10:05:00+01:00",
      "2024-01-15T10:10:00+01:00",
      "2024-01-15T10:15:00+01:00",
    ]);
  });

  it("sorts all platform boards by predicted time before selecting four departures", async () => {
    const { server } = await import("@/app/__tests__/setup");
    const { http, HttpResponse } = await import("msw");
    server.use(http.get("https://transit.hereapi.com/v8/departures", () => HttpResponse.json({ boards: [
      { departures: [{ time: "2026-11-15T10:00:00Z", rtTime: "2026-11-15T10:30:00Z" }] },
      { departures: [5, 10, 15, 20].map((minute) => ({ time: `2026-11-15T10:${String(minute).padStart(2, "0")}:00Z` })) },
    ] })));
    const response = await GET(new Request("http://localhost/api/departures?stopId=station"));
    const body = await response.json();
    expect(body.map((departure: { time: string }) => departure.time)).toEqual([
      "2026-11-15T10:05:00Z", "2026-11-15T10:10:00Z", "2026-11-15T10:15:00Z", "2026-11-15T10:20:00Z",
    ]);
  });

  it("returns line metadata for departures", async () => {
    const request = new Request(
      "http://localhost/api/departures?stopId=stop-1"
    );
    const response = await GET(request);

    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body[0].line).toEqual({
      name: "U2",
      direction: "Pankow",
      type: "subway",
    });
  });

  it("sets cache headers for 30 seconds", async () => {
    const request = new Request(
      "http://localhost/api/departures?stopId=stop-1"
    );
    const response = await GET(request);

    expect(response.headers.get("Cache-Control")).toContain("max-age=30");
  });

  it("returns 500 when HERE API fails", async () => {
    const { server } = await import("@/app/__tests__/setup");
    const { http, HttpResponse } = await import("msw");

    server.use(
      http.get("https://transit.hereapi.com/v8/departures", () => {
        return HttpResponse.json({ error: "Service unavailable" }, { status: 503 });
      })
    );

    const request = new Request(
      "http://localhost/api/departures?stopId=stop-1"
    );
    const response = await GET(request);

    expect(response.status).toBe(500);
  });
});

describe("optional grouped boards", () => {
  it("returns groups with at most four departures without changing the legacy array", async () => {
    const grouped = await GET(new Request("http://localhost/api/departures?stopId=stop-1&groupBy=line"));
    const payload = await grouped.json();
    expect(Array.isArray(payload.groups)).toBe(true);
    expect(typeof payload.complete).toBe("boolean");
    for (const group of payload.groups) {
      expect(group.line.name).toBeTruthy();
      expect(group.departures.length).toBeLessThanOrEqual(4);
      expect(group.departures.every((departure: { line: unknown }) => JSON.stringify(departure.line) === JSON.stringify(group.line))).toBe(true);
    }
    const legacy = await GET(new Request("http://localhost/api/departures?stopId=stop-1"));
    expect(Array.isArray(await legacy.json())).toBe(true);
  });
});

it("does not claim a capped grouped board is complete", async () => {
  const { server } = await import("@/app/__tests__/setup");
  const { http, HttpResponse } = await import("msw");
  server.use(http.get("https://transit.hereapi.com/v8/departures", () => HttpResponse.json({
    boards: [{ departures: Array.from({ length: 50 }, () => ({
      time: "2026-11-15T10:00:00Z", transport: { mode: "bus", name: "1", headsign: "Centre" },
    })) }],
  })));
  const response = await GET(new Request("http://localhost/api/departures?stopId=stop-1&groupBy=line"));
  const body = await response.json();
  expect(body.complete).toBe(false);
  expect(body.groups).toHaveLength(1);
  expect(body.groups[0].departures).toHaveLength(4);
});

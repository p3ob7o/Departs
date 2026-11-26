// @vitest-environment node
import { describe, it, expect } from "vitest";
import { workerContext } from "@/app/__tests__/setup";
import { GET } from "@/spacefast/functions/api/departures";

describe("GET /api/departures", () => {
  it("returns 400 when stopId is missing", async () => {
    const request = new Request("http://localhost/api/departures");
    const response = await GET(request, workerContext);

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.error).toBeDefined();
  });

  it("proxies request to HERE boards API", async () => {
    const request = new Request(
      "http://localhost/api/departures?stopId=stop-1"
    );
    const response = await GET(request, workerContext);

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
    const response = await GET(request, workerContext);

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
    const response = await GET(new Request("http://localhost/api/departures?stopId=station"), workerContext);
    const body = await response.json();
    expect(body.map((departure: { time: string }) => departure.time)).toEqual([
      "2026-11-15T10:05:00Z", "2026-11-15T10:10:00Z", "2026-11-15T10:15:00Z", "2026-11-15T10:20:00Z",
    ]);
  });

  it("returns line metadata for departures", async () => {
    const request = new Request(
      "http://localhost/api/departures?stopId=stop-1"
    );
    const response = await GET(request, workerContext);

    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body[0].line).toEqual({
      name: "U2",
      direction: "Pankow",
      type: "subway",
    });
  });

  it("prevents caching departure responses", async () => {
    const request = new Request(
      "http://localhost/api/departures?stopId=stop-1"
    );
    const response = await GET(request, workerContext);

    expect(response.headers.get("Cache-Control")).toBe("no-store");
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
    const response = await GET(request, workerContext);

    expect(response.status).toBe(500);
  });
});

describe("optional grouped boards", () => {
  it("returns groups with at most four departures without changing the legacy array", async () => {
    const grouped = await GET(new Request("http://localhost/api/departures?stopId=stop-1&groupBy=line"), workerContext);
    const payload = await grouped.json();
    expect(Array.isArray(payload.groups)).toBe(true);
    expect(typeof payload.complete).toBe("boolean");
    for (const group of payload.groups) {
      expect(group.line.name).toBeTruthy();
      expect(group.departures.length).toBeLessThanOrEqual(4);
      expect(group.departures.every((departure: { line: unknown }) => JSON.stringify(departure.line) === JSON.stringify(group.line))).toBe(true);
    }
    const legacy = await GET(new Request("http://localhost/api/departures?stopId=stop-1"), workerContext);
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
  const response = await GET(new Request("http://localhost/api/departures?stopId=stop-1&groupBy=line"), workerContext);
  const body = await response.json();
  expect(body.complete).toBe(false);
  expect(body.groups).toHaveLength(1);
  expect(body.groups[0].departures).toHaveLength(4);
});

it("checks the cap per platform board, not after flattening", async () => {
  const { server } = await import("@/app/__tests__/setup");
  const { http, HttpResponse } = await import("msw");
  server.use(http.get("https://transit.hereapi.com/v8/departures", () => HttpResponse.json({
    boards: [1, 2].map(() => ({ departures: Array.from({ length: 30 }, () => ({
      time: "2026-11-15T10:00:00Z", transport: { mode: "bus", name: "1", headsign: "Centre" },
    })) })),
  })));
  const response = await GET(new Request("http://localhost/api/departures?stopId=stop-1&groupBy=line"), workerContext);
  expect((await response.json()).complete).toBe(true);
});

describe("plus signs in the line filter", () => {
  // Installed iOS builds leave "+" raw in the query; searchParams reads it as a space.
  const at = (minute: number) => `2026-11-24T10:${String(minute).padStart(2, "0")}:00Z`;
  const departure = (minute: number, name: string, headsign: string) => ({
    time: at(minute),
    transport: { mode: "subway", name, headsign },
  });
  async function filtered(query: string, extra: unknown[] = []) {
    const { server } = await import("@/app/__tests__/setup");
    const { http, HttpResponse } = await import("msw");
    server.use(http.get("https://transit.hereapi.com/v8/departures", () => HttpResponse.json({ boards: [{ departures: [
      departure(1, "U2", "S+U Pankow"),
      departure(2, "U2", "Ruhleben"),
      departure(3, "U8", "S+U Hermannstr."),
      departure(4, "U2", "S+U Pankow"),
      departure(5, "S+1", "Farsta strand"),
      departure(6, "U2", "Pankow"),
      ...extra,
    ] }] })));
    const response = await GET(new Request(`http://localhost/api/departures?stopId=49031_783&${query}`), workerContext);
    expect(response.status).toBe(200);
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    return (await response.json()) as { time: string; line: { name: string; direction: string } }[];
  }

  it("matches a raw plus sent by installed builds", async () => {
    const body = await filtered("lineName=U2&direction=S+U%20Pankow");
    expect(body.map((departure) => departure.time)).toEqual(["2026-11-24T10:01:00Z", "2026-11-24T10:04:00Z"]);
    expect(body.every((departure) => departure.line.direction === "S+U Pankow")).toBe(true);
  });

  it("matches a plus encoded as %2B", async () => {
    const body = await filtered("lineName=U2&direction=S%2BU%20Pankow");
    expect(body.map((departure) => departure.time)).toEqual(["2026-11-24T10:01:00Z", "2026-11-24T10:04:00Z"]);
    expect(body.every((departure) => departure.line.direction === "S+U Pankow")).toBe(true);
  });

  it("matches a real space in either encoding, and a plus in lineName", async () => {
    for (const query of ["lineName=S%2B1&direction=Farsta%20strand", "lineName=S+1&direction=Farsta+strand"]) {
      const body = await filtered(query);
      expect(body.map((departure) => departure.line)).toEqual([{ name: "S+1", direction: "Farsta strand", type: "subway" }]);
    }
  });

  it("does not match a different destination", async () => {
    const body = await filtered("lineName=U8&direction=S+U%20Pankow");
    expect(body).toEqual([]);
  });

  it("matches a destination with two plus signs sent raw", async () => {
    const body = await filtered("lineName=U2&direction=S+U%20Pankow+Bus", [departure(7, "U2", "S+U Pankow+Bus")]);
    expect(body.map((departure) => [departure.time, departure.line.direction])).toEqual([[at(7), "S+U Pankow+Bus"]]);
  });

  it("does not match a destination that differs only by spacing", async () => {
    const body = await filtered("lineName=U2&direction=S+U%20Pankow", [
      departure(7, "U2", "SU Pankow"),
      departure(8, "U2", "S+U  Pankow"),
      departure(9, "U2", "S+UPankow"),
    ]);
    expect(body.map((departure) => departure.time)).toEqual([at(1), at(4)]);
  });

  it("leaves out a departure without a line while the filter is on", async () => {
    const body = await filtered("lineName=U2&direction=S+U%20Pankow", [
      { time: at(0) },
      { time: at(7), transport: null },
      { time: at(8), transport: { mode: "subway", name: "U2" } },
    ]);
    expect(body.map((departure) => departure.time)).toEqual([at(1), at(4)]);
  });

  it("treats a provider name or direction that is not a string as not matching", async () => {
    const malformed = [
      { time: at(0), transport: { mode: "subway", name: 2, headsign: "S+U Pankow" } },
      { time: at(7), transport: { mode: "subway", name: "U2", headsign: ["S+U Pankow"] } },
      { time: at(8), transport: { mode: "subway", name: "U2", headsign: { text: "S+U Pankow" } } },
    ];
    const body = await filtered("lineName=U2&direction=S+U%20Pankow", malformed);
    expect(body.map((departure) => departure.time)).toEqual([at(1), at(4)]);
    expect(await filtered("lineName=2&direction=S+U%20Pankow", malformed)).toEqual([]);
  });
});

it("skips a null line in a provider array while filtering departures", async () => {
  const { server } = await import("@/app/__tests__/setup");
  const { http, HttpResponse } = await import("msw");
  const match = { time: "2026-11-24T10:01:00Z", line: { name: "U2", direction: "Pankow" } };
  server.use(http.get("https://transit.hereapi.com/v8/departures", () =>
    HttpResponse.json([{ time: "2026-11-24T10:00:00Z", line: null }, match])
  ));
  const response = await GET(new Request("https://example.test/api/departures?stopId=s&lineName=U2&direction=Pankow"), workerContext);
  expect(response.status).toBe(200);
  expect(await response.json()).toEqual([match]);
});

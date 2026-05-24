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

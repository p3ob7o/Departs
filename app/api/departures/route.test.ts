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
      http.get("https://transit.hereapi.com/v8/boards", () => {
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

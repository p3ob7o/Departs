// @vitest-environment node
import { describe, it, expect } from "vitest";
import { workerContext } from "@/app/__tests__/setup";
import { GET } from "@/spacefast/functions/api/directions";

describe("GET /api/directions", () => {
  it("returns 400 when from is missing", async () => {
    const request = new Request(
      "http://localhost/api/directions?to=52.52,13.405"
    );
    const response = await GET(request, workerContext);

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.error).toBeDefined();
  });

  it("returns 400 when to is missing", async () => {
    const request = new Request(
      "http://localhost/api/directions?from=52.5195,13.4"
    );
    const response = await GET(request, workerContext);

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.error).toBeDefined();
  });

  it("returns 400 when coordinates are invalid", async () => {
    const request = new Request(
      "http://localhost/api/directions?from=abc,def&to=52.52,13.405"
    );
    const response = await GET(request, workerContext);

    expect(response.status).toBe(400);
  });

  it("returns 400 when coordinates are non-finite", async () => {
    const request = new Request(
      "http://localhost/api/directions?from=Infinity,13.4&to=52.52,13.405"
    );
    const response = await GET(request, workerContext);

    expect(response.status).toBe(400);
  });

  it.each([",13.4", "52.5,", " ,13.4"])("rejects missing coordinate components in %s", async (from) => {
    const response = await GET(new Request(`http://localhost/api/directions?${new URLSearchParams({ from, to: "52.52,13.405" })}`), workerContext);
    expect(response.status).toBe(400);
  });

  it("proxies request to Mapbox Directions API", async () => {
    const request = new Request(
      "http://localhost/api/directions?from=52.5195,13.4&to=52.52,13.405"
    );
    const response = await GET(request, workerContext);

    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body.geometry).toBeDefined();
    expect(body.duration).toBeGreaterThan(0);
  });

  it("sets cache headers for 1 hour", async () => {
    const request = new Request(
      "http://localhost/api/directions?from=52.5195,13.4&to=52.52,13.405"
    );
    const response = await GET(request, workerContext);

    expect(response.headers.get("Cache-Control")).toContain("max-age=3600");
  });

  it("returns 500 when Mapbox API fails", async () => {
    const { server } = await import("@/app/__tests__/setup");
    const { http, HttpResponse } = await import("msw");

    server.use(
      http.get("https://api.mapbox.com/directions/v5/mapbox/walking/*", () => {
        return HttpResponse.json({ error: "Unauthorized" }, { status: 401 });
      })
    );

    const request = new Request(
      "http://localhost/api/directions?from=52.5195,13.4&to=52.52,13.405"
    );
    const response = await GET(request, workerContext);

    expect(response.status).toBe(500);
  });

  it.each([[], [[13]], [[13, 52], [14]], [[13, 52], [14, 91]]].map((coordinates) => ({ coordinates })))("rejects malformed route coordinates $coordinates", async ({ coordinates }) => {
    const { server } = await import("@/app/__tests__/setup");
    const { http, HttpResponse } = await import("msw");
    server.use(http.get("https://api.mapbox.com/directions/v5/mapbox/walking/*", () => HttpResponse.json({ routes: [{
      geometry: { type: "LineString", coordinates }, duration: 120, distance: 80,
    }] })));
    const response = await GET(new Request("http://localhost/api/directions?from=52,13&to=52.1,13.1"), workerContext);
    expect(response.status).toBe(502);
  });

  it("returns 502 when Mapbox returns no routes", async () => {
    const { server } = await import("@/app/__tests__/setup");
    const { http, HttpResponse } = await import("msw");

    server.use(
      http.get("https://api.mapbox.com/directions/v5/mapbox/walking/*", () => {
        return HttpResponse.json({ routes: [] });
      })
    );

    const request = new Request(
      "http://localhost/api/directions?from=52.5195,13.4&to=52.52,13.405"
    );
    const response = await GET(request, workerContext);

    expect(response.status).toBe(502);
    const body = await response.json();
    expect(body.error).toBe("No walking route found");
  });
});

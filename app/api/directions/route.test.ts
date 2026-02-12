import { describe, it, expect } from "vitest";
import { GET } from "@/app/api/directions/route";

describe("GET /api/directions", () => {
  it("returns 400 when from is missing", async () => {
    const request = new Request(
      "http://localhost/api/directions?to=52.52,13.405"
    );
    const response = await GET(request);

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.error).toBeDefined();
  });

  it("returns 400 when to is missing", async () => {
    const request = new Request(
      "http://localhost/api/directions?from=52.5195,13.4"
    );
    const response = await GET(request);

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.error).toBeDefined();
  });

  it("returns 400 when coordinates are invalid", async () => {
    const request = new Request(
      "http://localhost/api/directions?from=abc,def&to=52.52,13.405"
    );
    const response = await GET(request);

    expect(response.status).toBe(400);
  });

  it("proxies request to Mapbox Directions API", async () => {
    const request = new Request(
      "http://localhost/api/directions?from=52.5195,13.4&to=52.52,13.405"
    );
    const response = await GET(request);

    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body.geometry).toBeDefined();
    expect(body.duration).toBeGreaterThan(0);
  });

  it("sets cache headers for 1 hour", async () => {
    const request = new Request(
      "http://localhost/api/directions?from=52.5195,13.4&to=52.52,13.405"
    );
    const response = await GET(request);

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
    const response = await GET(request);

    expect(response.status).toBe(500);
  });
});

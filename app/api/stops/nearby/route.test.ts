import { describe, it, expect, vi } from "vitest";
import { GET } from "@/app/api/stops/nearby/route";

describe("GET /api/stops/nearby", () => {
  it("returns 400 when lat is missing", async () => {
    const request = new Request("http://localhost/api/stops/nearby?lon=13.405");
    const response = await GET(request);

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.error).toBeDefined();
  });

  it("returns 400 when lon is missing", async () => {
    const request = new Request("http://localhost/api/stops/nearby?lat=52.52");
    const response = await GET(request);

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.error).toBeDefined();
  });

  it("returns 400 when lat is not a valid number", async () => {
    const request = new Request(
      "http://localhost/api/stops/nearby?lat=abc&lon=13.405"
    );
    const response = await GET(request);

    expect(response.status).toBe(400);
  });

  it("proxies request to HERE stations API", async () => {
    const request = new Request(
      "http://localhost/api/stops/nearby?lat=52.52&lon=13.405"
    );
    const response = await GET(request);

    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body).toHaveLength(3);
  });

  it("sets cache headers for 24 hours", async () => {
    const request = new Request(
      "http://localhost/api/stops/nearby?lat=52.52&lon=13.405"
    );
    const response = await GET(request);

    expect(response.headers.get("Cache-Control")).toContain("max-age=86400");
  });

  it("returns 500 when HERE API fails", async () => {
    // Override handler to simulate failure
    const { server } = await import("@/app/__tests__/setup");
    const { http, HttpResponse } = await import("msw");

    server.use(
      http.get("https://transit.hereapi.com/v8/stations", () => {
        return HttpResponse.json({ error: "Service unavailable" }, { status: 503 });
      })
    );

    const request = new Request(
      "http://localhost/api/stops/nearby?lat=52.52&lon=13.405"
    );
    const response = await GET(request);

    expect(response.status).toBe(500);
  });
});

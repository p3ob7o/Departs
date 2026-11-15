// @vitest-environment node
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

  it.each(["Infinity,13", "91,13", "52,181", " ,13"])("rejects invalid coordinates %s before calling HERE", async (value) => {
    const [lat, lon] = value.split(",");
    const spy = vi.spyOn(global, "fetch");
    const response = await GET(new Request(`http://localhost/api/stops/nearby?${new URLSearchParams({ lat, lon })}`));
    expect(response.status).toBe(400);
    expect(spy).not.toHaveBeenCalled();
    spy.mockRestore();
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

  it.each([undefined, "800", "1600"])("passes the bounded search radius %s to HERE", async (radius) => {
    const { server } = await import("@/app/__tests__/setup");
    const { http, HttpResponse } = await import("msw");
    let requestedArea: string | null = null;
    server.use(http.get("https://transit.hereapi.com/v8/stations", ({ request }) => {
      const params = new URL(request.url).searchParams;
      requestedArea = params.get("in");
      expect(params.get("maxPlaces")).toBe("50");
      return HttpResponse.json({ stations: [] });
    }));
    const query = new URLSearchParams({ lat: "48.2", lon: "16.35" });
    if (radius !== undefined) query.set("radius", radius);
    const response = await GET(new Request(`http://localhost/api/stops/nearby?${query}`));
    expect(response.status).toBe(200);
    expect(requestedArea).toBe(`48.2,16.35;r=${radius ?? "400"}`);
  });

  it.each(["", " ", "0", "-1", "99", "2001", "400.5", "Infinity", "abc"])("rejects invalid radius %s without a provider call", async (radius) => {
    const spy = vi.spyOn(global, "fetch");
    const query = new URLSearchParams({ lat: "48.2", lon: "16.35", radius });
    const response = await GET(new Request(`http://localhost/api/stops/nearby?${query}`));
    expect(response.status).toBe(400);
    expect(spy).not.toHaveBeenCalled();
    spy.mockRestore();
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

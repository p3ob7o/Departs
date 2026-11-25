import { expect, it } from "vitest";
import { http, HttpResponse } from "msw";
import { server } from "./setup";
import { GET as root } from "@/spacefast/functions/index";
import { GET as nearby } from "@/spacefast/functions/api/stops/nearby";
import { GET as departures } from "@/spacefast/functions/api/departures";
import { GET as directions } from "@/spacefast/functions/api/directions";

const env = { HERE_API_KEY: "worker-here", MAPBOX_SECRET_TOKEN: "worker-mapbox" };

it("serves the plain-text root", async () => {
  const response = root();
  expect(response.headers.get("cache-control")).toBe("public, max-age=3600");
  expect(await response.text()).toBe("Departs is now an iOS app.\n");
});

it("uses the worker bindings and caches only nearby stops and walking routes", async () => {
  const credentials: (string | null)[] = [];
  server.use(
    http.get("https://transit.hereapi.com/v8/:resource", ({ request }) => {
      credentials.push(new URL(request.url).searchParams.get("apiKey"));
      return HttpResponse.json({ stations: [], boards: [] });
    }),
    http.get("https://api.mapbox.com/directions/v5/mapbox/walking/*", ({ request }) => {
      credentials.push(new URL(request.url).searchParams.get("access_token"));
      return HttpResponse.json({ routes: [{
        duration: 10, distance: 12, geometry: { type: "LineString", coordinates: [[1, 2], [2, 3]] },
      }] });
    }),
  );
  const responses = [
    await nearby(new Request("https://example.test/api/stops/nearby?lat=1&lon=2"), { env }),
    await departures(new Request("https://example.test/api/departures?stopIds=a,b"), { env }),
    await directions(new Request("https://example.test/api/directions?from=1,2&to=2,3"), { env }),
  ];
  expect(credentials).toEqual([env.HERE_API_KEY, env.HERE_API_KEY, env.MAPBOX_SECRET_TOKEN]);
  expect(responses.map(response => response.status)).toEqual([200, 200, 200]);
  expect(responses.map(response => response.headers.get("cache-control"))).toEqual([
    "public, max-age=86400", "no-store", "public, max-age=3600",
  ]);
  expect(await responses[0].json()).toEqual([]);
  expect(await responses[1].json()).toMatchObject({ boards: [], missing: ["a", "b"] });
  expect(await responses[2].json()).toMatchObject({ duration: 10, distance: 12 });
});

it.each([
  ["stopId=a&lineName=13A&direction=Centre", 200],
  ["stopId=a&lineName=13A", 400],
  ["stopIds=a,", 400],
])("never stores the departures response for %s", async (query, status) => {
  const response = await departures(new Request(`https://example.test/api/departures?${query}`), { env });
  expect(response.status).toBe(status);
  expect(response.headers.get("cache-control")).toBe("no-store");
});

it("keeps the batch 502 and single-stop 500 when HERE rejects the worker key", async () => {
  server.use(http.get("https://transit.hereapi.com/v8/departures", () =>
    new HttpResponse(null, { status: 401 })
  ));
  const batch = await departures(new Request("https://example.test/api/departures?stopIds=a"), { env });
  const single = await departures(new Request("https://example.test/api/departures?stopId=a&lineName=13A&direction=Centre"), { env });
  expect(batch.status).toBe(502);
  expect(single.status).toBe(500);
  expect(batch.headers.get("cache-control")).toBe("no-store");
  expect(single.headers.get("cache-control")).toBe("no-store");
  expect(await batch.json()).toEqual({ error: "Failed to fetch departures" });
  expect(await single.json()).toEqual({ error: "Failed to fetch departures" });
});

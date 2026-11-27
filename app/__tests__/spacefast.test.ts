import { expect, it } from "vitest";
import { http, HttpResponse } from "msw";
import { server } from "./setup";
import { GET as root } from "@/spacefast/functions/index";
import { GET as nearby } from "@/spacefast/functions/api/stops/nearby";
import { GET as departures } from "@/spacefast/functions/api/departures";

const env = { HERE_API_KEY: "worker-here" };

it("serves the plain-text root", async () => {
  const response = root();
  expect(response.headers.get("cache-control")).toBe("public, max-age=3600");
  expect(await response.text()).toBe("Departs is now an iOS app.\n");
});

it("uses the HERE binding for both transit endpoints and caches only nearby stops", async () => {
  const credentials: (string | null)[] = [];
  server.use(
    http.get("https://transit.hereapi.com/v8/:resource", ({ request }) => {
      credentials.push(new URL(request.url).searchParams.get("apiKey"));
      return HttpResponse.json({ stations: [], boards: [] });
    }),
  );
  const responses = [
    await nearby(new Request("https://example.test/api/stops/nearby?lat=1&lon=2"), { env }),
    await departures(new Request("https://example.test/api/departures?stopIds=a,b"), { env }),
  ];
  expect(credentials).toEqual([env.HERE_API_KEY, env.HERE_API_KEY]);
  expect(responses.map(response => response.status)).toEqual([200, 200]);
  expect(responses.map(response => response.headers.get("cache-control"))).toEqual([
    "public, max-age=86400", "no-store",
  ]);
  expect(await responses[0].json()).toEqual([]);
  expect(await responses[1].json()).toMatchObject({ boards: [], missing: ["a", "b"] });
});

it.each([
  ["stopId=a", 200],
  ["stopId=a&groupBy=line", 200],
  ["stopId=a&lineName=13A&direction=Centre", 200],
  ["stopId=a&lineName=13A", 400],
  ["stopIds=a,", 400],
])("never stores the departures response for %s", async (query, status) => {
  const response = await departures(new Request(`https://example.test/api/departures?${query}`), { env });
  expect(response.status).toBe(status);
  expect(response.headers.get("cache-control")).toBe("no-store");
});

it.each([
  ["stopIds=a", 502],
  ["stopId=a", 500],
  ["stopId=a&lineName=13A&direction=Centre", 500],
])("keeps the uncached provider error for %s", async (query, status) => {
  server.use(http.get("https://transit.hereapi.com/v8/departures", () =>
    new HttpResponse(null, { status: 401 })
  ));
  const response = await departures(new Request(`https://example.test/api/departures?${query}`), { env });
  expect(response.status).toBe(status);
  expect(response.headers.get("cache-control")).toBe("no-store");
  expect(await response.json()).toEqual({ error: "Failed to fetch departures" });
});

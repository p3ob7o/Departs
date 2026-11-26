// @vitest-environment node
import { afterEach, describe, expect, it, vi } from "vitest";
import { http, HttpResponse } from "msw";
import { server, workerContext } from "@/app/__tests__/setup";
import { GET } from "@/spacefast/functions/api/departures";

const upstream = "https://transit.hereapi.com/v8/departures";
// IDs only, derived from the 16 November Vienna capture. No raw responses.
const sampleIDs = ["77704_312", "77704_313", "77704_311", "77704_310", "77704_741", "77704_739",
  "77704_5045", "77704_4130", "77704_1506", "77704_5044", "77704_3231", "77704_3233",
  "77704_4129", "77704_5092", "77704_1507", "77704_953", "77704_3232"];
const departure = (minute: number, name = "13A", headsign = "Wien Skodagasse") => ({
  time: `2026-11-16T12:${String(minute).padStart(2, "0")}:00Z`,
  transport: { name, headsign, mode: "bus" },
});
const board = (id: string, departures: (ReturnType<typeof departure> & { rtTime?: string })[] = [departure(5), departure(10), departure(15), departure(20)]) => ({ place: { id }, departures });
const batch = (ids: string[]) => GET(new Request(`https://departs.test/api/departures?${new URLSearchParams({ stopIds: ids.join(",") })}`), workerContext);

afterEach(() => { vi.restoreAllMocks(); vi.useRealTimers(); });

describe("batched departures", () => {
  it("returns all 17 sample platforms in one upstream request, matching the first two legacy grouped departures", async () => {
    const requests: URL[] = [];
    server.use(http.get(upstream, ({ request }) => {
      const url = new URL(request.url); requests.push(url);
      return HttpResponse.json({ boards: url.searchParams.get("ids")!.split(",").reverse().map((id) => board(id)) });
    }));
    const response = await batch(sampleIDs);
    const body = await response.json();
    expect(response.status).toBe(200);
    expect(requests).toHaveLength(1);
    expect(requests[0].searchParams.get("maxPerTransport")).toBe("2");
    expect(requests[0].searchParams.get("maxPerBoard")).toBe("50");
    expect(body.boards.map((item: { stopId: string }) => item.stopId)).toEqual(sampleIDs);
    expect(body.missing).toEqual([]);
    for (const item of body.boards) {
      const legacy = await GET(new Request(`https://departs.test/api/departures?stopId=${item.stopId}&groupBy=line`), workerContext);
      const grouped = await legacy.json();
      expect(item.groups).toEqual(grouped.groups.map((group: { departures: unknown[] }) => ({ ...group, departures: group.departures.slice(0, 2) })));
    }
    expect(requests.slice(1).every((url) => url.searchParams.get("maxPerTransport") === "4")).toBe(true);
  });

  it.each([1, 50])("accepts %i IDs in one call", async (count) => {
    let calls = 0;
    const ids = Array.from({ length: count }, (_, i) => `stop-${i}`);
    server.use(http.get(upstream, ({ request }) => {
      calls++;
      expect(new URL(request.url).searchParams.get("ids")).toBe(ids.join(","));
      return HttpResponse.json({ boards: ids.map((id) => board(id)) });
    }));
    const response = await batch(ids);
    expect(response.status).toBe(200);
    expect((await response.json()).boards).toHaveLength(count);
    expect(calls).toBe(1);
  });

  it.each(["", ",", "a,", ",a", "a, ,b", Array.from({ length: 51 }, (_, i) => `${i}`).join(",")])("rejects an invalid list (%s) without calling HERE", async (ids) => {
    let calls = 0;
    server.use(http.get(upstream, () => { calls++; return HttpResponse.json({ boards: [] }); }));
    expect((await GET(new Request(`https://departs.test/api/departures?${new URLSearchParams({ stopIds: ids })}`), workerContext)).status).toBe(400);
    expect(calls).toBe(0);
  });

  it.each(["stopId=a", "lineName=13A&direction=Centre", "direction=Centre", "groupBy=line", "stopIds=b"])("rejects ambiguous batch parameters: %s", async (extra) => {
    expect((await GET(new Request(`https://departs.test/api/departures?stopIds=a&${extra}`), workerContext)).status).toBe(400);
  });

  it("normalizes repeated IDs while keeping request order", async () => {
    server.use(http.get(upstream, ({ request }) => {
      expect(new URL(request.url).searchParams.get("ids")).toBe("a,b");
      return HttpResponse.json({ boards: [board("b"), board("a")] });
    }));
    const body = await (await batch([" a ", "b", "a"])).json();
    expect(body.boards.map((item: { stopId: string }) => item.stopId)).toEqual(["a", "b"]);
  });

  it("distinguishes an empty board from a missing platform and ignores unrequested boards", async () => {
    server.use(http.get(upstream, () => HttpResponse.json({ boards: [board("b", []), board("unrequested"), board("a")] })));
    const body = await (await batch(["a", "b", "missing"])).json();
    expect(body.missing).toEqual(["missing"]);
    expect(body.boards.map((item: { stopId: string }) => item.stopId)).toEqual(["a", "b"]);
    expect(body.boards[1].groups).toEqual([]);
  });

  it("keeps every requested ID missing when HERE returns no boards", async () => {
    server.use(http.get(upstream, () => HttpResponse.json({ boards: [] })));
    const body = await (await batch(["a", "b"])).json();
    expect(body).toMatchObject({ boards: [], missing: ["a", "b"] });
  });

  it("uses departure metadata, groups by mode/name/destination and sorts predicted times", async () => {
    server.use(http.get(upstream, () => HttpResponse.json({ boards: [board("a", [
      { ...departure(1), rtTime: "2026-11-16T12:12:00Z" }, departure(2), departure(3),
      departure(4, "13A", "Wien Hauptbahnhof"), departure(6, "unlisted", "Wien Centre"),
      { ...departure(5), transport: { name: "13A", headsign: "Wien Skodagasse", mode: "lightRail" } },
    ])] })));
    const { boards } = await (await batch(["a"])).json();
    expect(boards[0].groups).toHaveLength(4);
    expect(boards[0].groups[0].departures.map((dep: { time: string }) => dep.time)).toEqual([
      "2026-11-16T12:02:00Z", "2026-11-16T12:03:00Z",
    ]);
    expect(boards[0].groups.map((group: { line: { type: string } }) => group.line.type)).toEqual(["bus", "bus", "tram", "bus"]);
  });

  it("counts freshness from the provider request, not the later response receipt", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2026-11-16T12:00:00Z"));
    server.use(http.get(upstream, () => {
      vi.setSystemTime(new Date("2026-11-16T12:00:10Z"));
      return HttpResponse.json({ boards: [board("a")] });
    }));
    const response = await batch(["a"]);
    expect((await response.json()).fetchedAt).toBe("2026-11-16T12:00:00.000Z");
    expect(response.headers.get("Cache-Control")).toBe("no-store");
  });

  it("retries a 503 once and dates the successful provider call", async () => {
    const log = vi.spyOn(console, "error").mockImplementation(() => {});
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2026-11-16T12:00:00Z"));
    let calls = 0;
    server.use(http.get(upstream, () => {
      if (++calls === 1) { vi.setSystemTime(new Date("2026-11-16T12:00:03Z")); return new HttpResponse(null, { status: 503 }); }
      return HttpResponse.json({ boards: [board("a")] });
    }));
    const response = await batch(["a"]);
    expect(response.status).toBe(200);
    expect((await response.json()).fetchedAt).toBe("2026-11-16T12:00:03.000Z");
    expect(calls).toBe(2);
    expect(log).not.toHaveBeenCalled();
  });

  it("retries a network failure once and recovers", async () => {
    let calls = 0;
    server.use(http.get(upstream, () => ++calls === 1 ? HttpResponse.error() : HttpResponse.json({ boards: [board("a")] })));
    expect((await batch(["a"])).status).toBe(200);
    expect(calls).toBe(2);
  });

  it.each([503, 401, 429])("logs one sanitized upstream status and returns 502 after HTTP %i", async (status) => {
    const log = vi.spyOn(console, "error").mockImplementation(() => {});
    let calls = 0;
    server.use(http.get(upstream, ({ request }) => { calls++; return new HttpResponse(request.url, { status }); }));
    const response = await batch(["a"]);
    expect(response.status).toBe(502);
    expect(calls).toBe(status >= 500 ? 2 : 1);
    expect(log).toHaveBeenCalledExactlyOnceWith("departures upstream failure", { errorClass: "HTTPError", status });
    expect(JSON.stringify(log.mock.calls)).not.toMatch(/test-here-api-key|apiKey|https:/);
    expect(await response.json()).toEqual({ error: "Failed to fetch departures" });
  });

  it("logs one error class after two network failures, without leaking the request URL", async () => {
    const log = vi.spyOn(console, "error").mockImplementation(() => {});
    let calls = 0;
    server.use(http.get(upstream, () => { calls++; return HttpResponse.error(); }));
    expect((await batch(["a"])).status).toBe(502);
    expect(calls).toBe(2);
    expect(log).toHaveBeenCalledExactlyOnceWith("departures upstream failure", { errorClass: "NetworkError" });
    expect(JSON.stringify(log.mock.calls)).not.toMatch(/test-here-api-key|apiKey|https:/);
  });

  it.each([{ nope: [] }, { boards: [null] }, { boards: [{ place: { id: "a" } }] }])("rejects a malformed upstream payload instead of reporting an empty stop", async (payload) => {
    const log = vi.spyOn(console, "error").mockImplementation(() => {});
    server.use(http.get(upstream, () => HttpResponse.json(payload)));
    expect((await batch(["a"])).status).toBe(502);
    expect(log).toHaveBeenCalledExactlyOnceWith("departures upstream failure", { errorClass: "InvalidResponse" });
  });

  it("does not retry invalid JSON or log the response contents", async () => {
    const log = vi.spyOn(console, "error").mockImplementation(() => {});
    let calls = 0;
    server.use(http.get(upstream, ({ request }) => { calls++; return new HttpResponse(request.url); }));
    expect((await batch(["a"])).status).toBe(502);
    expect(calls).toBe(1);
    expect(log).toHaveBeenCalledExactlyOnceWith("departures upstream failure", { errorClass: "InvalidResponse" });
  });

  it("retries a timeout once and logs only its fixed class", async () => {
    const log = vi.spyOn(console, "error").mockImplementation(() => {});
    const timeout = vi.spyOn(AbortSignal, "timeout").mockImplementation(() => AbortSignal.abort(new DOMException("sensitive upstream details", "TimeoutError")));
    expect((await batch(["a"])).status).toBe(502);
    expect(timeout).toHaveBeenCalledTimes(2);
    expect(log).toHaveBeenCalledExactlyOnceWith("departures upstream failure", { errorClass: "TimeoutError" });
  });
});

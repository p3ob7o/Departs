import { describe, it, expect, vi } from "vitest";
import { fetchNearbyStops, fetchDepartures, fetchDirections } from "@/app/lib/api";
import { nearbyStops } from "@/app/__tests__/fixtures/nearby-stops";
import { departures } from "@/app/__tests__/fixtures/departures";
import { walkingRoute } from "@/app/__tests__/fixtures/walking-route";

describe("api client", () => {
  describe("fetchNearbyStops", () => {
    it("fetches nearby stops from /api/stops/nearby", async () => {
      const result = await fetchNearbyStops(52.52, 13.405);

      expect(result).toEqual(nearbyStops);
    });

    it("passes lat and lon as query params", async () => {
      const spy = vi.spyOn(global, "fetch");
      await fetchNearbyStops(52.52, 13.405);

      expect(spy).toHaveBeenCalledWith(
        expect.stringContaining("/api/stops/nearby?lat=52.52&lon=13.405"), { signal: undefined }
      );
      spy.mockRestore();
    });

    it("throws on non-ok response", async () => {
      await expect(fetchNearbyStops(NaN, NaN)).rejects.toThrow();
    });
  });

  describe("fetchDepartures", () => {
    it("fetches departures from /api/departures", async () => {
      const result = await fetchDepartures("stop-1");

      expect(result).toMatchObject(departures);
      expect(result[0].line).toEqual({ name: "U2", direction: "Pankow", type: "subway" });
    });

    it("encodes stop IDs and sends the selected line and direction", async () => {
      const spy = vi.spyOn(global, "fetch");
      await fetchDepartures("stop/1?platform=A&B#1", { name: "U2", direction: "A & B" });
      const url = new URL(spy.mock.calls[0][0] as string, "http://localhost");
      expect(url.searchParams.get("stopId")).toBe("stop/1?platform=A&B#1");
      expect(url.searchParams.get("lineName")).toBe("U2");
      expect(url.searchParams.get("direction")).toBe("A & B");
      spy.mockRestore();
    });

    it("passes stopId as query param", async () => {
      const spy = vi.spyOn(global, "fetch");
      await fetchDepartures("stop-1");

      expect(spy).toHaveBeenCalledWith(
        expect.stringContaining("/api/departures?stopId=stop-1"), { signal: undefined }
      );
      spy.mockRestore();
    });
  });

  describe("fetchDirections", () => {
    it("fetches walking directions from /api/directions", async () => {
      const result = await fetchDirections(
        { lat: 52.5195, lon: 13.4 },
        { lat: 52.52, lon: 13.405 }
      );

      expect(result).toEqual(walkingRoute);
    });

    it("passes from and to as query params", async () => {
      const spy = vi.spyOn(global, "fetch");
      await fetchDirections(
        { lat: 52.5195, lon: 13.4 },
        { lat: 52.52, lon: 13.405 }
      );

      expect(spy).toHaveBeenCalledWith(
        expect.stringContaining("/api/directions?from=52.5195,13.4&to=52.52,13.405"), { signal: undefined }
      );
      spy.mockRestore();
    });
  });
});

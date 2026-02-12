import { describe, it, expect } from "vitest";
import { transformStations, transformDepartures } from "@/app/lib/transitProvider";
import hereStationsResponse from "@/app/__tests__/fixtures/here-stations-response.json";
import hereBoardsResponse from "@/app/__tests__/fixtures/here-boards-response.json";

describe("transitProvider", () => {
  describe("transformStations", () => {
    it("transforms HERE stations response to NearbyStop[]", () => {
      const result = transformStations(hereStationsResponse);

      expect(result).toHaveLength(3);
      expect(result[0]).toMatchObject({
        id: "stop-1",
        name: "Central Station",
        distance: 120,
      });
    });

    it("maps HERE transport modes to TransportType", () => {
      const result = transformStations(hereStationsResponse);

      expect(result[0].type).toBe("subway");
      expect(result[1].type).toBe("tram");
      expect(result[2].type).toBe("rail");
    });

    it("maps lightRail to tram", () => {
      const result = transformStations(hereStationsResponse);
      const tramStop = result.find((s) => s.name === "Market Square");

      expect(tramStop?.type).toBe("tram");
    });

    it("maps intercityTrain to rail", () => {
      const result = transformStations(hereStationsResponse);
      const railStop = result.find((s) => s.name === "Park Avenue");

      expect(railStop?.type).toBe("rail");
    });

    it("extracts line info with direction", () => {
      const result = transformStations(hereStationsResponse);

      expect(result[0].lines).toHaveLength(2);
      expect(result[0].lines[0]).toMatchObject({
        name: "U2",
        direction: "Pankow",
        type: "subway",
      });
    });

    it("converts lng to lon in location", () => {
      const result = transformStations(hereStationsResponse);

      expect(result[0].location).toEqual({ lat: 52.52, lon: 13.405 });
    });

    it("returns empty array for empty stations response", () => {
      const result = transformStations({ stations: [] });

      expect(result).toEqual([]);
    });
  });

  describe("transformDepartures", () => {
    it("transforms HERE boards response to Departure[]", () => {
      const result = transformDepartures(hereBoardsResponse);

      expect(result).toHaveLength(4);
    });

    it("sets realTime to false when no rtTime present", () => {
      const result = transformDepartures(hereBoardsResponse);

      expect(result[0].realTime).toBe(false);
      expect(result[0].delay).toBeNull();
    });

    it("sets realTime to true when rtTime is present", () => {
      const result = transformDepartures(hereBoardsResponse);

      expect(result[1].realTime).toBe(true);
    });

    it("calculates delay in seconds from time vs rtTime", () => {
      const result = transformDepartures(hereBoardsResponse);

      // Second departure: scheduled 10:12, actual 10:14 = 120s delay
      expect(result[1].delay).toBe(120);
    });

    it("sets delay to 0 when rtTime equals scheduled time", () => {
      const result = transformDepartures(hereBoardsResponse);

      // Fourth departure: scheduled 10:30, actual 10:30 = 0s delay
      expect(result[3].delay).toBe(0);
    });

    it("uses scheduled time as the departure time", () => {
      const result = transformDepartures(hereBoardsResponse);

      expect(result[0].time).toBe("2024-01-15T10:05:00+01:00");
    });
  });
});

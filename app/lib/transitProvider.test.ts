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

    it("preserves the same line and direction at separate stops", () => {
      const data = {
        stations: [
          {
            place: { id: "s1", name: "Stop A", location: { lat: 1, lng: 2 } },
            distance: 50,
            transports: [
              { mode: "lightRail", name: "49", headsign: "Hütteldorf", id: "t1" },
              { mode: "bus", name: "13A", headsign: "Hauptbahnhof", id: "t2" },
            ],
          },
          {
            place: { id: "s2", name: "Stop B", location: { lat: 1.1, lng: 2.1 } },
            distance: 80,
            transports: [
              { mode: "lightRail", name: "49", headsign: "Hütteldorf", id: "t3" },
            ],
          },
          {
            place: { id: "s3", name: "Stop C", location: { lat: 1.2, lng: 2.2 } },
            distance: 100,
            transports: [
              { mode: "lightRail", name: "49", headsign: "Ring/Volkstheater", id: "t4" },
              { mode: "bus", name: "13A", headsign: "Skodagasse", id: "t5" },
            ],
          },
        ],
      };

      const result = transformStations(data);

      expect(result).toHaveLength(3);
      expect(result[0].id).toBe("s1");
      expect(result[0].lines).toHaveLength(2);
      expect(result[1].id).toBe("s2");
      expect(result[1].lines).toEqual([
        expect.objectContaining({ name: "49", direction: "Hütteldorf" }),
      ]);
      expect(result[2].id).toBe("s3");
      expect(result[2].lines).toHaveLength(2);
    });

    it("keeps every line and direction on a stop", () => {
      const data = {
        stations: [
          {
            place: { id: "s1", name: "Stop A", location: { lat: 1, lng: 2 } },
            distance: 50,
            transports: [
              { mode: "subway", name: "17", headsign: "Alvik", id: "t1" },
              { mode: "subway", name: "17", headsign: "Skarpnäck", id: "t2" },
              { mode: "subway", name: "18", headsign: "Farsta strand", id: "t3" },
              { mode: "subway", name: "19", headsign: "Hagsätra", id: "t4" },
            ],
          },
        ],
      };

      const result = transformStations(data);

      expect(result).toHaveLength(1);
      expect(result[0].id).toBe("s1");
      expect(result[0].lines.map((line) => `${line.name}->${line.direction}`)).toEqual([
        "17->Alvik",
        "17->Skarpnäck",
        "18->Farsta strand",
        "19->Hagsätra",
      ]);
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

    it("preserves line metadata from HERE transport info", () => {
      const result = transformDepartures(hereBoardsResponse);

      expect(result[0].line).toEqual({
        name: "U2",
        direction: "Pankow",
        type: "subway",
      });
    });
  });
});

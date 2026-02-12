import type { NearbyStop } from "@/app/types";

export const nearbyStops: NearbyStop[] = [
  {
    id: "stop-1",
    name: "Central Station",
    type: "subway",
    lines: [
      { id: "line-u2", name: "U2", direction: "Pankow", type: "subway" },
      { id: "line-bus100", name: "Bus 100", direction: "Alexanderplatz", type: "bus" },
    ],
    location: { lat: 52.52, lon: 13.405 },
    distance: 120,
  },
  {
    id: "stop-2",
    name: "Market Square",
    type: "tram",
    lines: [
      { id: "line-m1", name: "Tram M1", direction: "Rosenthal", type: "tram" },
    ],
    location: { lat: 52.521, lon: 13.406 },
    distance: 85,
  },
  {
    id: "stop-3",
    name: "Park Avenue",
    type: "rail",
    lines: [
      { id: "line-re1", name: "RE1", direction: "Frankfurt (Oder)", type: "rail" },
    ],
    location: { lat: 52.519, lon: 13.404 },
    distance: 200,
  },
];

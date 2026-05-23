export type TransportType = "subway" | "tram" | "bus" | "rail";

export interface LineInfo {
  id: string;
  name: string;
  direction: string;
  type: TransportType;
}

export interface NearbyStop {
  id: string;
  name: string;
  type: TransportType;
  lines: LineInfo[];
  location: { lat: number; lon: number };
  distance: number;
}

export interface Departure {
  time: string;
  realTime: boolean;
  delay: number | null;
  line?: {
    name: string;
    direction: string;
    type: TransportType;
  };
}

export interface WalkingRoute {
  geometry: GeoJSON.LineString;
  duration: number;
  distance: number;
}

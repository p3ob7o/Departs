import type { NearbyStop, Departure, TransportType } from "@/app/types";

const modeMap: Record<string, TransportType> = {
  bus: "bus",
  privateBus: "bus",
  busRapid: "bus",
  subway: "subway",
  metro: "subway",
  lightRail: "tram",
  monorail: "tram",
  intercityTrain: "rail",
  interRegionalTrain: "rail",
  regionalTrain: "rail",
  cityTrain: "rail",
  highSpeedTrain: "rail",
};

function mapMode(mode: string): TransportType {
  return modeMap[mode] ?? "bus";
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function transformStations(data: any): NearbyStop[] {
  if (Array.isArray(data)) return data;

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const stops = (data.stations ?? []).map((station: any) => {
    const { place, distance, transports } = station;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const lines = (transports ?? []).map((t: any) => ({
      id: t.id,
      name: t.name,
      direction: t.headsign,
      type: mapMode(t.mode),
    }));

    return {
      id: place.id,
      name: place.name,
      type: lines[0]?.type ?? "bus",
      lines,
      location: { lat: place.location.lat, lon: place.location.lng },
      distance,
    };
  }).filter((stop: NearbyStop) => stop.lines.length > 0);

  // Deduplicate: for each line+direction combo, keep only the nearest stop
  const seen = new Set<string>();
  const deduped: NearbyStop[] = [];

  for (const stop of stops) {
    const uniqueLines = stop.lines.filter((line) => {
      const key = `${line.name}::${line.direction}`;
      return !seen.has(key);
    });

    if (uniqueLines.length === 0) continue;

    for (const line of uniqueLines) {
      seen.add(`${line.name}::${line.direction}`);
    }

    deduped.push({
      ...stop,
      lines: uniqueLines,
      type: uniqueLines[0].type,
    });
  }

  return deduped;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function transformDepartures(data: any): Departure[] {
  if (Array.isArray(data)) return data;

  const deps = data.boards?.[0]?.departures ?? [];
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return deps.map((dep: any) => {
    const hasRt = !!dep.rtTime;
    let delay: number | null = null;
    if (hasRt) {
      delay =
        (new Date(dep.rtTime).getTime() - new Date(dep.time).getTime()) / 1000;
    }
    return {
      time: dep.time,
      realTime: hasRt,
      delay,
    };
  });
}

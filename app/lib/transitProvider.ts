import type { Departure, LineInfo, NearbyStop, TransportType } from "@/app/types";

type HereTransport = {
  id?: string;
  mode?: string;
  name?: string;
  headsign?: string;
};

type HereStation = {
  place?: {
    id?: string;
    name?: string;
    location?: {
      lat?: number;
      lng?: number;
    };
  };
  distance?: number;
  transports?: HereTransport[];
};

type HereStationsResponse = {
  stations?: HereStation[];
};

type HereDeparture = {
  time?: string;
  rtTime?: string;
};

type HereBoard = {
  departures?: HereDeparture[];
};

type HereBoardsResponse = {
  boards?: HereBoard[];
};

function mapModeToTransportType(mode: string | undefined): TransportType {
  switch (mode) {
    case "subway":
    case "metro":
      return "subway";
    case "tram":
    case "lightRail":
      return "tram";
    case "rail":
    case "train":
    case "regionalTrain":
    case "intercityTrain":
    case "highSpeedTrain":
      return "rail";
    default:
      return "bus";
  }
}

function toLineInfo(transport: HereTransport): LineInfo {
  return {
    id: transport.id ?? `${transport.name ?? "line"}-${transport.headsign ?? "dir"}`,
    name: transport.name ?? "Unknown line",
    direction: transport.headsign ?? "",
    type: mapModeToTransportType(transport.mode),
  };
}

export function transformStations(data: HereStationsResponse): NearbyStop[] {
  if (!Array.isArray(data?.stations) || data.stations.length === 0) {
    return [];
  }

  return data.stations.map((station, index) => {
    const transports = Array.isArray(station.transports) ? station.transports : [];
    const lines = transports.map(toLineInfo);
    const primaryTransport = transports[0];

    return {
      id: station.place?.id ?? `stop-${index}`,
      name: station.place?.name ?? "Unknown stop",
      type: mapModeToTransportType(primaryTransport?.mode),
      lines,
      location: {
        lat: Number(station.place?.location?.lat ?? 0),
        lon: Number(station.place?.location?.lng ?? 0),
      },
      distance: Number(station.distance ?? 0),
    };
  });
}

function computeDelaySeconds(scheduled: string, realtime: string): number | null {
  const scheduledTs = Date.parse(scheduled);
  const realtimeTs = Date.parse(realtime);

  if (!Number.isFinite(scheduledTs) || !Number.isFinite(realtimeTs)) {
    return null;
  }

  return Math.round((realtimeTs - scheduledTs) / 1000);
}

export function transformDepartures(data: HereBoardsResponse): Departure[] {
  if (!Array.isArray(data?.boards) || data.boards.length === 0) {
    return [];
  }

  const allDepartures = data.boards.flatMap((board) =>
    Array.isArray(board.departures) ? board.departures : []
  );

  return allDepartures.slice(0, 4).map((departure) => {
    const scheduledTime = departure.time ?? departure.rtTime ?? "";
    const hasRealtime = typeof departure.rtTime === "string";
    const delay = hasRealtime
      ? computeDelaySeconds(scheduledTime, departure.rtTime as string)
      : null;

    return {
      time: scheduledTime,
      realTime: hasRealtime,
      delay,
    };
  });
}

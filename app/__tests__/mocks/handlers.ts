import { http, HttpResponse } from "msw";
import hereStationsResponse from "../fixtures/here-stations-response.json";
import hereBoardsResponse from "../fixtures/here-boards-response.json";

export const handlers = [
  http.get("https://transit.hereapi.com/v8/stations", () => {
    return HttpResponse.json(hereStationsResponse);
  }),

  http.get("https://transit.hereapi.com/v8/departures", () => {
    return HttpResponse.json(hereBoardsResponse);
  }),
];

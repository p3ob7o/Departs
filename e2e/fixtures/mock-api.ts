import type { Page } from "@playwright/test";

const hereStationsResponse = {
  stations: [
    {
      place: {
        type: "station",
        id: "stop-1",
        name: "Central Station",
        location: { lat: 52.52, lng: 13.405 },
      },
      distance: 120,
      transports: [
        { mode: "subway", name: "U2", headsign: "Pankow", id: "line-u2" },
      ],
    },
    {
      place: {
        type: "station",
        id: "stop-2",
        name: "Market Square",
        location: { lat: 52.521, lng: 13.406 },
      },
      distance: 85,
      transports: [
        { mode: "lightRail", name: "Tram M1", headsign: "Rosenthal", id: "line-m1" },
      ],
    },
  ],
};

const hereBoardsResponse = {
  boards: [
    {
      departures: [
        {
          time: "2024-01-15T10:05:00+01:00",
          transport: { mode: "subway", name: "U2", headsign: "Pankow" },
          agency: { name: "BVG" },
        },
        {
          time: "2024-01-15T10:12:00+01:00",
          rtTime: "2024-01-15T10:14:00+01:00",
          transport: { mode: "subway", name: "U2", headsign: "Pankow" },
          agency: { name: "BVG" },
        },
        {
          time: "2024-01-15T10:20:00+01:00",
          transport: { mode: "subway", name: "U2", headsign: "Pankow" },
          agency: { name: "BVG" },
        },
        {
          time: "2024-01-15T10:30:00+01:00",
          transport: { mode: "subway", name: "U2", headsign: "Pankow" },
          agency: { name: "BVG" },
        },
      ],
    },
  ],
};

const mapboxDirectionsResponse = {
  routes: [
    {
      geometry: {
        type: "LineString",
        coordinates: [
          [13.4, 52.5195],
          [13.405, 52.52],
        ],
      },
      duration: 145.2,
      distance: 120.5,
      legs: [{ summary: "", duration: 145.2, distance: 120.5, steps: [] }],
    },
  ],
  waypoints: [
    { name: "", location: [13.4, 52.5195] },
    { name: "Central Station", location: [13.405, 52.52] },
  ],
  code: "Ok",
};

export async function mockAPIs(page: Page) {
  await page.route("**/api/stops/nearby*", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(hereStationsResponse),
    })
  );

  await page.route("**/api/departures*", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(hereBoardsResponse),
    })
  );

  await page.route("**/api/directions*", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(mapboxDirectionsResponse),
    })
  );
}

export async function mockGeolocation(
  page: Page,
  coords = { latitude: 52.52, longitude: 13.405 }
) {
  await page.context().grantPermissions(["geolocation"]);
  await page.context().setGeolocation(coords);
}

export async function mockGeolocationDenied(page: Page) {
  await page.context().clearPermissions();
}

export async function mockNetworkError(page: Page) {
  await page.route("**/api/stops/nearby*", (route) =>
    route.fulfill({ status: 500, body: "Internal Server Error" })
  );
}

export async function mockEmptyStops(page: Page) {
  await page.route("**/api/stops/nearby*", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ stations: [] }),
    })
  );
}

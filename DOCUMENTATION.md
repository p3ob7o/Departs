# Departs implementation guide

Departs answers “What is leaving near me?” in a native iOS app. The browser client has been retired. The backend remains on Vercel because installed iOS builds depend on it.

## Native app

`ios/Departs/Departs/` contains SwiftUI views, observable view models, Codable models, an `APIService` actor, and a CoreLocation service. MapKit renders the map; system appearance controls light and dark styling. There are no accounts, application database, or third-party iOS dependencies.

The flow is:

1. Request the device's location and load stops within 400 metres.
2. Show nearby stops and their available lines/directions.
3. Select a stop and line, then request its departures and walking route in parallel.
4. Display up to four departures. A route failure does not hide an available departure board.

The API host is compiled into `Services/APIService.swift`. `URLComponents` encodes station IDs and line/direction parameters. The native `NearbyStop.distance` is optional and `LineInfo.id` is computed from the line name and direction. Previews using `PreviewData` must stay within `#if DEBUG`.

## Backend contract

Next.js route handlers proxy to HERE and Mapbox and normalize their data. Provider credentials are server environment variables. Keep these paths and response shapes compatible with installed iOS builds:

| Endpoint | Query | Response | Provider |
| --- | --- | --- | --- |
| `/api/stops/nearby` | `lat`, `lon` | Array of stops with `id`, `name`, `type`, `lines`, `location` and optional `distance` | HERE `/v8/stations` |
| `/api/departures` | `stopId`; optional paired `lineName`, `direction` | Array of departures with `time`, `realTime`, `delay` and optional line metadata | HERE `/v8/departures` |
| `/api/directions` | `from=lat,lon`, `to=lat,lon` | `{geometry, duration, distance}`; GeoJSON LineString, seconds, metres | Mapbox walking directions |

The station limit is 50 and the departure limit is four. Cache headers are 24 hours for nearby stops, 30 seconds for departures and one hour for directions. They do not trigger client refreshes. Do not assume every operator supplies realtime data.

The website root `/` returns a plain-text notice that Departs is now an iOS app. It performs no provider calls. React remains a Next.js runtime dependency, but no React pages, browser maps, geolocation hooks, or browser test suite remain.

## Development and verification

Use the commands in [AGENTS.md](AGENTS.md). The backend uses Vitest in Node with MSW intercepting external providers. Native tests live in `ios/Departs/DepartsTests/`. Mocked tests require no real keys; live backend calls require `HERE_API_KEY` and `MAPBOX_SECRET_TOKEN`.

Running the backend locally does not redirect `APIService`: the iOS app still uses the production host. Verify local HTTP responses separately and run native integration checks against the intended backend before distribution. Keep credentials out of test output.

Vercel deploys the backend from `main`. An iOS release is a separate Xcode/TestFlight/App Store operation. Deploying the backend does not update installed Swift code.

## Current priorities

See [the iOS roadmap](docs/ios-roadmap.md). The [dated audit](docs/reviews/2026-11-15-project-audit.md) records the state before the iOS-only decision. Designs under `docs/archive/web/` are historical and are not implementation requirements.

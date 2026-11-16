# Departs implementation guide

Departs answers “What is leaving near me?” in a native app requiring iOS 26 or later. The owner approved this minimum during the design implementation on 15 November 2026. iOS 27-only APIs require availability checks. The browser client has been retired. The backend remains on Vercel because installed iOS builds depend on it.

## Native app

`ios/Departs/Departs/` contains SwiftUI views, observable view models, Codable models, an `APIService` actor, and a CoreLocation service. MapKit renders the map; system appearance controls light and dark styling. There are no accounts, application database, or third-party iOS dependencies.

The flow is:

1. Restore saved stops, boards, and pinned directions synchronously, then request location without blocking navigation.
2. Find stops within 400 metres and load nearby pins plus the first three provider stop boards. Refresh pins and visible stop sections; keep a 25-second throttle unless the user explicitly refreshes. Departure and walking queues run independently, in batches of three each.
3. Show the next two times, live/scheduled labels, walking time, and leave-time advice when the board, location, and route are fresh enough.
4. Open a line for up to four departures and walking navigation. An app-owned `TransitSession` shares one `TransitStore` and `LocationService` across panes and windows, so opening a board reuses the answer already shown. Each window retains its own selection and sheets in one `NavigationSplitView`, which collapses in compact width.
5. Refresh visible panes on foreground return and every 30 seconds after the previous refresh completes, using one app-owned clock. Pull-to-refresh remains available. Saved times remain visible after failure, with an explicit saved-data label. List status includes the cycle's initial targets plus newly visible stops, so the status header cannot oscillate as its height changes.

Users can pin a stop plus direction, open it via App Shortcuts, choose a place using MapKit search, or expand the nearby radius to 800 then 1600 metres. A map is created only when requested. See [the native behavior guide](docs/ios-fast-answers.md) for freshness rules and verification.

The committed app target supports iPhone, including landscape. Text columns cap at 640 points; maps fill their containers and the selected-stop card scrolls independently in compact height. iPad runs exercise the shared layout foundation using a command-line device-family override, not committed iPad support. Mac, Vision Pro, scene configuration and required device capabilities are unchanged. Product support for other devices belongs to the separate adaptation plans.

The API host is compiled into `Services/APIService.swift`. `URLComponents` encodes station IDs and line/direction parameters. The native `NearbyStop.distance` is optional and `LineInfo.id` is computed from the line name and direction. Previews using `PreviewData` must stay within `#if DEBUG`.

## Backend contract

Next.js route handlers proxy to HERE and Mapbox and normalize their data. Provider credentials are server environment variables. Keep these paths and response shapes compatible with installed iOS builds:

| Endpoint | Query | Response | Provider |
| --- | --- | --- | --- |
| `/api/stops/nearby` | `lat`, `lon`; optional `radius` in metres (100–2000, default 400, backend PR #9) | Array of stops with `id`, `name`, `type`, `lines`, `location` and optional `distance` | HERE `/v8/stations` |
| `/api/departures` | `stopId`; optional paired `lineName`, `direction` | Array of departures with `time`, `realTime`, `delay` and optional line metadata | HERE `/v8/departures` |
| `/api/directions` | `from=lat,lon`, `to=lat,lon` | `{geometry, duration, distance}`; GeoJSON LineString, seconds, metres | Mapbox walking directions |

The station limit is 50 and the departure limit is four. Cache headers are 24 hours for nearby stops, 30 seconds for departures and one hour for directions. They do not trigger client refreshes. Do not assume every operator supplies realtime data.

The website root `/` returns a plain-text notice that Departs is now an iOS app. It performs no provider calls. React remains a Next.js runtime dependency, but no React pages, browser maps, geolocation hooks, or browser test suite remain.

## Development and verification

Use the commands in [AGENTS.md](AGENTS.md). The backend uses Vitest in Node with MSW intercepting external providers. Native tests live in `ios/Departs/DepartsTests/`. Mocked tests require no real keys; live backend calls require `HERE_API_KEY` and `MAPBOX_SECRET_TOKEN`.

Running the backend locally does not automatically redirect `APIService`. Set `DEPARTS_API_BASE_URL` in a Debug scheme for integration checks; release builds always use the production host unless an instance is explicitly constructed with a different base URL in code. `DEPARTS_DEFAULTS_SUITE` provides isolated preferences for Debug UI tests. Neither environment override is compiled into release builds. Keep credentials out of test output.

UI tests use `DEPARTS_TEST_VIEWPORT=1` only for exact container dimensions from 320 to 1200 points, driven by the local fixture server. That host is excluded from Release. Separate tests resize actual iPad windows; the iOS 27 simulator window manager imposes a 375-point minimum. Use separate derived-data directories for iPhone builds and iPad builds with `TARGETED_DEVICE_FAMILY="1,2"`.

Vercel deploys the backend from `main`. An iOS release is a separate Xcode/TestFlight/App Store operation. Deploying the backend does not update installed Swift code.

## Current priorities

See [the iOS roadmap](docs/ios-roadmap.md). The [dated audit](docs/reviews/2026-11-15-project-audit.md) records the state before the iOS-only decision. Designs under `docs/archive/web/` are historical and are not implementation requirements.

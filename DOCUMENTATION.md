# Departs implementation guide

Departs shows available transport nearby in a native iPhone and iPad app requiring iOS 26. iOS 27-only APIs require availability checks. The browser client is retired. Spacefast serves the native app.

## Native app

`ios/Departs/Departs/` contains SwiftUI views, observable state, Codable models, an `APIService` actor and CoreLocation. Maps use `UIViewRepresentable` MapKit wrappers and system appearance. There are no third-party iOS dependencies.

`DepartsApp` owns one `TransitSession`, shared store, location service and refresh clock. Each `ContentView` owns a navigation stack and sheets. iPhone uses a portrait stack. Departs offers one resizable iPad window in all orientations, stacking the map above the list in tall or narrow windows and dividing wide landscape windows equally. At accessibility sizes a stacked map scrolls with the list and a split map stays beside it. The Duo layout remains deferred. On 24 November 2026 the owner chose one window on iPad for now (O27). The one-window setting also applies to the iPhone Duo, and supporting several windows needs another decision. Mac and Vision Pro availability and required capabilities still need the owner’s decision.

Home restores a published snapshot, fetches nearby platforms and sends their IDs in one departure batch. Selection uses returned departures within 60 minutes, physical-stop distance and stable service identities. Membership and boards publish together, after interaction ends. Ticks and failures never reorder rows. Partial results retain existing membership. One walking route per listed physical stop runs independently of departures, at most three requests at once.

The line screen starts with home's two times, then fetches four for its exact platform and direction. A home refresh cannot overwrite a four-time board or mark a failed line request fresh. The route is visible immediately, and a system toolbar button opens Apple Maps walking mode. Pins, App Shortcuts and `departs://pin` links preserve their stored identities.

Fresh home times count from the provider timestamp, including CDN age. Failed or restored data shows clock times. Foreground refresh runs every 30 seconds with a 25-second recency throttle; explicit refresh bypasses it. See [native behavior](docs/ios-fast-answers.md) for the full rules and recovery states.

## Backend contract

The backend proxies HERE and Mapbox using server credentials. Starting with 1.3 (15), the app calls `https://api.departs.now`. Four entries in `spacefast/functions/` serve the root and three API paths.

| Endpoint | Query | Response |
| --- | --- | --- |
| `/api/stops/nearby` | `lat`, `lon`, optional `radius` 100–2000 m, default 400 | Up to 50 stops with `id`, `name`, `type`, `lines`, `location`, optional `distance` |
| `/api/departures` | `stopId`, optional paired `lineName`, `direction` | Up to four departure records. Both filters match exactly, except that a `+` and a space count as the same character: installed builds send a raw `+`, which the query parser reads as a space. A departure without a line, or with a provider name or direction that is not a string, never matches |
| `/api/departures` | `stopId`, `groupBy=line` | Compatible grouped response with `groups` and `complete` |
| `/api/departures` | `stopIds=a,b,c`, 1–50 IDs | `{fetchedAt, boards: [{stopId, groups}], missing}`; two departures per transport, 50 per platform |
| `/api/directions` | `from=lat,lon`, `to=lat,lon` | First walking route `{geometry, duration, distance}`, in seconds/metres |

The batch handler sends one provider request and retries once on network/5xx failure. On final failure it returns 502, which Spacefast has delivered as 500. Legacy calls keep their 500 failure contract. Logging contains only a fixed error class and optional numeric status, never the credential-bearing URL. `fetchedAt` is captured before the successful attempt; upstream `no-store` prevents a new timestamp wrapping a cached provider body.

HTTP cache lifetimes are 24 hours for stops and one hour for walks. All departures responses carry `Cache-Control: no-store`. They do not trigger native refreshes. Home has no fallback to an older backend. The provider can omit boards or cap away lines, and scheduled data does not imply realtime coverage.

The API root (`GET /`) returns a plain-text notice about the retired browser app without provider calls.

## Development and verification

Use [AGENTS.md](AGENTS.md) for commands and simulator rules. Vitest/MSW intercept external providers; native XCTest uses a small derived Vienna sample and a local fixture server. Live backend checks require provider credentials on the deployment, not embedded in the app.

Debug builds accept API, preferences and location-accuracy test overrides. `NSAllowsLocalNetworking` is included only by the Debug Info.plist preprocessor definition. Release contains no such overrides and loads production directly. Previews using `PreviewData` stay inside `#if DEBUG`.

Run native suites with the runtime pinned and derived data outside the repository. Complete first boot before testing. Dark appearance requires the iOS 26.2 simulator. The German pseudolocalization script copies and expands the catalog outside Git; it reuses that destination's derived data. No German localization ships.

Keep at most ten upright JPEG captures under 2 MB per phase PR. Export captures before deleting task-owned result bundles. Do not delete preexisting simulators, derived data or other users' outputs.

Fixtures, preview and production establish different things. Each PR records all three explicitly. See the [Phase 3 validation](docs/plans/ios-two-screens-phase-3-validation.md) and [Phase 0 provider results](docs/plans/ios-two-screens-phase-0-validation.md).

Spacefast builds the Functions from GitHub. See the [hosting guide](docs/backend-hosting.md) for release checks and rollback. Each stacked PR must reach `main` in sequence, with owner approval. Native releases ship separately.

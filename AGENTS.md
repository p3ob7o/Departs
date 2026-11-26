# Departs - Project Instructions

## Product scope

Departs is an iOS app. The owner chose on 15 November 2026 to retire the browser app and focus development on iOS. Do not restore the browser client or work toward web/iOS feature parity. The active roadmap is `docs/ios-roadmap.md`; `docs/archive/web/` contains historical designs.

Spacefast serves the iOS API at `https://api.departs.now/api/*`. Preserve the API contract. Server keys stay in the backend Space. The owner retired support for the Vercel host without forwarding.

## Commands

```bash
# iOS app (requires Xcode selected as the active developer directory)
xcodebuild -project ios/Departs/Departs.xcodeproj -scheme Departs -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -derivedDataPath /tmp/departs-iphone build
xcodebuild -project ios/Departs/Departs.xcodeproj -scheme Departs -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -derivedDataPath /tmp/departs-iphone test

# API backend
npm ci
npm run build:spacefast
npm run test:run
npm run test:coverage
npm run lint
```

## Environment variables

Spacefast supplies `HERE_API_KEY` for transit. Local backend tests mock HERE and use a dummy binding.

## Architecture

- SwiftUI with `@Observable` view models, iOS 26+, zero third-party iOS dependencies. Guard iOS 27-only APIs with availability checks.
- MapKit through `UIViewRepresentable` wrappers, system light/dark appearance.
- `DepartsApp` owns one `TransitSession`, containing the shared `TransitStore`, `LocationService` and foreground refresh clock. Each `ContentView` owns a `NavigationStack`, selection and the pinned-elsewhere sheet. On iPhone, home and line screens both place a square MapKit map above a short list. Home has no navigation bar: its square map starts under the status bar, stays centred on the rider and does not pan or zoom. At standard text sizes the line screen hides its bar too: its map has home's frame (`MapStrip`), its back, line, walk and pin sit under the map, and `EdgeSwipeBack` keeps the swipe from the left edge; at accessibility sizes it keeps the bar. The walk button offers Google Maps or Apple Maps when Google Maps is installed and remembers the choice in `TransitPersistence`. Where the status bar is at least 44 pt tall the map continues above the square to the top of the screen; iOS blurs it there, and MapKit keeps the square framed because it treats the safe area as margin. At accessibility text sizes the map is the square alone and scrolls away with the list. A badge on a home map label opens its line, or offers its directions when the line runs more than one way; a tap recognizer on the map hears the taps, because MapKit reports a selection only when it changes.
- The app supports iPhone in portrait and one resizable iPad window in all orientations. Supporting several windows requires another owner decision. On iPad choose stacked or equal side-by-side panes from the window dimensions as specified in the seventh amendment to `docs/plans/ios-two-screens.md`. The Duo remains deferred. Do not commit Mac or Vision Pro availability or change scene/capability settings without the owner's decision.
- Home requests every platform in the radius in one `stopIds` batch. `HomeSnapshot` publishes selection, ordering and boards together after interaction ends. Countdown ticks and failed requests never change membership or order. There is no per-line fallback or visibility-driven departure queue.
- List candidates come from returned departures within 60 minutes, not stop line metadata. Merge same-name platforms within 150 m; order physical stops by computed distance. A service appears once. See `docs/plans/ios-two-screens.md` for the nearest-stop and second-direction rule.
- Home and line share up to three active on-device MapKit calculations across refreshes. Identical requests share a calculation. Walks run independently of departures. While location access is denied or restricted, the walking service starts no calculation, cancels pending work, and discards route results. Active calculations time out after 12 seconds. Walks cancel when their origin is superseded, their platform is no longer shown, or the last window becomes inactive. Active windows restore demand on return, and selected platforms go ahead of queued home walks. The store reuses a walk to the same platform for ten minutes within 40 m of the origin. The MapKit service reuses an exact origin and destination for one hour and holds at most 32 routes in the app session, evicting the oldest insertion first. The line screen uses its own platform and four-departure request. Maps load immediately without blocking rows.
- App Intents expose pinned stop/direction entities through Shortcuts. Keep their stable identities independent of provider ordering.
- `APIService` is an actor using URLSession async/await.
- iOS structure: `Models/`, `Services/`, `ViewModels/`, `Views/`, `Utilities/`, `Preview Content/`.
- iOS `NearbyStop.distance` is optional; `LineInfo.id` is computed from `name::direction` because provider IDs are not consistently present.
- Wrap previews that use `PreviewData` in `#if DEBUG`: Preview Content is excluded from release builds.
- Spacefast routes requests to three entries in `spacefast/functions/`. The root returns the plain-text browser retirement notice. The nearby stops and departures entries call handlers in `app/lib/`.
- `@/*` maps to the repository root. `app/types.ts` describes the backend transit response shapes.

## Testing and workflow

- Backend: Vitest in Node, MSW mocks only external HERE calls, fixtures in `app/__tests__/fixtures/`.
- Native: unit XCTest in `ios/Departs/DepartsTests/`, UI flows with an in-process fixture HTTP server in `ios/Departs/DepartsUITests/`. The shared scheme runs both. Use normal simulator signing so App Intents can register correctly.
- For backend changes run `npm ci`, `npm run test:run`, `npm run test:coverage`, `npm run lint`, `npx tsc --noEmit` and `npm run build:spacefast` locally. For HTTP checks, open the PR’s **Spacefast Builds** check details and select the version for the PR head. Public access covers the live address only. Version and branch preview addresses return HTTP 403 (`access_denied`) to anonymous requests unless a share grant targets that version or branch. The owner decides how to provide access for the [four rider requests](docs/backend-hosting.md#check-what-a-rider-receives).
- Run native tests/build for native changes. Validate live data against the production API after deployment; test UI behavior in the iOS app.
- After implementing a change, commit, push and open or update its PR. Record which checks ran and distinguish local/preview verification from production verification.
- Preserve historical release records and archived web designs.

## External APIs

- HERE Transit v8: `/v8/stations` for nearby stops and `/v8/departures` for departures. Encode stop IDs using URL query parameters.
- Search radius: the app always asks for 400 metres around the rider, up to 50 stops. It has no wider search and no place search. The backend still accepts an optional radius of 100–2000 metres for installed builds. `stopId` plus optional paired `lineName` and `direction` returns up to four departures; `groupBy=line` stays compatible with installed builds. Additive `stopIds=a,b` accepts 1–50 IDs, asks for two departures per transport, and returns `{fetchedAt, boards, missing}`. Home freshness uses `fetchedAt`, including CDN age.
- MapKit supplies a single walking route on the device.
- Cache headers do not make the native client refresh automatically.

## iOS simulator

```bash
xcrun simctl location <SIMULATOR_UUID> set 48.20134,16.34941
xcrun simctl privacy <SIMULATOR_UUID> grant location-always app.departs.Departs
```

Boot new simulators fully with `xcrun simctl bootstatus <SIMULATOR_UUID> -b` before testing. Pin the OS because simulator names repeat. Use iOS 26.2 for dark appearance; iOS 27.0 did not apply it in testing. US units need `-AppleMeasurementUnits Inches -AppleMetricUnits NO` in addition to `-AppleLocale en_US`. Reuse one derived-data directory per destination, outside the repository. Export only a curated set of upright JPEGs, at most ten and under 2 MB per PR, then delete the result bundles. Delete only outputs and simulators created for the task; leave the owner's booted iPhone 17e alone.

`NSAllowsLocalNetworking` and the API, preferences, location-accuracy and walking-route test overrides exist only in Debug. Release must load production directly. Check fixtures, preview and production separately in each PR; fixture success does not establish provider coverage.

## Deployment

Follow `docs/backend-hosting.md` for the Spacefast GitHub build, cutover checklist and pinned release fallback. Native changes require a separate iOS build and distribution through TestFlight/App Store. Each stacked phase must reach `main` in order, retargeting after its base merges. Merges, deployments, version preparation and uploads need the owner's approval.

# Departs - Project Instructions

## Product scope

Departs is an iOS app. The owner chose on 15 November 2026 to retire the browser app and focus development on iOS. Do not restore the browser client or work toward web/iOS feature parity. The active roadmap is `docs/ios-roadmap.md`; `docs/archive/web/` contains historical designs.

Keep the Next.js/Vercel API backend: installed iOS builds call `https://departs.vercel.app/api/*`. Preserve that host and the existing API contract. Server keys must never be embedded in the app.

## Commands

```bash
# iOS app (requires Xcode selected as the active developer directory)
xcodebuild -project ios/Departs/Departs.xcodeproj -scheme Departs -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -derivedDataPath /tmp/departs-iphone build
xcodebuild -project ios/Departs/Departs.xcodeproj -scheme Departs -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' -derivedDataPath /tmp/departs-iphone test

# API backend
npm ci
npm run dev
npm run build
npm run test:run
npm run test:coverage
npm run lint
```

## Environment variables

Required in `.env.local` and on Vercel for live API calls:

```
HERE_API_KEY=*             # Server-side transit data
MAPBOX_SECRET_TOKEN=sk.*   # Server-side walking directions
```

The native MapKit map does not use a public Mapbox token. Local backend startup does not change the production host compiled into `APIService`.

## Architecture

- SwiftUI with `@Observable` view models, iOS 26+, zero third-party iOS dependencies. Guard iOS 27-only APIs with availability checks.
- MapKit through `UIViewRepresentable` wrappers, system light/dark appearance.
- `DepartsApp` owns one `TransitSession`, containing the shared `TransitStore`, `LocationService` and foreground refresh clock. Each `ContentView` owns its selection, split navigation, scroll targets and sheets. Visible panes contribute separately to refresh demand; closing or backgrounding a window removes only its demand.
- The app target stays iPhone-only (`TARGETED_DEVICE_FAMILY = 1`). Landscape is enabled on iPhone. Test the resizable foundation on iPad with a command-line `TARGETED_DEVICE_FAMILY="1,2"` override and separate derived data; do not commit iPad, Mac or Vision Pro availability without the owner's decision in the adaptation plan.
- Nearby pins and the first three provider stops load on open; subsequent refreshes demand pins and visible stop sections. Departure and walking queues are independent and each runs at most three requests at once. MapKit maps load on request.
- App Intents expose pinned stop/direction entities through Shortcuts. Keep their stable identities independent of provider ordering.
- `APIService` is an actor using URLSession async/await.
- iOS structure: `Models/`, `Services/`, `ViewModels/`, `Views/`, `Utilities/`, `Preview Content/`.
- iOS `NearbyStop.distance` is optional; `LineInfo.id` is computed from `name::direction` because provider IDs are not consistently present.
- Wrap previews that use `PreviewData` in `#if DEBUG`: Preview Content is excluded from release builds.
- Next.js serves `app/api/*`; `app/route.ts` returns a plain-text retirement notice. There is no browser app.
- `@/*` maps to the repository root. `app/types.ts` describes the backend transit response shapes.

## Testing and workflow

- Backend: Vitest in Node, MSW mocks only external HERE and Mapbox calls, fixtures in `app/__tests__/fixtures/`.
- Native: unit XCTest in `ios/Departs/DepartsTests/`, UI flows with an in-process fixture HTTP server in `ios/Departs/DepartsUITests/`. The shared scheme runs both. Use normal simulator signing so App Intents can register correctly.
- Run backend tests, lint and a production build for backend changes; check the affected JSON endpoints over HTTP.
- Run native tests/build for native changes. Validate live data against the production API after deployment; test UI behavior in the iOS app.
- After implementing a change, commit, push and open or update its PR. Record which checks ran and distinguish local/preview verification from production verification.
- Preserve archived web work in Git history. Do not delete the Vercel project or remove API secrets as part of retiring the browser UI.

## External APIs

- HERE Transit v8: `/v8/stations` for nearby stops and `/v8/departures` for departures. Encode stop IDs using URL query parameters.
- Search radius: 400 metres by default, up to 50 stops. Backend PR #9 adds an optional 100–2000 metre radius; native recovery steps are 400/800/1600. Departure API supports `stopId`, plus optional paired `lineName` and `direction` filters, and returns up to four departures.
- Mapbox Directions: walking profile. The route returns the unwrapped first route as `{geometry, duration, distance}`.
- Cache headers do not make the native client refresh automatically.

## iOS simulator

```bash
xcrun simctl location 'iPhone 17 Pro' set 48.20134,16.34941
xcrun simctl privacy 'iPhone 17 Pro' grant location-always app.departs.Departs
```

## Deployment

Vercel auto-deploys from `main`; the API host stays `https://departs.vercel.app`. Native changes require a separate iOS build and distribution through TestFlight/App Store.

<!-- BEGIN:nextjs-agent-rules -->

## This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

# Departs - Project Instructions

## Product scope

Departs is an iOS app. The owner chose on 15 November 2026 to retire the browser app and focus development on iOS. Do not restore the browser client or work toward web/iOS feature parity. The active roadmap is `docs/ios-roadmap.md`; `docs/archive/web/` contains historical designs.

Keep the Next.js/Vercel API backend: installed iOS builds call `https://departs.vercel.app/api/*`. Preserve that host and the existing API contract. Server keys must never be embedded in the app.

## Commands

```bash
# iOS app (requires Xcode selected as the active developer directory)
xcodebuild -project ios/Departs/Departs.xcodeproj -scheme Departs -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -project ios/Departs/Departs.xcodeproj -scheme Departs -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

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

- SwiftUI with `@Observable` view models, iOS 17+, zero third-party iOS dependencies.
- MapKit through `UIViewRepresentable` wrappers, system light/dark appearance.
- `ContentView` switches between nearby stops and a selected stop/line departure board.
- `APIService` is an actor using URLSession async/await.
- iOS structure: `Models/`, `Services/`, `ViewModels/`, `Views/`, `Utilities/`, `Preview Content/`.
- iOS `NearbyStop.distance` is optional; `LineInfo.id` is computed from `name::direction` because provider IDs are not consistently present.
- Wrap previews that use `PreviewData` in `#if DEBUG`: Preview Content is excluded from release builds.
- Next.js serves `app/api/*`; `app/route.ts` returns a plain-text retirement notice. There is no browser app.
- `@/*` maps to the repository root. `app/types.ts` describes the backend transit response shapes.

## Testing and workflow

- Backend: Vitest in Node, MSW mocks only external HERE and Mapbox calls, fixtures in `app/__tests__/fixtures/`.
- Native: XCTest in `ios/Departs/DepartsTests/`; use a simulator for native build/test validation.
- Run backend tests, lint and a production build for backend changes; check the affected JSON endpoints over HTTP.
- Run native tests/build for native changes. Validate live data against the production API after deployment; test UI behavior in the iOS app.
- After implementing a change, commit, push and open or update its PR. Record which checks ran and distinguish local/preview verification from production verification.
- Preserve archived web work in Git history. Do not delete the Vercel project or remove API secrets as part of retiring the browser UI.

## External APIs

- HERE Transit v8: `/v8/stations` for nearby stops and `/v8/departures` for departures. Encode stop IDs using URL query parameters.
- Search radius: 400 metres, up to 50 stops. Departure API supports `stopId`, plus optional paired `lineName` and `direction` filters, and returns up to four departures.
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

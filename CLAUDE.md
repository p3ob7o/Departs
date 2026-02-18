# Departs - Project Instructions

## Commands

```bash
# Web app
npm run dev          # Start dev server (Turbopack)
npm run build        # Production build
npm run test:run     # Run unit tests once (vitest)
npm run test         # Run unit tests in watch mode
npm run test:coverage # Run tests with coverage report
npm run test:e2e     # Run Playwright e2e tests
npm run lint         # ESLint

# iOS app (requires Xcode + sudo xcode-select -s /Applications/Xcode.app/Contents/Developer)
xcodebuild -project ios/Departs/Departs.xcodeproj -scheme Departs -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -project ios/Departs/Departs.xcodeproj -scheme Departs -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Environment Variables

Required in `.env.local` (and on Vercel):

```
NEXT_PUBLIC_MAPBOX_TOKEN=pk.*    # Client-side map rendering
MAPBOX_SECRET_TOKEN=sk.*         # Server-side directions API
HERE_API_KEY=*                   # Server-side transit data
```

## Architecture

### Web App
- **Single-page app** with two screens managed by `selectedStop` state in `page.tsx`
- **API proxy pattern**: client fetches `/api/*` routes, server proxies to HERE/Mapbox with keys
- **No global state store** — hooks (`useGeolocation`, `useNearbyStops`, `useDepartures`) manage async state
- **Path alias**: `@/*` maps to project root

### iOS App (`ios/Departs/`)
- **SwiftUI** with `@Observable` (iOS 17+ target), zero third-party dependencies
- **MapKit** (`.mutedStandard`, auto dark mode) via `UIViewRepresentable` wrapping `MKMapView`
- **Reuses Vercel backend**: `APIService` actor calls `departs.vercel.app/api/*` via URLSession async/await
- **Same 2-screen flow**: `ContentView` toggles `selectedStop` state, matching web app's `page.tsx`
- Structure: `Models/`, `Services/`, `ViewModels/`, `Views/`, `Utilities/`, `Preview Content/`
- iOS models don't match web `types.ts` exactly: `NearbyStop.distance` is optional (`Int?`), `LineInfo.id` is computed from `name::direction` (API doesn't return these fields)
- `#Preview` blocks that reference `PreviewData` must be wrapped with `#if DEBUG` (Preview Content is excluded from release/archive builds)

## Key Conventions

- All components in `app/components/`, hooks in `app/hooks/`, API routes in `app/api/`
- Design tokens as CSS custom properties in `globals.css` (light/dark via `prefers-color-scheme`)
- No Geist fonts — uses iOS system font stack (`-apple-system, BlinkMacSystemFont, ...`)
- Map dark mode detected via `matchMedia` inside the Map component (not passed as prop)
- `mapbox-gl/dist/mapbox-gl.css` must be imported in Map.tsx for markers to render

## Testing

- **Unit tests**: Vitest + React Testing Library + MSW for API mocking
- API route tests run in `node` environment; component tests in `jsdom`
- `react-map-gl/mapbox` is aliased to a mock in `vitest.config.ts` (not via `vi.mock`)
- `matchMedia` is mocked in `app/__tests__/setup.ts`
- MSW handlers in `app/__tests__/mocks/handlers.ts` — the `/api/directions` handler returns the already-unwrapped format (flat `{geometry, duration, distance}`, not `{routes: [...]}`)
- Test fixtures in `app/__tests__/fixtures/`

## External APIs

- **HERE Transit v8**: `/v8/stations` (nearby stops), `/v8/boards` (departures). Stop IDs must be URL-encoded.
- **Mapbox Directions**: Walking profile. API route unwraps `routes[0]` before returning to client.
- **Mapbox GL JS**: `light-v11` / `dark-v11` styles via `react-map-gl`

## Browser Automation

- Multiple Chromium browsers are installed. Only **Google Chrome** (profile **"Claude"**) has the Claude extension
- If `tabs_context_mcp` returns a connection error, call `switch_browser` to connect to Chrome

## iOS Simulator Testing

```bash
# Set simulated location (e.g. Neubaugasse 36, Vienna)
xcrun simctl location "iPhone 17 Pro" set 48.20134,16.34941
# Grant location permission
xcrun simctl privacy "iPhone 17 Pro" grant location-always app.departs.Departs
# Install and launch
xcrun simctl install "iPhone 17 Pro" /Users/paolo/Library/Developer/Xcode/DerivedData/Departs-efvvvjglmzsmuugyprgrdugprfrn/Build/Products/Debug-iphonesimulator/Departs.app
xcrun simctl launch "iPhone 17 Pro" app.departs.Departs
```

## Workflow

- After implementing a change, always commit, push, and verify in Chrome on production (the app is not launched publicly)

## Deployment

- Vercel (auto-deploys from `main`)
- Production URL: https://departs.vercel.app

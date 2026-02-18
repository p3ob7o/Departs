# Departs - Project Documentation

## Overview

Departs is a mobile-first web app that shows nearby public transit stops and real-time departure times. It uses the browser's geolocation to find stops within 250m, displays them on a map, and shows upcoming departures when a stop is selected.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Next.js 16 (App Router, Turbopack) |
| Language | TypeScript (strict) |
| Styling | Tailwind CSS 4 + CSS custom properties |
| Map | Mapbox GL JS via react-map-gl |
| Transit data | HERE Public Transit API v8 |
| Walking directions | Mapbox Directions API |
| Testing | Vitest, React Testing Library, MSW, Playwright |
| Deployment | Vercel |
| iOS App | SwiftUI (iOS 17+), MapKit, CoreLocation, URLSession |

## Project Structure

```
app/
├── api/
│   ├── departures/route.ts      # Proxy → HERE /v8/boards
│   ├── directions/route.ts      # Proxy → Mapbox Directions
│   └── stops/nearby/route.ts    # Proxy → HERE /v8/stations
├── components/
│   ├── BottomSheet.tsx           # Fixed bottom sheet (flush, no drag handle)
│   ├── DepartureDetail.tsx       # Screen 2: departure list + header
│   ├── DepartureRow.tsx          # Individual departure (12h time + clock icon)
│   ├── ErrorState.tsx            # Error/permission/offline states
│   ├── LoadingState.tsx          # Centered spinner
│   ├── Map.tsx                   # Mapbox GL map with custom markers
│   ├── StopList.tsx              # Screen 1: nearby stops list
│   ├── StopRow.tsx               # Stop row (transport type + line info)
│   └── TransportIcon.tsx         # 40px circle with transport letter + per-stop color palette
├── hooks/
│   ├── useDepartures.ts          # Fetches departures + walking route
│   ├── useGeolocation.ts         # Browser geolocation with retry
│   └── useNearbyStops.ts         # Fetches nearby stops
├── lib/
│   ├── api.ts                    # Client fetch helpers
│   └── transitProvider.ts        # HERE API response transformers
├── __tests__/                    # Fixtures, mocks, setup
├── globals.css                   # Design tokens + layout
├── layout.tsx                    # Root layout (no custom fonts)
├── page.tsx                      # Main page (state machine)
└── types.ts                      # Shared TypeScript interfaces
docs/
├── PRD.md                        # Product requirements
├── specs.md                      # Technical specifications
├── design-system.md              # UI design tokens & components
└── user-journey.md               # User flow documentation
e2e/                              # Playwright e2e tests
ios/Departs/
├── Departs.xcodeproj/            # Xcode project (iOS 17+ target)
├── Departs/
│   ├── Models/                   # Codable structs matching web types.ts
│   ├── Services/                 # APIService (actor), LocationService (@Observable)
│   ├── ViewModels/               # NearbyStopsViewModel, DepartureDetailViewModel
│   ├── Views/                    # SwiftUI views (ContentView, screens, rows)
│   │   └── Map/                  # UIViewRepresentable MKMapView wrappers
│   ├── Utilities/                # StopPalette, TimeFormatter, Color+Hex
│   └── Preview Content/          # Sample data for Xcode previews
└── DepartsTests/                 # XCTest unit tests
```

## Screens

### Screen 1: Nearby Stops
- Map shows user location (blue dot with pulsing halo) + 250m radius circle
- Each stop gets a unique muted pastel color (from a 10-color palette) on both the map marker and list icon
- Bottom sheet lists stops: transport type heading, line + direction subtitle

### Screen 2: Departure Detail
- Map zooms to fit user + stop pin (same pastel color as in list), with walking route (dashed line) added when loaded
- Map and departures load in parallel — map updates immediately without waiting for departure data
- Bottom sheet shows "Departures:" heading, line info, walking time
- Up to 4 departure times using device locale (12h or 24h per user setting) with clock icons

## Design System

- Full light/dark mode via CSS custom properties (`--color-bg-primary`, `--color-text-primary`, etc.)
- Dark mode: auto-detected via `prefers-color-scheme` media query
- Map styles switch between `light-v11` and `dark-v11`
- Max width 430px, centered on desktop
- iOS system font stack

## Data Flow

```
Browser Geolocation → useGeolocation hook
    ↓
/api/stops/nearby → HERE /v8/stations → transformStations → useNearbyStops
    ↓ (user taps stop)
/api/departures → HERE /v8/boards → transformDepartures → useDepartures
/api/directions → Mapbox Directions → flat {geometry, duration, distance} → useDepartures
```

## iOS App

Native SwiftUI companion app that reuses the Vercel backend (no API keys on device). Zero third-party dependencies — MapKit for maps, CoreLocation for location, URLSession for networking.

- Same 2-screen flow as web app: nearby stops → departure detail
- Centered "Departs" header on both screens; Back button at top-left on detail screen
- Pull-to-refresh on stops list to re-request location and reload stops
- Edge-to-edge maps on both screens
- MapKit `.mutedStandard` with automatic dark mode
- `UIViewRepresentable` MKMapView for custom annotations (colored pins, pulsing user dot, dashed route)
- Detail map loads route and departures in parallel — map shows user + stop immediately
- Per-stop pastel colors (same 10-color palette as web)
- `APIService` actor with 3 async methods calling `departs.vercel.app/api/*`
- Time formatting uses device locale (respects 12h/24h setting)
- App icon included (dark charcoal with app name and transit line motif)
- Bundle ID: `app.departs.Departs`

## Current Status

- Core functionality working: geolocation, nearby stops, departure fetching, walking directions
- Design system fully implemented with light/dark mode
- Custom map markers rendering (blue dot, stop pins with letters, walking route)
- 129 web unit tests passing, 8 iOS unit tests passing, production build succeeds
- Deployed to Vercel at https://departs.vercel.app
- iOS app ready for TestFlight (archive builds, app icon, signed)

## Known Considerations

- HERE API free tier: 5,000 transactions/month
- Mapbox free tier: 50,000 map loads/month, 100,000 direction requests/month
- Departures endpoint may return 500 for some stop ID formats — IDs are now URL-encoded
- `useDepartures` resets state (departures, walkingRoute, error) when navigating back (stopId → null)
- E2e tests exist in `e2e/` but require browser setup via Playwright

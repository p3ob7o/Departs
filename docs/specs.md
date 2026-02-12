# Departs - Technical Specifications

## 1. Architecture Overview

Departs is a **Next.js** mobile-first web application. It runs entirely in the browser with no user accounts or backend database. The Next.js server acts as a thin API proxy to external services, keeping API keys secure.

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────────────┐
│   Browser     │────▶│  Next.js Server  │────▶│  External APIs       │
│   (Mobile)    │◀────│  (API Routes)    │◀────│  (Transit, Maps)     │
└──────────────┘     └──────────────────┘     └──────────────────────┘
```

- **Client**: React components, map rendering, geolocation
- **Server**: API routes that proxy requests to external services
- **External**: Transit data API, Mapbox (maps + directions)

## 2. Technology Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| Framework | Next.js 15 (App Router) | React-based, SSR/SSG capable, API routes for proxying |
| Language | TypeScript | Type safety across client and server |
| Styling | Tailwind CSS | Utility-first, fast iteration, dark mode support |
| Map Rendering | Mapbox GL JS (via react-map-gl) | Lightweight, customizable, built-in light/dark styles |
| Walking Directions | Mapbox Directions API | 100K free requests/month, walking profile |
| Transit Data | HERE Public Transit API v8 | Purpose-built endpoints for nearby stops + departures, ~1000+ cities |
| Geolocation | Browser Geolocation API | Native, no library needed |
| State Management | React useState/useReducer | App state is minimal, no need for external store |
| Deployment | Vercel | Native Next.js hosting, edge functions, free tier |

## 3. External API Integrations

### 3.1 Browser Geolocation API

**Purpose**: Get user's current latitude and longitude.

**Usage**:
- Called on app mount via `navigator.geolocation.getCurrentPosition()`
- Options: `enableHighAccuracy: true`, `timeout: 10000`, `maximumAge: 60000`
- Falls back to `watchPosition()` if initial fix is too slow

**No API key required** — this is a browser-native API.

**Error handling**:
- `PERMISSION_DENIED` → Show permission explanation screen
- `POSITION_UNAVAILABLE` → Show error with retry
- `TIMEOUT` → Show error with retry

### 3.2 HERE Public Transit API v8

**Purpose**: Find nearby transit stops and get departure times.

**Base URL**: `https://transit.hereapi.com/v8`

**Authentication**: API key via query parameter `apiKey={key}`

**Endpoints used**:

#### GET /stations
Find transit stops near a location.
```
GET /stations?in={lat},{lon};r=250
```
Response includes: station ID, name, location, transport modes available.

#### GET /boards
Get upcoming departures from a stop.
```
GET /boards?ids={stationId}&direction={directionId}&maxPerBoard=4
```
Response includes: departure time (scheduled + real-time), line name, direction/headsign, transport mode.

**Rate limits**: 5,000 transactions/month (free tier). After that, $2.50/1,000.

**Fallback/Alternative**: The transit data layer will be abstracted behind an interface, allowing future swap to Navitia.io, Transitland, or OpenTripPlanner if needed.

### 3.3 Mapbox Directions API

**Purpose**: Calculate walking route from user location to selected stop.

**Endpoint**:
```
GET https://api.mapbox.com/directions/v5/mapbox/walking/{lon1},{lat1};{lon2},{lat2}
    ?geometries=geojson
    &access_token={token}
```

**Response**: GeoJSON LineString geometry for the route, duration, and distance.

**Rate limits**: 100,000 requests/month (free tier).

### 3.4 Mapbox GL JS (Map Tiles)

**Purpose**: Render the interactive map in the browser.

**Styles used**:
- Light mode: `mapbox://styles/mapbox/light-v11`
- Dark mode: `mapbox://styles/mapbox/dark-v11`

**Map features**:
- User location marker (blue dot with halo)
- 250m radius circle (Screen 1)
- Stop markers with green pins (Screen 2)
- Walking route line (dashed, Screen 2)

**Rate limits**: 50,000 map loads/month (free tier).

## 4. API Proxy Layer (Next.js API Routes)

All external API calls (HERE, Mapbox Directions) are proxied through Next.js API routes to:
1. Keep API keys server-side (never exposed to the client)
2. Allow response transformation and caching
3. Provide a stable internal API regardless of external provider changes

### Route Structure

```
/api/stops/nearby    → proxies HERE /stations
/api/departures      → proxies HERE /boards
/api/directions      → proxies Mapbox Directions
```

### Caching Strategy

| Endpoint | Cache TTL | Rationale |
|----------|-----------|-----------|
| `/api/stops/nearby` | 24 hours | Stop locations rarely change |
| `/api/departures` | 30 seconds | Real-time data, must stay fresh |
| `/api/directions` | 1 hour | Walking routes don't change often |

Caching is implemented via Next.js `fetch` with `revalidate` or via HTTP cache headers.

## 5. Data Models

### NearbyStop
```typescript
interface NearbyStop {
  id: string;                   // Unique stop/station ID from transit API
  name: string;                 // Stop name (e.g., "42nd Street")
  type: TransportType;          // 'subway' | 'tram' | 'bus' | 'rail'
  lines: LineInfo[];            // Lines serving this stop
  location: {
    lat: number;
    lon: number;
  };
  distance: number;             // Distance from user in meters
}

interface LineInfo {
  id: string;                   // Line identifier
  name: string;                 // Line display name (e.g., "Line 1")
  direction: string;            // Headsign / end station name
  type: TransportType;
}
```

### Departure
```typescript
interface Departure {
  time: string;                 // ISO 8601 departure time
  realTime: boolean;            // Whether this is real-time or scheduled
  delay: number | null;         // Delay in seconds (null if on time or no data)
}
```

### WalkingRoute
```typescript
interface WalkingRoute {
  geometry: GeoJSON.LineString; // Route polyline
  duration: number;             // Walking time in seconds
  distance: number;             // Distance in meters
}
```

## 6. Screen Flow & State Machine

```
[LOADING] ──▶ [NEARBY_STOPS] ──▶ [DEPARTURE_DETAIL]
    │                │                      │
    │                │                      │
    ▼                ▼                      │
[ERROR]        [EMPTY_STATE]               │
                                            │
              ◀─────────────────────────────┘
                        (back)
```

### App States

| State | Trigger | Data Required |
|-------|---------|---------------|
| `LOADING` | App mount | None |
| `ERROR_PERMISSION` | Geolocation denied | None |
| `ERROR_NETWORK` | API call failed | Error message |
| `EMPTY_STATE` | No stops within radius | User coordinates |
| `NEARBY_STOPS` | Stops fetched successfully | User coordinates, list of NearbyStop |
| `DEPARTURE_DETAIL` | User taps a stop | Selected stop, departures, walking route |

## 7. Client-Side Component Structure

```
app/
├── layout.tsx              # Root layout, dark mode provider, viewport meta
├── page.tsx                # Main (only) page — manages app state
├── components/
│   ├── Map.tsx             # Mapbox GL wrapper (handles both screens)
│   ├── BottomSheet.tsx     # Draggable bottom sheet container
│   ├── StopList.tsx        # List of nearby stops (Screen 1 content)
│   ├── StopRow.tsx         # Individual stop row (icon + type + line + chevron)
│   ├── DepartureDetail.tsx # Departure list (Screen 2 content)
│   ├── DepartureRow.tsx    # Individual departure time row
│   ├── TransportIcon.tsx   # Icon component for subway/tram/bus
│   ├── LoadingState.tsx    # Loading spinner/skeleton
│   └── ErrorState.tsx      # Error and empty state displays
├── hooks/
│   ├── useGeolocation.ts   # Browser geolocation wrapper
│   ├── useNearbyStops.ts   # Fetch nearby stops
│   └── useDepartures.ts    # Fetch departures for a stop
├── lib/
│   ├── api.ts              # Client-side fetch helpers for /api/* routes
│   └── transitProvider.ts  # Transit API adapter interface
└── api/
    ├── stops/nearby/route.ts   # Proxy to HERE /stations
    ├── departures/route.ts     # Proxy to HERE /boards
    └── directions/route.ts     # Proxy to Mapbox Directions
```

## 8. Mobile-First Considerations

- **Viewport**: Locked to mobile width, `<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">`
- **Touch targets**: All tappable elements minimum 44x44pt (Apple HIG)
- **Performance**: Map is the heaviest asset. Use `react-map-gl` lazy loading. Minimize JS bundle.
- **PWA potential**: Add `manifest.json` and service worker for home screen install (v1 optional, but the structure should support it).
- **Safe areas**: Respect `env(safe-area-inset-*)` for notched devices.

## 9. Environment Variables

```env
# Mapbox
NEXT_PUBLIC_MAPBOX_TOKEN=pk.*       # Client-side map rendering
MAPBOX_SECRET_TOKEN=sk.*             # Server-side directions API

# HERE
HERE_API_KEY=                        # Server-side transit data

# App
NEXT_PUBLIC_SEARCH_RADIUS=250       # Default radius in meters
```

`NEXT_PUBLIC_` prefixed vars are exposed to the client. All others are server-only.

## 10. Error Handling Strategy

| Error | User-Facing Behavior |
|-------|---------------------|
| Geolocation denied | Full-screen prompt explaining why location is needed, with a button to open settings |
| Geolocation timeout | "Having trouble finding your location" with retry button |
| Transit API down/error | "Couldn't load transit data" with retry button |
| No stops found | "No public transit found within 250m" with a suggestion to try a different area |
| Directions API error | Show departures without the walking route map (graceful degradation) |
| Offline | "You appear to be offline" with retry button |

## 11. Performance Budget

| Metric | Target |
|--------|--------|
| First Contentful Paint | < 1.5s |
| Largest Contentful Paint | < 2.5s |
| Total JS bundle (gzipped) | < 150KB (excluding map GL) |
| API response time (proxy) | < 500ms |
| Time to interactive | < 3s on 4G |

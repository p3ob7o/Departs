# Departs - User Journey & API Flow

```mermaid
flowchart TD
    A[User opens Departs] --> B[App requests user location]
    B --> C[Browser Geolocation API]
    C --> D{Location permission?}

    D -->|Denied| E[Show permission explanation screen]
    E --> F[User opens device settings]
    F --> B

    D -->|Granted| G[Receive lat/lon coordinates]

    G --> H[Show loading state with map centered on user]

    H --> I[Fetch nearby transit stops]
    I --> J["API: Next.js /api/stops/nearby\n(lat, lon, radius=250m)"]
    J --> K["External: HERE Transit API\nGET /v8/stations?in=lat,lon;r=250"]

    K --> L{Stops found?}

    L -->|None| M[Show empty state:\nNo public transit within 250m]

    L -->|Found| N[Screen 1: Nearby Stops\nMap with user dot + 250m radius\nBottom sheet with stop list]

    N --> O[User taps a transit option]

    O --> P[Fetch departures + walking route in parallel]

    P --> Q["API: Next.js /api/departures\n(stop_id, direction, limit=4)"]
    Q --> R["External: HERE Transit API\nGET /v8/boards?ids=stopId&maxPerBoard=4"]

    P --> S["API: Next.js /api/directions\n(user coords, stop coords)"]
    S --> T["External: Mapbox Directions API\nGET /directions/v5/mapbox/walking/..."]

    R --> U{Both responses received?}
    T --> U

    U --> V[Screen 2: Departure Detail\nMap with walking route\nBottom sheet with next 4 departures]

    V --> W{User action}

    W -->|Taps back| N
    W -->|Closes app| X[Session ends]
```

## External API Calls Summary

| Step | API | Endpoint | Trigger |
|------|-----|----------|---------|
| Geolocation | Browser Geolocation API | `navigator.geolocation.getCurrentPosition()` | App launch |
| Nearby stops | HERE Public Transit API v8 | `GET /v8/stations?in={lat},{lon};r=250` | After geolocation succeeds |
| Departures | HERE Public Transit API v8 | `GET /v8/boards?ids={stationId}&maxPerBoard=4` | User taps a stop |
| Walking route | Mapbox Directions API | `GET /directions/v5/mapbox/walking/{coords}` | User taps a stop (parallel with departures) |
| Map tiles | Mapbox GL JS | Tile requests (automatic) | Whenever map is visible |

## Notes

- The departures and walking route requests fire **in parallel** when the user taps a stop, to minimize wait time.
- All external API calls are proxied through Next.js API routes — the browser never calls HERE or Mapbox Directions directly.
- Map tile requests (Mapbox GL JS) go directly from the browser to Mapbox CDN using the public token.
- If the walking route request fails, the app still shows departures (graceful degradation). The map falls back to showing both points without a route line.

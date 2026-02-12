# Departs - Product Requirements Document

## 1. Product Overview

**Departs** is a mobile-first web app that instantly shows the nearest public transit options when launched. No login, no setup — open the app, see what's leaving near you, tap to get walking directions and the next departures.

The name references the split-flap departure boards found in train stations: fast, glanceable, and purpose-built for people on the move.

## 2. Problem Statement

When you're somewhere unfamiliar (or even somewhere familiar but in a hurry), finding the nearest bus, tram, or subway stop and knowing when the next ride departs requires opening a maps app, searching for transit, parsing complex route planners, and filtering through irrelevant results. It's slow, cluttered, and over-engineered for a simple question: **"What's leaving near me, and when?"**

## 3. Target Users

- Travelers in unfamiliar cities
- Daily commuters who want a faster alternative to full route planners
- Anyone on the go who needs instant transit info without friction

**User profile**: Smartphone user, standing on a street or exiting a building, who needs an answer in under 10 seconds.

## 4. Core Features

### 4.1 Automatic Geolocation
- On launch, the app requests the user's location via the browser Geolocation API.
- No manual address entry. The app is designed for "right here, right now."
- If permission is denied, a clear prompt explains why location is needed.

### 4.2 Nearby Transit Discovery
- Shows all public transit stops within a **250-meter radius** (approximately 2-3 minutes walking).
- Each stop displays:
  - **Transport type**: Subway, Tram, Bus (with corresponding icon)
  - **Line number**: e.g., Line 1, Line 12
  - **Direction**: Name of the end station (headsign), e.g., "to Grand Central"
- Results are shown in a bottom sheet over a map centered on the user's location.
- The map displays a 250m radius circle around the user.

### 4.3 Departure Details
- Tapping a transit option navigates to a detail view showing:
  1. **Walking map**: A route from the user's current location to the selected stop, with the stop marked by a pin.
  2. **Next 4 departures**: Listed with absolute times (e.g., 12:15 PM, 12:22 PM), in a bottom sheet below the map.
- The header identifies the selected line and direction (e.g., "Subway Line 1 to Grand Central").

### 4.4 Light Mode / Dark Mode
- Supports both light and dark color schemes.
- Follows the user's system preference by default.
- Map tiles switch between light and dark styles accordingly.

## 5. User Stories

| ID | Story | Priority |
|----|-------|----------|
| US-1 | As a user, I open the app and it immediately begins locating me, so I don't have to type anything. | P0 |
| US-2 | As a user, I see a list of nearby transit options with type, line, and direction so I can quickly identify what's useful. | P0 |
| US-3 | As a user, I tap a transit option and see walking directions to the stop plus the next 4 departure times. | P0 |
| US-4 | As a user, I can go back to the stop list to pick a different option. | P0 |
| US-5 | As a user, the app respects my phone's dark mode setting. | P1 |
| US-6 | As a user, if no stops are found within 250m, I see a clear message (not a blank screen). | P1 |
| US-7 | As a user, if I deny location permission, I understand what the app needs and can retry. | P1 |

## 6. Screens

The app has **2 primary screens** plus transient states:

### Screen 1: Nearby Stops
- **Map area** (top ~55%): User's location centered, 250m radius circle overlay.
- **Bottom sheet** (bottom ~45%): Scrollable list of nearby stops. Each row has an icon, transport type, line + direction, and a chevron.
- **Transient states**: Loading spinner while geolocating; error/empty states.

### Screen 2: Departure Detail
- **Map area** (top ~55%): Walking route (dashed line) from user to stop. Stop marked with a green pin. User location shown as blue dot.
- **Bottom sheet** (bottom ~45%): Header with line name and direction. List of 4 departure times, each with a clock icon.
- **Back navigation**: Tap back to return to Screen 1.

### Transient States
- **Loading**: Shown while geolocation is in progress and while fetching transit data.
- **Location permission denied**: Explanation + prompt to enable.
- **No stops found**: Friendly message suggesting the user may be in an area without transit coverage.
- **Network error**: Retry prompt.

## 7. What This App Is NOT

- **Not a route planner**: No origin/destination input, no trip planning.
- **Not a map app**: The map is minimal, only showing the immediate area.
- **Not a desktop app**: Mobile-only viewport, designed for one-handed phone use.
- **No accounts**: No login, no saved preferences, no history.
- **No notifications**: No push alerts for departures.

## 8. Success Metrics

| Metric | Target |
|--------|--------|
| Time from app open to seeing stops | < 3 seconds (with location cached) |
| Time from tap to seeing departures | < 1 second |
| Screens to complete core task | 2 taps max (open app → tap stop) |

## 9. Constraints & Assumptions

- Requires an active internet connection.
- Requires browser geolocation permission.
- Transit data availability depends on the coverage of the transit data API provider — the app will be most useful in cities with GTFS data feeds.
- The 250m radius is a hardcoded default for v1. Future versions may allow adjustment.
- Departure times depend on the quality of real-time data from transit operators. Where real-time is unavailable, scheduled times are shown.

## 10. Future Considerations (Out of Scope for v1)

- Adjustable search radius
- "Favorite" stops or lines
- Pull-to-refresh for updated departure times
- Real-time countdown ("in 3 min" vs "12:15 PM") toggle
- Walking time estimate to the stop
- Multiple languages / localization
- PWA install prompt for home screen

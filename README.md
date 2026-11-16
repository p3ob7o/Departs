# Departs

Departs is a native iOS app for finding nearby public transport, checking the next departures, and walking to the stop. It uses SwiftUI and MapKit on iOS 26 and later, with no accounts or third-party iOS dependencies.

The opening screen shows a square map over the lines that leave within the hour, within 400 metres of where you are. Tap a line for its walking route and next four departures. Saved results appear immediately while location and transit data refresh. Pin a stop and direction for repeat trips and open it through App Shortcuts. There is no search: with location off, the app shows pinned routes only.

Development focuses exclusively on iOS. The browser app is retired; this repository retains the Next.js API backend that the iOS app needs. The website root returns a short retirement notice.

## Project layout

- `ios/Departs/`: the iOS app and XCTest suite.
- `app/api/`: the Vercel backend for nearby stops, departures, and walking directions.
- `app/lib/`: transit provider normalization.
- [iOS roadmap and product decision](docs/ios-roadmap.md).
- [Implementation and API guide](DOCUMENTATION.md).
- [Agent commands and conventions](AGENTS.md).
- [Original project audit](docs/reviews/2026-11-15-project-audit.md) and [archived web designs](docs/archive/web/PRD.md).

## iOS development

Open `ios/Departs/Departs.xcodeproj` in Xcode and select the Departs scheme. Build or run on an iOS simulator or device. From the command line, with Xcode selected:

```bash
xcodebuild -project ios/Departs/Departs.xcodeproj -scheme Departs -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

`APIService` calls `https://departs.vercel.app/api/`. In a Debug scheme, set `DEPARTS_API_BASE_URL=http://localhost:3000` to test a local backend; release builds ignore this environment override. API keys stay on the server.

The scheme runs unit tests and UI tests. UI tests serve their own local transit fixtures, simulate location, and use isolated preferences; they do not require provider keys. Screenshots are attached to the Xcode test report. See [native behavior and verification](docs/ios-fast-answers.md) for cache, refresh, Shortcuts, and release details.

## Backend development

Run `npm ci`, configure `HERE_API_KEY` and `MAPBOX_SECRET_TOKEN` in `.env.local`, then run `npm run dev`. No public Mapbox token is needed: MapKit renders the native maps, while Mapbox still supplies walking directions through the server.

```bash
npm run test:run
npm run lint
npm run build
```

Vercel deploys `main`. Keep the API host, endpoint paths, and response shapes compatible with installed iOS builds. Merging backend changes does not distribute a new iOS binary.

# Departs

Departs is a native iOS app for finding nearby public transport, checking the next departures, and walking to the stop. It uses SwiftUI and MapKit on iOS 26 and later, with no accounts or third-party iOS dependencies.

The opening screen shows a square map over the lines that leave within the hour, within 400 metres of where you are. Tap a line for its walking route on a locked map and its next four departures. Saved results appear immediately while location and transit data refresh. Pin a stop and direction for repeat trips and open it through App Shortcuts. There is no search: with location off, the app shows pinned routes only.

Development focuses exclusively on iOS. Spacefast serves the iOS API. Its root returns a short notice about the retired browser app.

## Project layout

- `ios/Departs/`: the iOS app and XCTest suite.
- `spacefast/functions/`: HTTP entry points for the root, nearby stops and departures. HERE supplies the transit data. The app requests walking routes from MapKit on the device.
- `app/lib/`: request validation, provider calls and response normalization.
- [iOS roadmap and product decision](docs/ios-roadmap.md).
- [Implementation and API guide](DOCUMENTATION.md).
- [Agent commands and conventions](AGENTS.md).
- [Original project audit](docs/reviews/2026-11-15-project-audit.md) and [archived web designs](docs/archive/web/PRD.md).

## iOS development

Open `ios/Departs/Departs.xcodeproj` in Xcode and select the Departs scheme. Build or run on an iOS simulator or device. From the command line, with Xcode selected:

```bash
xcodebuild -project ios/Departs/Departs.xcodeproj -scheme Departs -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Starting with 1.3 (15), `APIService` calls `https://api.departs.now/api/`. In a Debug scheme, set `DEPARTS_API_BASE_URL` to a fixture server to test against local data. Release builds use the production host. API keys stay on the server.

The scheme runs unit tests and UI tests. UI tests serve their own local transit fixtures, simulate location, and use isolated preferences; they do not require provider keys. Screenshots are attached to the Xcode test report. See [native behavior and verification](docs/ios-fast-answers.md) for cache, refresh, Shortcuts, and release details.

## Backend development

The local suite uses MSW fixtures for HERE. It needs no provider credentials.

```bash
npm ci
npm run test:run
npm run test:coverage
npm run lint
npm run build:spacefast
```

The build writes the three Functions under `.spacefast/worker/functions/`. See the [hosting guide](docs/backend-hosting.md) for preview checks, releases and rollback. A backend release is independent of iOS distribution.

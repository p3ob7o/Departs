# Native fast answers

Departs shows which transport is available around you: within 400 metres of where you are, and nowhere else. The [two-screen plan](plans/ios-two-screens.md), approved on 16 November 2026, replaces the former advice cards, idle disclosures and map sheets. Its [amendment](plans/ios-two-screens.md#amendment-around-you-only) of the same day removed place search and the wider search. Both screens have a square map above a short list. The app requires iOS 26 and supports iPhone in portrait.

## Home selection and order

Home restores its last published list before networking. It then requests stops within 400 metres of the rider's position and fetches all their departure boards in one batch. The radius is fixed, and there is no way to choose another place. Candidates come from actual departures within 60 minutes of the batch's `fetchedAt`, not the provider's stop-line metadata.

Platforms with the same name within 150 metres form one physical stop. Sections follow computed straight-line distance from the centre of the area, which is where the rider was when its stops were loaded. A new fix within 150 metres keeps that centre, so the list and map stay put; a fix farther away starts a new area. The nearest stop for a line contributes all its qualifying destinations. If it has only one, the next qualifying stop may contribute one different destination. A line uses at most two automatic stops, and a mode/line/destination appears once. Rows retain provider order. Walking time never changes selection or ordering.

The snapshot contains rows and boards together. Countdown ticks never change membership or order. A failed refresh retains the whole list; a partial response updates available times while retaining membership and order until a complete response arrives. Publication waits until the list is no longer being touched.

Rows show a mode badge, destination and a single primary time. Fresh times read "Now" below one minute and "In N min" through 60 minutes. Saved times use the clock. Home has no live/scheduled label or leave advice. The common city prefix may be hidden visually when every destination shares it; VoiceOver always speaks the full destination.

Pinned directions come first, in pin order, with their stop name. Nearby pinned services suppress automatic duplicates. An idle pin stays dimmed with "Nothing soon"; other idle services disappear. "Pinned elsewhere" opens pins outside this area. Pin by swipe, long press or the line screen's system pin button.

## Maps and the line screen

Home's map shows the search radius and one label per listed physical stop, including nearby pins. A label contains up to three line badges, then a count. A single-row stop opens its line; a multi-row stop selects the pin and scrolls to the section. All map actions remain available in the list. Map tiles never block departures.

The line screen opens with home's two times, then requests up to four for that exact platform, line and direction. Its square map immediately shows the walking route, or both endpoints while no route is available. The full direction wraps in the content as well as appearing in the navigation title. The stop appears once with walking time and distance. When the walk starts from the last area instead of a current position, it says so. A pinned route opened while location is off shows the stop alone.

Each fresh departure shows its countdown and clock. Beyond 60 minutes only the clock remains. Live departures have a symbol and a delay from one full minute; scheduled times carry no marker. Saved data shows clock times and one Refresh action. The system toolbar opens Apple Maps in walking mode to the platform and pins the direction. There are no advice cards, crossed-out times or other-line sections.

The map remains fixed through the largest standard text size. At accessibility sizes it stays square and scrolls away with the list. Map badge text caps at 18 pt; list text uses the full preferred size. Rows are single VoiceOver elements without decorative state. App-drawn controls have at least 44-pt targets; native toolbar accessibility frames do not measure their hit regions.

## Freshness, failures and recovery

- A board is fresh for 60 seconds. Home counts from the provider-attempt `fetchedAt`, so a CDN hit does not reset its age. The compatible per-line array has no timestamp and retains its existing receipt-based check time.
- A failed refresh marks the previous answer saved immediately. Restored boards remain saved until successfully checked. Home and line have separate board ownership once the line request starts, so a two-time home refresh cannot replace four times or certify a failed line request.
- Home keeps one saved/partial banner. A missing first-load platform gets one Retry row per physical stop, never one per line. A failed stops request has an error and Try again, distinct from no stops and nothing in the next hour.
- No stops within 400 metres, and no departures within the hour, are plain statements. Neither offers another search.
- The top bar holds one control, the location button. It asks for a new fix and returns a panned map to the searched circle.
- With location off, home shows the notice, Open Settings and pinned routes only. The last area is forgotten, not refreshed, and the location button tells VoiceOver that location is off.
- Without a usable fix and without a saved area, home says it could not find the location and offers Try again and Open Settings. With a saved area the list stays, titled Last area, and its times keep updating.
- A usable location is no more than two minutes old and accurate to 100 metres. A coarser fix counts as no fix, which is what Precise Location off produces. Stops older than five minutes are refreshed for the same centre, with the rows left on screen. Walking routes are reused for ten minutes within 40 metres of their origin. Walking minutes round up; routes farther than five kilometres are not requested.
- Visible screens refresh on foreground return and every 30 seconds after the previous refresh finishes. Requests have a 25-second recency throttle; explicit refresh bypasses it. Countdowns tick every 15 seconds. Location requests time out after eight seconds, excluding permission dialogs.

The provider caps each platform at 50 departures. Two times per transport leave room for more services, but lines absent from a capped board are not discoverable. There is no per-line fallback for home. The provider can return different later times with two-per-transport and four-per-line requests, as observed on Berlin U2 in the preview check.

## State and requests

`DepartsApp` owns one `TransitSession` with a shared observable `TransitStore`, location service and refresh clock. `ContentView` owns navigation and the pinned-elsewhere sheet. Area and batch tasks belong to the store, with revision checks against stale results. Backgrounding removes refresh demand. APIService coalesces identical URLs, uses a 12-second timeout and bypasses the local URL cache for departures.

Opening the Vienna sample costs six requests: one stops, one batch and four walking routes. Each home refresh costs one batch. Walks run up to three at once and do not block the list. Each listed physical stop uses its nearest platform for the walk; the line screen requests its own platform's route. A line request may reuse that walk.

UserDefaults stores pins, the last nearby response, the published home snapshot and the 40 newest line boards. A searched place, a wider radius or recent places saved by builds up to 1.2 (7) are discarded on first launch. Boards older than a day are discarded on launch. The in-memory cache has no old 80-board pruning rule. Walks stay in memory. Pin identities are length-prefixed and independent of provider ordering. Unknown deep-link IDs cannot load arbitrary stops.

## Shortcuts

Pin a direction, then select it in Departs' **Open pinned route** action in Shortcuts. The action opens the line and refreshes it. Existing `departs://pin?id=<encoded saved identity>` links still work. Intent execution and URL navigation are tested; Siri speech and discovery in Shortcuts need a signed physical-device check.

## Verification and release

The shared scheme runs unit and UI tests. Pin the simulator runtime and keep one derived-data directory per destination outside Git:

```bash
xcodebuild -project ios/Departs/Departs.xcodeproj -scheme Departs \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
  -derivedDataPath /tmp/departs-iphone -parallel-testing-enabled NO test
```

The UI suite uses a local HTTP fixture server, simulated location and isolated preferences. It covers the states in the plan, navigation, failure recovery, both map actions, pins and text sizes. Debug accepts `DEPARTS_API_BASE_URL`, `DEPARTS_DEFAULTS_SUITE` and `DEPARTS_TEST_LOCATION_ACCURACY`. Release excludes these hooks and local-networking permission. The simulator's location is exactly constant and always precise. A coarse fix therefore needs the accuracy override, and behaviour that depends on small differences between fixes needs a unit test or a phone.

On a new simulator, grant Apple Maps its own location permission before the UI suite: `xcrun simctl privacy <SIMULATOR_UUID> grant location com.apple.Maps`. The walking-directions test needs Maps to plan a route. Granting it through the prompt instead makes iOS ask about Maps widgets a minute later, over whichever test is running.

Use iOS 26.2 for dark-mode checks. Pseudolocalization copies the project outside Git and adds an expanded German test catalog there only. No German ships. See the [Phase 3 validation](plans/ios-two-screens-phase-3-validation.md) for commands, measured results and T1–T17 coverage, plus the [Phase 0 provider checks](plans/ios-two-screens-phase-0-validation.md).

Backend PRs #26 and #27 reached `main` and production before the new native client. Remaining phase PRs must each reach `main` in order; retarget the next to `main` after its base merges. Version 1.2 preparation and TestFlight distribution require a separate owner request. Simulator fixtures do not establish realtime coverage, mobile-data startup time, VoiceOver speech, haptics or GPS behavior.

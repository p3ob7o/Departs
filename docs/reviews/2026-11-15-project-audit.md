# Departs project review — 15 November 2026

> Historical snapshot from before the owner chose to focus exclusively on iOS later on 15 November 2026. Web-only PR #8 is retired; PR #9 is scoped to the backend; native #10 and runtime #11 remain relevant. This report is carried forward from #12 by the retirement PR. The current scope and five product priorities are in [the iOS roadmap](../ios-roadmap.md). The web/PWA recommendations and original PR validation below describe the earlier review, not the current roadmap.

The app has a clear purpose: open it, find a nearby transit option, and see when to leave for the stop. The native client is ahead of the web client in line selection and presentation. Several correctness defects and dependency advisories should be addressed before inviting more users.

This review produced four independent fix PRs. They are proposals against `main`, not production changes. All four merge together without conflicts; the combined web checks pass. No branches were deleted, PRs merged, or TestFlight releases uploaded.

## Git synchronization and branch decisions

Repository: [p3ob7o/Departs](https://github.com/p3ob7o/Departs).

Fetched and pruned remote-tracking refs. Local `main` was three commits behind and was fast-forwarded from `0f7060a` to `bc8b19b`, matching `origin/main`. Both existing local feature branches already matched their remote tips. Pushing all existing local branches returned “Everything up-to-date.” The only original uncommitted file was `AGENTS.md`; it is included in this documentation PR with the HERE departure endpoint corrected. Ignored files were preserved.

Every branch present at the beginning of the review:

| Branch | Tip | What it contains | Recommendation |
| --- | --- | --- | --- |
| `main` | `bc8b19b` | Current web app, shared API, native iOS app; merges PRs #5 and #6 | Keep as production source. Local and remote now agree. |
| `codex/deep-review-20260520` | `7efe5c6` | Earlier iOS/API repair: URL encoding, line metadata, station-local clocks, route failure isolation and map work | Fully merged via [#5](https://github.com/p3ob7o/Departs/pull/5). No unique commits remain; safe cleanup candidate. |
| `codex/ios-stop-line-summary` | `97c34d7` | All stop/line choices and selected-line filtering, already merged via #6; one remaining commit bumps iOS build 3 to 4 | Keep until [#7](https://github.com/p3ob7o/Departs/pull/7) is resolved. Recommend merging that bookkeeping change: its PR records a build-4 TestFlight upload. The upload was not independently reverified. Then retire the branch. |
| `claude/debug-app-display-1NJ3P` | `1fedc4b` | Early page wiring from merged #1, followed by two unique icon commits | Superseded by later icon work on main (`898f3fe`, `51b3c0f`, `76b2110`). Archive if wanted for history, then retire; no reason to merge the old branch wholesale. |
| `codex-v1` | `dfd77a8` | An alternative implementation of the initial TDD skeleton | Superseded prototype. Its map is placeholder DOM rather than the real Mapbox implementation, and it lacks the native app and later fixes. Archive as historical work; do not merge. |

“Superseded” is a code comparison judgment, not a claim that every commit was merged. The icon branch has two unique commits and the prototype has one. Those histories remain intact.

New branches are `fix/web-transit-reliability`, `fix/transit-times-and-validation`, `fix/ios-refresh-consistency`, and `fix/patched-runtime-dependencies`, corresponding to PRs #8–#11 below. Keep them until their PRs are resolved. `docs/project-audit-2026-11-15` contains this report and documentation corrections; retire it after its PR merges.

## What the application actually does

1. Requests the device's location.
2. Queries stops within **400 metres**, up to 50 places, through `/api/stops/nearby`.
3. Shows a map and stop/line information. On current main, iOS offers every line/direction but web exposes only the first line per stop.
4. Requests a departure board and a walking route when a selection is opened.
5. Shows up to four departures and the route, with system light/dark styling.

The web app uses Next.js 16.1.6, React 19.2.3, React hooks, and Mapbox GL. PR #11 updates Next.js to 16.4.6. The SwiftUI app targets iOS 17+, uses `@Observable` view models and MapKit, and calls the same production backend through an `APIService` actor. There is no account system, global application state store, or application database.

The Next.js routes hide server API keys and normalize provider responses:

- `/api/stops/nearby` → HERE `/v8/stations`; response cache header: 24 hours.
- `/api/departures` → HERE `/v8/departures`; line/direction filtering happens in the proxy; response cache header: 30 seconds.
- `/api/directions` → Mapbox walking directions; unwraps the first route; response cache header: one hour.

These headers are not an automatic client refresh mechanism. Neither client currently polls departure data or systematically refreshes it on foreground return. PR #10 adds a manual departure refresh and ticking iOS labels, but not automatic board fetching.

The original PRD/specs are historical design material: their 250-metre radius, Next.js 15 version, `/boards` endpoint, radius-circle overlay, and some proposed geolocation behavior do not describe the implementation. Pricing figures there were not verified and should not guide capacity planning. The code and this dated review distinguish implemented behavior from proposals.

## Findings and fixes

| Priority | Reproduced or code-supported problem | Fix PR |
| --- | --- | --- |
| High | Location timeout/unavailability falls through to a map with null coordinates, crashing the web app | [#8](https://github.com/p3ob7o/Departs/pull/8): recoverable location states, unsupported-browser handling, and tests |
| High | Web shows station-wide departures under the first line's heading; other lines cannot be chosen | [#8](https://github.com/p3ob7o/Departs/pull/8): every line/direction is selectable, and the request and heading use that selection |
| High | HERE real-time predictions are discarded as the display time; only the first platform board is read | [#9](https://github.com/p3ob7o/Departs/pull/9): predicted clock, all returned boards, chronological selection and preserved delay metadata; benefits both clients |
| High | Installed runtime dependencies have known advisories, including a critical rating for Next.js | [#11](https://github.com/p3ob7o/Departs/pull/11): patched Next.js and transitive packages; production audit now clean. Advisory ratings do not establish application exploitability. |
| Medium | A slow walking-route request blocks an already-ready web departure board | [#8](https://github.com/p3ob7o/Departs/pull/8): publish independent results immediately and cancel obsolete requests |
| Medium | Narrow map bounds remove valid nearby stops from the web list | [#8](https://github.com/p3ob7o/Departs/pull/8): show all returned nearby options, independent of the viewport |
| Medium | Web stop IDs are interpolated without encoding, retry unnecessarily reacquires GPS, and the heavy map is eagerly imported | [#8](https://github.com/p3ob7o/Departs/pull/8): encoded query parameters, direct retries, and a separately loaded map |
| Medium | Invalid nearby coordinates reach HERE; blank walking-coordinate components become zero; malformed route geometry can reach native indexing | [#9](https://github.com/p3ob7o/Departs/pull/9): finite/range/component validation, route shape checks and 10-second upstream deadlines |
| Medium | Web clocks use the device timezone and hardcoded 12-hour formatting | [#9](https://github.com/p3ob7o/Departs/pull/9): retain the station's clock while respecting locale |
| Medium | iOS pull-to-refresh can fetch twice; older responses can overwrite newer state | [#10](https://github.com/p3ob7o/Departs/pull/10): one request owner and per-load identity/cancellation guards |
| Medium | iOS countdowns do not tick and past departures display “Now” | [#10](https://github.com/p3ob7o/Departs/pull/10): periodic label updates, “Departed” for elapsed times and manual board refresh |
| Medium | API tests silently run in jsdom because the Vitest environment configuration is obsolete | [#11](https://github.com/p3ob7o/Departs/pull/11): explicit Node environment directives and guarded browser setup |

PR #8 also restores browser zoom, displays station names, gives rows room for wrapping, and rounds walking allowances up. Its browser fixtures now match the proxy's flat route response instead of returning an upstream Mapbox envelope.

## Verification and limits

Baseline `bc8b19b`: 133 of 134 web unit tests passed; lint had four errors and three warnings; production build passed; all 16 native tests passed. The failing web test expected departure fixtures without the line metadata already returned by the adapter. The browser suite initially could not launch because its required binaries were absent.

Regression evidence was captured before fixes: three web tests failed for null location and a pending route, nine API/data tests failed for predictions, platform boards and invalid coordinates, and three native tests failed for out-of-order results and old departures labeled “Now.”

The proposed PRs were combined locally without changing main or pushing an aggregate implementation branch:

- **159/159 web unit tests pass**, including API routes in Node.
- **30/30 browser tests pass** across Chromium/Pixel 7 and WebKit/iPhone 14 emulation.
- The original 12 browser scenarios also passed against installed Google Chrome on the web-fix branch.
- **Lint and the production build pass** on the combined changes.
- **20/20 native XCTest tests pass** on the changed iPhone 17 Pro simulator app.
- **Production dependency audit: zero known vulnerabilities.** The full audit still lists seven moderate entries in the development-only TypeScript ESLint/minimatch chain. A forced incompatible dependency override was not applied.
- Vercel checks for **all four fix PRs are successful**. Those checks establish deployment/build success, not end-to-end transit correctness.

Combined web verification used Node 24.22.0, Next.js 16.4.6 and Vitest 4.1.12. The browser installer stalled under the machine's Node 26 runtime and completed under Node 24. No global Node setting or installation-script approval policy was changed.

Production was checked separately through the shared browser's script interface. Its page displayed a client-side exception. The nearby-stop endpoint returned 17 stops for the documented Vienna test location, and selected-line departures and walking directions returned HTTP 200. A single observed departure request took about 1.15 seconds and a route request about 0.48 seconds; these are smoke-test observations, not representative latency benchmarks. The exact production exception cause was not established from a console stack.

Chrome's computer-use host was unavailable. The shared preview snapshot timed out twice, although its script interface worked. Vercel branch previews redirected to a login page. Therefore a signed-in visual check of deployed previews and the required Chrome production check remain outstanding. All opened shared-browser tabs were closed. None of these proposed fixes has been verified as a production release, because no PR was merged.

Suggested landing order: #11 (dependency patch), #8 (web recovery), #9 (shared data correctness), #10 (native consistency), and the existing #7 build-number bookkeeping. The independent #11 branch still has the baseline fixture-test failure until #8 or #9 is included; the combined suite is green.

### Remaining engineering work

- Add a repository CI workflow for unit tests, lint, build and browser tests; currently Vercel is the visible PR gate, and no repository workflow was present.
- Add foreground/visible-screen board refresh with request deduplication, freshness timestamps and an explicit stale/offline state. Avoid refetching walking directions with every board tick.
- HERE caps a board query at 50 results. Even after filtering improvements, a busy station can yield fewer than four departures for a selected service. Treat that as a provider-bound limit and investigate line-specific coverage rather than claiming completeness.
- Verify operator real-time coverage before promising live data everywhere. The Vienna smoke sample was scheduled data (`realTime: false`), and HERE documents real-time, timetable and estimated coverage separately.
- Before a public launch, address the lack of API rate limiting, establish provider usage alerts, and measure first-use success and field performance. No usage analytics were found in the repository, so the growth priorities below are hypotheses.

## Five improvements to make Departs more useful and encourage adoption

1. **Show the next catchable departure directly in the nearby list.** Display “49 → Volkstheater · 6 min · 3 min walk,” with a walking allowance and a clear distinction between live and scheduled data. Put the answer on the first screen and highlight services the user can reasonably reach. Start with a small number of visible stops to control API cost. Measure time to a useful departure and the proportion of first sessions that reach one.

2. **Make a live board users can trust while they wait.** Refresh departures while the screen is visible and on foreground return; show “Updated just now,” countdowns, delay changes, and a stale/offline state. Keep useful cached stop information when connectivity drops, without presenting expired times as live. Validate with repeated commuter use and measure stale-board incidents and return visits.

3. **Let users pin a few stops and directions, then expose them on the home screen.** Store favorites locally without an account; offer “home” and “work” shortcuts and an iOS widget that opens the corresponding board. This turns a discovery utility into a daily habit. Start with favorites, then add the widget if repeat use supports it. Measure seven-day retention and favorite-to-board opens. [Apple's WidgetKit guidance](https://developer.apple.com/documentation/WidgetKit/Developing-a-WidgetKit-strategy) supports opening a relevant app scene from a widget.

4. **Offer a useful path when location fails or 400 metres returns nothing.** Add manual stop/place search and an explicit “Search farther” action. Make coverage limits understandable. This helps denied-location users and travelers without turning the product into a full journey planner. Measure recovery from permission denial and empty results into a useful departure board.

5. **Make each stop board shareable and easy to keep.** Give boards stable links and QR codes that work without installing anything, with a home-screen install invitation after the first successful lookup. Pilot links with a few hotels, cafés or venues near well-covered stops; each link should open the useful local board immediately. Measure link-open → board-use → return-use conversion, rather than raw scans. [Web app installation guidance](https://web.dev/learn/pwa/installation) describes the manifest and platform-specific installation paths.

Start with catchable departures and freshness, then test favorites with a small commuter cohort. Use shareable boards to recruit new users only after the core information is dependable. Keep the “open and know what's leaving” focus: [Transit already puts upcoming nearby departures on its main screen](https://help.transitapp.com/article/93-how-to-use-transit), so Departs needs a faster, clearer first-use experience rather than more planning screens.

## Primary technical references

- [HERE departures: station-local timestamps, scheduled-time ordering, and limits](https://docs.here.com/transit/reference/public-transit-api-v8-getdepartures)
- [HERE coverage levels](https://docs.here.com/transit/docs/coverage)
- [Next.js 16.4.6 release](https://github.com/vercel/next.js/releases/tag/v16.4.6)
- [Remaining development minimatch advisory](https://github.com/advisories/GHSA-g3hv-75wg-m249)

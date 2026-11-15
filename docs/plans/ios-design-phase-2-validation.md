# Phase 2: answer-first list

Stop sections replace full-size cards and the paging button. Nearby pins appear in saved order above the stop sections; distant pins have a separate sheet. Swipe or hold a route to pin it, with a dismissible first-run hint and the detail pin button retained. Shared stop names within 150 metres merge. Running lines retain provider order, idle lines collapse, and countdown ticks do not change their partition. Presentation updates wait until scrolling/touch interaction ends.

The title menu and toolbar replace the large opening header. One freshness line replaces repeated stamps. Mode badges show a symbol and line number; leave advice uses the contrast-safe green/orange roles with a symbol. At accessibility sizes, walking detail and row status move to detail; stop names use the full header width. Only a shared locality prefix known as Wien or the selected area's name is hidden, and only in visible row text. Full directions remain in identities, detail and accessibility labels.

## Acceptance measurements

| Measure | Evaluation baseline | Result |
| --- | --- | --- |
| First answer, 402 × 874 pt | 319 pt | 169.7 pt, UI assertion |
| First answer, 375 × 667 pt | 277 pt | 128 pt, UI assertion |
| Visible departures, 402 pt | 1 in live sample | 8 fixtures; at least 9 complete live rows |
| Visible departures, 375 pt | 1 clipped live row | 8 fixtures; 6 complete live rows |
| Expanded idle rows before a running row | 3 of first 4 | 0; idle rows collapsed |
| Paging taps to reach running lines | up to 12 | 0; scroll loads sections |
| Opening request budget | 6 per-line requests | first 3 provider stop boards, then visible sections; 3 concurrent requests per kind |

Fixture capacity was expanded from one route to eight to measure density. The production read-only sample still returned 17 stops and 73 line/direction options at 48.20134, 16.34941. Samples were taken around 21:57–22:03 Vienna time on 15 November 2026. The 375-point live capture includes six running options, including later night departures; these are not claims that all services are imminent.

## Additive backend contract and fallback

`GET /api/departures?stopId=…&groupBy=line` returns `{groups: [{line, departures}], complete}`. Each group has up to four departures. All existing calls retain their array response, filtering, cache headers and host. No key is embedded in the app.

The spike keeps the existing one HERE request per provider stop, `maxPerBoard=50`, `maxPerTransport=4`, and timeout. `complete` is true only below the 50-departure cap. Missing lines in a complete response can be marked idle; at the cap they use per-line fallback. A legacy array disables the grouped attempt for the store session. Failed requests also fall back. In-flight stop requests are deduplicated, and periodic refresh does not progressively load offscreen stops.

The common grouped path needs at most three initial provider-board calls before lazy section loading. A merged physical stop can include several provider IDs, and capped responses or legacy production can require more calls; the concurrency bound remains three. Live HERE quota and latency for the new handler are **unverified**: this checkout has no provider credentials. Production verification exercises the old endpoint and the native fallback, not the new handler.

## Checks

- `npm ci`; 64 Vitest/MSW tests; lint; production backend build passed.
- Local HTTP `/api/departures?groupBy=line` without stopId returned JSON HTTP 400. Valid new provider calls were not tested live.
- 45 native unit tests and seven UI tests passed on a dedicated iPhone 17 Pro simulator, iOS 27.0. The seven UI flows also passed at 375 × 667. Normal simulator signing; all derived data and result bundles outside the repo.
- New unit tests cover grouped and legacy fallback, complete-board idle lines, countdown-stable partitioning, and deferred changes during interaction. The UI suite checks a countdown tick without reordering, density, swipe pinning/relaunch, direct entry, offline recovery, wider search and largest text.
- The full 402-point result is `/tmp/departs-p2-head.xcresult`; the small-screen result is `/tmp/departs-p2-small-final.xcresult`. A targeted opening-flow check measured one grouped departure request for the eight-line fixture, under the three-request initial budget.

## Captures

Before, default and largest text:

![Before default](https://github.com/p3ob7o/Departs/blob/feat/ios-design-phase-1-repairs/docs/screenshots/ios-design-phase-1/nearby-departures.png?raw=true)
![Before largest text](https://github.com/p3ob7o/Departs/blob/feat/ios-design-phase-1-repairs/docs/screenshots/ios-design-phase-1/nearby-at-accessibility-text-size.png?raw=true)

After, default and largest text:

![After default](https://github.com/p3ob7o/Departs/blob/feat/ios-design-phase-2-list/docs/screenshots/ios-design-phase-2/nearby-departures.png?raw=true)
![After largest text](https://github.com/p3ob7o/Departs/blob/feat/ios-design-phase-2-list/docs/screenshots/ios-design-phase-2/nearby-at-accessibility-text-size.png?raw=true)

Production and small-screen captures are in `docs/screenshots/ios-design-phase-2/`. No merge, deployment, release, TestFlight upload or version/build-number change. This draft targets Phase 1.

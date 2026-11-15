# Departs iOS roadmap

## Product direction

Departs is used in a pinch, on the go. Prioritize the time it takes to find a useful departure over maps, configuration, or additional screens. The owner retired the browser client on 15 November 2026; iOS is the sole product client. The Vercel API remains required infrastructure at the existing host.

The web retirement and runtime dependency patches are merged. Historical designs and the original review remain in `docs/archive/web/` and `docs/reviews/2026-11-15-project-audit.md`.

## Seven improvements in the native fast-answer implementation

1. **Answers on the opening screen.** Next two departure times, line, direction, stop, and walking time. Maps are secondary and created on demand.
2. **Conservative leave guidance.** Subtract walking time and a two-minute buffer from the first reachable departure. Explain when an earlier service looks too tight; withhold advice when data or location cannot support it.
3. **Useful content immediately.** Restore the last area, boards, and pins before networking. Keep results visible while location and fresh times arrive.
4. **Automatic freshness.** Refresh visible answers on foreground return and periodically while active. Keep rows stable, coalesce duplicate loads, and label saved information.
5. **Pinned stop and direction.** Local favorites, one-tap boards, and an App Shortcut that opens the selected pin directly. No account, widget extension, or notification permission required.
6. **Recovery on the go.** Manual place/address/stop search without location permission, explicit 400 → 800 → 1600 metre search expansion, retry actions, and saved boards after failed refreshes.
7. **Clear boarding and walking information.** Prominent stop and direction, clear live/scheduled labels, and a persistent walking-directions action to the exact stop coordinate. Do not invent platform or entrance data the provider does not supply.

See [implementation behavior and checks](ios-fast-answers.md). These features require a new native binary; a merged PR does not update installed apps.

## Release status on 15 November 2026

- [Backend PR #9](https://github.com/p3ob7o/Departs/pull/9) and [native PR #15](https://github.com/p3ob7o/Departs/pull/15) are merged. Production HTTP checks passed for nearby stops, selected-line departures, wider search, and walking directions. Native PR #15 supersedes [PR #10](https://github.com/p3ob7o/Departs/pull/10).
- **Departs 1.1 (5)** is uploaded to TestFlight, processed as `VALID`, and available for internal testing. App Store Connect confirmed the previous release was 1.0 (4). [Release PR #16](https://github.com/p3ob7o/Departs/pull/16) records the new version and supersedes the build-4 bookkeeping in [PR #7](https://github.com/p3ob7o/Departs/pull/7).
- Validation passed: 41 native unit tests, six native UI tests, 62 backend tests, backend type checking/lint/build, a distribution-signed Release package, and Apple's package validation. The Release app also displayed live-fetched departures and walking/leave guidance in the simulator.
- Complete physical-device acceptance, including Shortcuts, real GPS, and mobile-data startup time, before expanding the cohort. External testing is awaiting beta-review submission; no public App Store release has been submitted.

## Adoption work after validation

- Recruit a small TestFlight cohort around stops with verified realtime coverage. Observe whether users can find a reachable departure without opening multiple boards.
- Measure cold and warm time to first useful answer on a physical phone and ordinary mobile data. Three seconds is a target, not a measured promise from simulator fixtures.
- Verify accessibility text sizes, VoiceOver order, reduced location accuracy, foreground return, and poor connectivity on device.
- Add native sharing and an installation fallback once there is a public distribution URL. Keep the destination small; a browser transit app is outside scope.
- Establish provider usage alerts and request limits before wider distribution. Add CI once the simulator/runtime and signing setup are selected.

No analytics SDK or tracking service is added by this implementation.

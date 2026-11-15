# Departs iOS roadmap

## Product decision — 15 November 2026

The owner chose to drop the web app and focus all development on the iOS version. iOS is the sole product client. The Vercel API remains required infrastructure for transit data and walking directions. Web/iOS feature parity is no longer a goal.

The retirement removes browser components, map rendering, geolocation hooks, client fetch helpers, browser tests and their dependencies. The root URL becomes a plain-text notice; `/api/stops/nearby`, `/api/departures` and `/api/directions` keep their existing contract. The old client and designs remain recoverable in Git history and `docs/archive/web/`.

## Finish reliability work first

- Keep [#9](https://github.com/p3ob7o/Departs/pull/9): predicted departure times, all platform boards, input validation and upstream timeouts. Its scope is now backend-only.
- Keep [#10](https://github.com/p3ob7o/Departs/pull/10): prevent stale native refresh results, deduplicate nearby requests, tick countdown labels and add departure pull-to-refresh.
- Keep [#11](https://github.com/p3ob7o/Departs/pull/11): runtime dependency patches. The retirement branch is based on it; merge it first, then retarget the retirement PR to `main`.
- Keep [#7](https://github.com/p3ob7o/Departs/pull/7) as iOS build-number bookkeeping, subject to confirming the current TestFlight build before another upload.
- Retire web-only [#8](https://github.com/p3ob7o/Departs/pull/8). Its browser improvements are no longer needed.
- The retirement PR incorporates the report from [#12](https://github.com/p3ob7o/Departs/pull/12), which it supersedes. Preserve the audit as a dated historical record.

These fixes and the retirement are proposed changes until their PRs merge. Backend deployment and native app distribution are separate steps.

## Five native product priorities

These are proposals, not implemented features. Validate them with a small TestFlight cohort before expanding scope.

1. **Show the next catchable departure on the nearby screen.** Include the line, direction, departure countdown and walking allowance. Distinguish scheduled data from live predictions. Limit extra requests to visible, useful options. Success: a new user finds a reachable departure quickly, without opening several boards.

2. **Keep departure boards fresh and useful offline.** Refresh while a board is visible and on foreground return, deduplicate requests, display the last update, and mark stale data. Refresh departures independently of walking directions. Success: users can wait at a stop without manually reopening the app or mistaking expired data for live information.

3. **Pin recurring stops and directions.** Store a few favorites locally without an account. Start with one-tap access in the app; add a WidgetKit shortcut to a favorite board once repeated use supports it. Success: commuters return and reach their regular board faster.

4. **Recover when location or nearby coverage fails.** Offer manual stop/place search and an explicit search-farther action. Explain permission and provider coverage limits. Success: denied-location and empty-result sessions still reach a useful board.

5. **Make a useful board easy to share and invite people to the app.** Use the native share sheet for a stop and direction. Plan deep links that open the corresponding native screen; provide an honest installation fallback once a public distribution URL exists. Before launch, recruit a small TestFlight cohort around well-covered stops and collect feedback. A small link destination or association file can support this without rebuilding a browser transit app. Success: invited users open a useful board and return.

## Release gates

- Native tests and a release build pass; verify location denial, poor connectivity, foreground return and the selected-line board on device or simulator.
- API tests, lint, production build and HTTP checks pass. Keep the existing host and JSON contract for installed builds.
- Verify realtime coverage for the initial operators and display scheduled data honestly.
- Establish provider usage alerts and request limits before wider distribution.
- Add CI for native and backend checks. No browser test or PWA work is required.

The first priorities are correctness and freshness, then catchable departures and favorites. Measure first useful board and repeat use only after defining the smallest appropriate measurement approach; no new analytics integration is part of this transition.

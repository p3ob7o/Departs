# Departs iOS roadmap

## Product direction

On 16 November 2026 the owner defined Departs as two screens showing which transport is available around you. Each screen has a square map above a short list. Home shows nearby lines leaving within an hour, once per destination at the nearest qualifying stop. A row opens the line's walking map and next four departures. The [approved plan](plans/ios-two-screens.md) specifies the exact selection rules, states and acceptance gates.

The owner retired the browser client on 15 November. iOS is the sole product client; the Vercel API remains at its existing host for installed builds. Historical web designs stay in `docs/archive/web/`.

## Current implementation

- Home selects the eight rows in the Vienna sample from 17 platforms. A single batch replaces departure fan-out; opening takes one stops request, one batch and one walk per listed physical stop.
- Fresh rows show a single countdown. Saved rows retain their position and show clock times with a recovery action. Cached content appears before networking.
- The line screen keeps the full destination visible, shows up to four departures and opens Apple Maps walking directions to the platform. Live times carry a symbol and full-minute delay. There is no scheduled label or leave advice.
- Local pins, recent-area search, App Shortcuts and explicit wider search remain. Pins are still a product trial under O8.
- Both screens support accessibility text, with the map scrolling away at accessibility sizes. iPhone returns to portrait only. iOS 26 remains the minimum.

See [native behavior](ios-fast-answers.md) and the [final validation](plans/ios-two-screens-phase-3-validation.md). The old fast-answer roadmap's advice, optional-map and split-view work is superseded.

## Release sequence

The test baseline was Departs 1.1 (6). After the implementation checks passed, the owner requested the update on 16 November. **Departs 1.2 (7) is uploaded, VALID and IN_BETA_TESTING for internal testers.** The [release record](releases/1.2-7.md) contains package, production and processing verification.

Plan PR #26 and additive backend PR #27 merged into `main`, and Vienna/Berlin production checks passed before upload. Native home #28, line #29, cleanup #30 and release #31 remain stacked drafts pending separate merge approval. Each must land in `main` in that order, retargeting after the previous merge. Merging into an already-merged phase branch does not update `main`.

The uploaded build uses the tested release branch. Backend-first is satisfied. Complete the remaining physical-device checks with TestFlight; no external beta review or public App Store release was submitted.

## Next decisions and checks

- Rewrite the [iPhone Duo plan, PR #18](https://github.com/p3ob7o/Departs/pull/18) and [iPad plan, PR #19](https://github.com/p3ob7o/Departs/pull/19) for map and list side by side. Both predate this design. Device support and the Xcode upgrade remain outside this work.
- Check map selection, long destinations and empty nighttime results on a phone. Observe whether people find the available service without opening several lines.
- Verify VoiceOver speech, haptics, GPS accuracy, foreground return, Shortcuts discovery and Home Screen icon appearances on a signed device.
- Measure cold/warm startup on mobile data and provider quota/cost under the batch model. Check a capped hub and operators with realtime coverage. The Vienna sample supplied scheduled data only.
- Decide whether to keep pins after observing use. Widgets, Live Activities, notifications, accounts, German and journey planning remain out of scope.

No analytics SDK or tracking service is added.

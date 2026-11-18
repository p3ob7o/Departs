# Departs iOS roadmap

## Product direction

On 16 November 2026 the owner defined Departs as two screens showing which transport is available around you. Each screen has a square map above a short list. Home shows nearby lines leaving within an hour, once per destination at the nearest qualifying stop. A row opens the line's walking map and next four departures. The [approved plan](plans/ios-two-screens.md) specifies the exact selection rules, states and acceptance gates.

Later that day the owner made it stricter: "This app is minimalistic and opinionated. It looks in a 400m radius, period." The wider search and place search are gone. With location off, the app shows pinned routes only.

The owner retired the browser client on 15 November. iOS is the sole product client; the Vercel API remains at its existing host for installed builds. Historical web designs stay in `docs/archive/web/`.

## Current implementation

- Home selects the eight rows in the Vienna sample from 17 platforms. A single batch replaces departure fan-out; opening takes one stops request, one batch and one walk per listed physical stop.
- Fresh rows show a single countdown. Saved rows retain their position and show clock times with a recovery action. Cached content appears before networking.
- The line screen keeps the full destination visible, shows up to four departures and opens Apple Maps walking directions to the platform. Live times carry a symbol and full-minute delay. There is no scheduled label or leave advice.
- Local pins and App Shortcuts remain. Pins are still a product trial under O8. There is no search of any kind. Since the owner's corrections of 17 and 18 November, home has no top bar: its square map starts under the status bar and stays centred on you.
- Both screens support accessibility text, with the map scrolling away at accessibility sizes. iPhone returns to portrait only. iOS 26 remains the minimum.

See [native behavior](ios-fast-answers.md) and the [final validation](plans/ios-two-screens-phase-3-validation.md). The old fast-answer roadmap's advice, optional-map and split-view work is superseded.

## Release sequence

The test baseline was Departs 1.1 (6). After the implementation checks passed, the owner requested the update on 16 November. **Departs 1.2 (7) is uploaded, VALID and IN_BETA_TESTING for internal testers.** The [release record](releases/1.2-7.md) contains package, production and processing verification.

Plan PR #26 and additive backend PR #27 merged into `main`, and Vienna/Berlin production checks passed before upload. Native home #28, line #29, cleanup #30 and release #31 form the implementation stack. The owner explicitly approved landing all four in `main` in that order, retargeting after each previous merge. Merging into an already-merged phase branch does not update `main`.

The uploaded build uses the tested release branch. Backend-first is satisfied. Complete the remaining physical-device checks with TestFlight; no external beta review or public App Store release was submitted.

**Departs 1.2 (8) followed on 17 November: uploaded, VALID and IN_BETA_TESTING for internal testers.** It removes place search and the wider search, and fixes two defects found in the test of 1.2 (7): the list started over about every five minutes on a phone, and a coarse location fix left home waiting forever. [PR #32](https://github.com/p3ob7o/Departs/pull/32) is merged. The [release record](releases/1.2-8.md) lists the checks and seven open findings that need the owner's decision.

**Four corrections followed the owner's use of 1.2 (8) on 17 November**, recorded as O13 to O16 in the [plan's second amendment](plans/ios-two-screens.md#second-amendment-the-map-at-the-top): home loses its bar and the map is centred on you at all times, a stop's name leaves with its last line, destinations start at one x, and times read "7 min". They are not in a build yet; the next would be 1.2 (9), with the owner's approval.

## Next decisions and checks

- Rewrite the [iPhone Duo plan, PR #18](https://github.com/p3ob7o/Departs/pull/18) and [iPad plan, PR #19](https://github.com/p3ob7o/Departs/pull/19) for map and list side by side. Both predate this design. Device support and the Xcode upgrade remain outside this work.
- Review A20 and A23 in the [second amendment](plans/ios-two-screens.md#second-amendment-the-map-at-the-top): what the map centres on, and how a pinned stop name looks.
- Decide the seven open findings in the [1.2 (8) record](releases/1.2-8.md#open-findings-not-changed-in-this-build). The first is a defect: a stop with no departures is shown as a failed load, seen at Berlin Alexanderplatz.
- With build 8 on a phone: leave the app open in one place for ten minutes, walk a few hundred metres, and try Location off and Precise Location off. With the next build, check that the map follows a walk smoothly and stays put with Precise Location off.
- Check map selection, long destinations and empty nighttime results on a phone. Observe whether people find the available service without opening several lines.
- Verify VoiceOver speech, haptics, GPS accuracy, foreground return, Shortcuts discovery and Home Screen icon appearances on a signed device.
- Measure cold/warm startup on mobile data and provider quota/cost under the batch model. Check a capped hub and operators with realtime coverage. The Vienna sample supplied scheduled data only.
- Decide whether to keep pins after observing use. Widgets, Live Activities, notifications, accounts, German and journey planning remain out of scope.

No analytics SDK or tracking service is added.

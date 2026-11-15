# iPhone Duo adaptation plan

| | |
| --- | --- |
| Status | Proposal. This branch changes no app code. |
| Date | 15 November 2026 |
| Branch | `feat/iphone-duo-adaptation`, based on `feat/ios-design-improvements` |
| Builds on | [iOS design evaluation and improvement plan](ios-design-improvements.md), Phases 1, 2 and 5 |
| Sibling | [iPad adaptation plan](ipad-adaptation.md) |

## Summary

iPhone Duo is Apple's folding iPhone, on sale since 23 October 2026 with iOS 27.1. It gives Departs two new canvases:

- **The cover display, closed: 466 × 678 pt.** It is wider and much shorter than any other current iPhone. This is where Departs will be used most, one-handed and in a hurry.
- **The inner display, open: about 951 × 669 pt, regular width.** It is two cover displays side by side, joined at the fold.

Where Departs stands:

- The code is clean against Apple's resize checklist. Nothing reads the main screen, the device idiom, or the orientation.
- The design is not ready. On a display this short, today's header and cards show about one and a half answers. On the inner display the single phone column stretches to fill the width.
- **This Mac cannot test any of it yet.** It has Xcode 27.0, which has no iPhone Duo simulator. Apple's simulator ships with Xcode 27.1.
- **The first build made with Xcode 27.1 changes how Departs looks on every Duo**, whether or not any of this plan is done. The system moves the app's bars to a vertical strip on the side. Apple asks developers to check their content against that before shipping.
- From April 2027 App Store submissions need iPhone Duo screenshots.

The plan has five steps. Phase 0 installs the toolchain, captures the baseline, and replaces this document's estimates with measurements. Phase 1 designs for the cover display. Phase 2 uses the inner display for list and detail side by side. Phase 3 is optional work for the folded poses. Phase 4 ships.

## What is known about the device

"Apple" means Apple's developer or design documentation. "Derived" means calculated here. "Unverified" means reported by third parties or not yet measured.

| Fact | Value | Basis |
| --- | --- | --- |
| Cover display | 5.4 in, 1398 × 2034 px, so 466 × 678 pt at 3x | Apple screenshot specification, and Derived |
| Cover size classes | Compact width, regular height in portrait. Compact in both in landscape. Same as other iPhones. | Apple |
| Inner display panel | 7.6 in, 1878 × 2670 px | Unverified (press specifications) |
| Inner display canvas | About 951 × 669 pt in landscape. Apple's screenshot size is 2007 × 2853 px, which is 669 × 951 pt at 3x. | Derived. Confirm in Phase 0. |
| Inner size classes | Regular width and regular height, in both orientations | Apple |
| How it opens | Like a book. 84.1 mm wide closed, 164.6 mm open, 117.8 mm tall either way. The fold is vertical in the natural open pose. | Unverified (press specifications) |
| Bars | On the cover display, and on the inner display in landscape, the system moves the status bar, toolbars and tab bars to a vertical strip on one side. The inner display in portrait keeps horizontal bars. The strip stays on the same physical side in right-to-left languages. | Apple |
| Orientation | The inner display does not honor an app's supported orientations. Apple says to lay out by size class, never by orientation. | Apple |
| Split View | Two apps, or two windows of one app, share the inner display. Each puts its controls on its outer edge. | Apple |
| Split View size classes | Not published. Expect compact width. | Unverified |
| Reserved regions | The cover camera, always. The inner camera, while in use. The fold, while the device is partially folded. | Apple |
| System containers | Split views, sheets, alerts and menus adapt to the fold on their own. A split view moves to equal panes when the device is partially folded. | Apple |
| New layout APIs | `ArrangementView` and reserved regions need iOS 27.1. Toolbar visibility priorities and the system overflow menu are reported as iOS 27. | Apple for the APIs. Version numbers partly Unverified. |
| App Store | Screenshot sizes: cover 1398 × 2034 px, inner 2007 × 2853 px. Submitting them adds a "made for iPhone Duo" badge. | Apple |
| Screenshot deadline | April 2027. Apple's news post says all submissions. Its specification page says apps built with the iOS 27.1 SDK or later. | Apple, with a discrepancy |

How a build behaves depends on the SDK it was made with:

| Built with | Closed | Open |
| --- | --- | --- |
| iOS 26 SDK or earlier | Content sits beside the status bar and camera | Phone-sized window centered on the inner display |
| iOS 27.0 SDK. This is the Xcode on this Mac, so presumably Departs 1.1 (5). | Resizes between displays | Fills most of the inner display and avoids the status bar on the right |
| iOS 27.1 SDK or later | Edge to edge, bars in the vertical strip | Edge to edge, bars in the vertical strip in landscape |

## Where Departs stands today

Audit against Apple's "fix patterns" list:

| Pattern | Departs | Status |
| --- | --- | --- |
| Sizing from `UIScreen.main` | Not used | OK |
| Layout from device or interface orientation | Not used | OK |
| Layout from `userInterfaceIdiom` | Not used | OK |
| Device-size checks | None | OK |
| Full-bleed media that assumes an aspect ratio | None | OK |
| `UIRequiresFullScreen` | Not set | OK |
| Scene-based life cycle | SwiftUI `WindowGroup` | OK |
| Supported orientations | Portrait only. The inner display ignores this, so every screen must work wider than tall. | Design work |
| Multiple scenes | Declared in the built Info.plist, but each window creates its own store and location service | Fix in improvements Phase 5 |
| Bars | The walking-directions bar is a custom safe-area inset. The area, locate and map buttons and the filter sit in the content. The system cannot move any of them to the side strip. | Design work |
| Toolbar items | The pin item is a symbol with no title | Design work |
| Fixed sizes | 40-pt badge, 250-pt route map | Minor |

Expected appearance of Departs 1.1 (5), until Phase 0 measures it:

- **Closed.** The cover display is 678 pt tall. The 667-pt iPhone SE capture in the improvements plan is a close stand-in: the first answer starts about 40% of the way down, one full card fits, and the second is cut above its leave advice.
- **Open.** The same single column, stretched across roughly 880 pt. The iPad capture in the iPad plan shows the effect: content against the left edge, the pin a hand's width away, a walking button as wide as the display.

## Design principles for the Duo

1. **The cover display is the primary surface.** Departs is used in a pinch, and a closed Duo is what comes out of a pocket.
2. **Height is the scarce resource.** Both displays are under 680 pt tall in their natural poses. Nothing horizontal sits above or below the answers.
3. **One layout per width, not per pose.** Compact width on the cover display, regular width on the inner display. Poses refine it and never replace it.
4. **Opening the device adds a level. It does not change the app.** The cover shows the list or a board. The inner display shows the list and a board.
5. **Use the system's bars.** Apple's guidance is to follow the vertical layout, give every toolbar item a title and a symbol, keep text-only buttons to a minimum, and use the system overflow menu.

## Cover display, closed

```
466 × 678 pt
┌──────────────────────────────────────────┬──────┐
│ Near you ▾ · 400 m · updated just now    │  ◐   │  camera, status
│ PINNED                                   │ 9:41 │
│ ▐49▌ Hütteldorf             Leave in 1   │      │
│      Volkstheater · 3 min      7 · 12    │  ⌕   │  search
│ SIEBENSTERNGASSE · 1 MIN WALK            │  ➤   │  locate
│ ▐13A▌ Skodagasse            Leave in 4   │  ⊞   │  map
│       scheduled                7 · 17    │      │
│ ▐49▌ Hütteldorf, Bujattig…  Leave in 2   │      │
│      live · 3 min late         5 · 11    │      │
│ ▐52▌ Baumgarten             Leave in 6   │      │
│      live                      9 · 19    │      │
│ 3 lines with nothing soon             ›  │      │
│ KIRCHENGASSE · 4 MIN WALK                │      │
│ ▐49▌ Parlament/Volkstheater Leave in 3   │      │
└──────────────────────────────────────────┴──────┘
```

- The list is the compact layout from the improvements plan, unchanged. The header is one line that scrolls with the content.
- Search, locate and map are toolbar items, so the system places them in the strip. The strip costs width, not height.
- No custom bar appears at the top or the bottom.
- The search sheet has about 250 pt above the keyboard. It opens on recent places and has no footer text.

Detail on the cover display:

```
┌──────────────────────────────────────────┬──────┐
│ ▐49▌ Hütteldorf                          │  ◐   │
│ Volkstheater · 3 min walk · 280 m        │  ‹   │  back
│ ┌──────────────────────────────────────┐ │  ⇢   │  walking directions
│ │ ● Leave in 1 min                     │ │  ⚑   │  pin
│ │ to catch the 19:30 · live            │ │  ↻   │  refresh
│ └──────────────────────────────────────┘ │  …   │  overflow: map
│ in 7 min    19:30   ◉ live               │      │
│ in 12 min   19:35   ◔ scheduled          │      │
│ in 22 min   19:45   ◉ live · 3 min late  │      │
└──────────────────────────────────────────┴──────┘
```

- Order from the top of the strip: back, then walking directions as the prominent action, then pin, refresh and the overflow menu. This is Apple's standard placement order.
- Walking directions shows as a symbol here and as a labeled button on other iPhones. One toolbar item serves both.
- Visibility priorities keep walking directions and pin on screen longest. The map overflows first.

Cover display in landscape (678 × 466 pt, compact in both dimensions) happens when the phone stands like a tent. The list stays one column. The detail screen places the advice card beside the board. This is the compact-height work in improvements Phase 5.

## Inner display, open

Natural open pose, landscape:

```
about 951 × 669 pt                       fold
┌─────────────────────────────────┬─────────────────────────────┬──────┐
│ Near you ▾              ⌕   ➤   │ ▐49▌ Hütteldorf             │  ◐   │
│ within 400 m · updated just now │ Volkstheater · 3 min walk   │ 9:41 │
│ PINNED                          │ ┌─────────────────────────┐ │      │
│▌▐49▌ Hütteldorf    Leave in 1  ▐│ │ ● Leave in 1 min        │ │  ⇢   │
│ SIEBENSTERNGASSE · 1 MIN WALK   │ │ to catch the 19:30      │ │  ⚑   │
│ ▐13A▌ Skodagasse   Leave in 4   │ │ ░░ walking route map ░░ │ │  ↻   │
│ ▐49▌ Hütteldorf, … Leave in 2   │ └─────────────────────────┘ │      │
│ ▐52▌ Baumgarten    Leave in 6   │ in 7 min   19:30  ◉ live    │      │
│ 3 lines with nothing soon    ›  │ in 12 min  19:35  ◔ sched.  │      │
│ KIRCHENGASSE · 4 MIN WALK       │ OTHER LINES AT THIS STOP    │      │
└─────────────────────────────────┴─────────────────────────────┴──────┘
```

- **Two panes that meet at the fold.** The left pane is the list the cover display showed. The right pane is the selected board.
- **Controls stay with their content.** Search and locate sit above the list pane. Pin, refresh and walking directions belong to the board and sit in the strip.
- **The route map is visible by default** in the board pane, because there is room. It is created after the answers render.
- **Nothing selected.** The right pane shows the nearby-stops map. Selecting a pin selects that stop in the list (decision 3).
- **The list is never hidden.** If a pane would be narrower than 320 pt, the layout collapses to the compact stack.

Rotated open pose, portrait (about 669 × 951 pt): bars return to horizontal and the fold runs across the middle. The two panes remain, at roughly 320 and 349 pt.

Partially folded like a book: the system moves the split view to equal panes. Each pane keeps its own margins and nothing spans the fold.

Split View with another app: Departs gets about half the width and is expected to report compact width. The compact layout applies with the strip on Departs's outer edge. Safe-area insets are asymmetric, so no layout may assume equal left and right insets.

Two Departs windows: possible once improvements Phase 5 gives the app one shared store. It would let someone watch two boards side by side (decision 4).

## Continuity

Opening, closing, rotating and folding resize the scene. The app is not relaunched. These must hold across every transition:

| State | Rule |
| --- | --- |
| Selected board | Open on a board: the same board appears in the right pane with its row selected. Close: the same board is on screen. |
| List position | The scroll position is kept. |
| Area search | An open sheet stays open with its text and results. |
| Map | The camera and selected stop are kept. |
| Loading | A resize alone triggers no network request and cancels none. |
| Controls | The same actions in the same order in every pose. Overflow may hide items but never removes them. |

## Phases

### Phase 0. Baseline and toolchain gate (S)

No design change.

1. Install Xcode 27.1 alongside or in place of 27.0.
2. Run current `main` on the iPhone Duo simulator in Device Hub: closed in portrait and landscape, open in landscape and portrait, partially folded on both axes, Split View on each side.
3. Run the six UI tests on the Duo simulator, closed and open.
4. Build once with the 27.1 SDK and repeat step 2 to see the vertical strip.
5. Save the captures under `docs/screenshots/` and replace the "Expected appearance" section above with what was observed.

Questions Phase 0 must answer:

| # | Question |
| --- | --- |
| 1 | What are the inner display's point size and safe-area insets, and how wide is the strip? |
| 2 | Where does an inline navigation title go when bars are vertical? |
| 3 | What size classes and widths does an app get in Split View? |
| 4 | How is a portrait-only build shown on the inner display in each orientation? Apple's own statements differ. |
| 5 | Can a second Departs window be opened today, given the scene manifest? |
| 6 | How tall is a sheet on each display, with and without the keyboard? |
| 7 | Can `xcodebuild` select a pose for UI tests, or does that need Device Hub? |

Gate: decide whether release builds may move to Xcode 27.1 before Phase 1 is finished (decision 2).

### Phase 1. Cover display (M)

Needs improvements Phases 1 and 2, and Phase 5 item 4 (standard bars).

Acceptance on the cover display at the default text size:

- At least six options with a departure are visible without scrolling at the Vienna test location.
- No app bar is drawn horizontally at the top or bottom in portrait.
- Every action is in the strip or its overflow menu, in the same order as on other iPhones.
- On the detail screen the advice card and two departures are visible without scrolling.
- At the largest text size the first answer and its advice are on the first screen.
- The search sheet shows at least three results above the keyboard.
- Every control is at least 44 × 44 pt.

### Phase 2. Inner display (M to L)

Needs improvements Phase 5 items 1 to 5.

Acceptance:

- In landscape the list and a board are both visible and meet at the fold.
- Every row of the continuity table passes, each with a UI test where the simulator allows it.
- In Split View, on either side, nothing sits under the neighboring app's controls.
- Partially folded, no text or control crosses the fold.
- The behavior of a second window matches decision 4.

### Phase 3. Poses (S to M, optional, iOS 27.1 and later)

- **Fold-aware details.** Use reserved regions to keep the advice card and map focus clear of the fold in any layout the system does not already adapt.
- **Glance board.** With the device half open on a table, or standing as a tent, show the selected board in large type on the upright half: leave advice and the next two departures, readable from across a room. Controls stay on the flat half. `ArrangementView` is the intended container. It must not hold navigation or sit inside a scroll view, so it wraps the board pane only.
- The hinge-angle API is for effects, not layout. Departs does not need it.

Everything here is behind availability checks. The deployment target stays at iOS 17.

### Phase 4. Release (S)

- Capture cover and inner screenshots at Apple's sizes and check them in App Store Connect's preview tool.
- Run a TestFlight pass on a physical Duo: one-handed reach on the closed device, outdoor legibility, real open and close, real GPS.
- Update `CLAUDE.md`, `AGENTS.md`, the roadmap and `docs/ios-fast-answers.md` for the new layouts and the Xcode requirement.

## Decisions needed

| # | Decision | Recommendation |
| --- | --- | --- |
| 1 | Order of the two adaptations | Duo first. It is a phone people carry, it is already on sale, and its screenshots have a date. Its inner-display layout is most of the iPad layout. |
| 2 | When release builds move to Xcode 27.1 | After Phase 0 shows the vertical strip with today's design. If that looks acceptable, move at once. If not, stay on 27.0 until Phase 1 lands. |
| 3 | Right pane with nothing selected | The nearby-stops map. The alternative is to select the first answer automatically. |
| 4 | Two Departs windows side by side | Support after the shared store exists. Until then, consider declaring a single scene. |
| 5 | Glance board | Defer until Phases 1 and 2 have shipped. |
| 6 | Acceptance hardware | Phase 4 needs a physical Duo. The simulator cannot judge reach, glare, or the hinge. |

## Risks and unknowns

- **Geometry is partly derived.** The inner canvas size, the strip width and the Split View widths are estimates until Phase 0.
- **New APIs.** `ArrangementView` and reserved regions are weeks old. Signatures here come from Apple's Tech Talks and must be checked against the 27.1 SDK.
- **Request volume.** The inner display shows more rows and a board at once. The request budget from improvements decision 1 has to cover it.
- **Test automation.** Driving poses may need Device Hub. The repository has no CI yet.
- **Dependency on the improvements plan.** If its row design or split navigation is declined, Phases 1 and 2 here need a new basis. The minimum is toolbar-only actions and a shorter header.
- **Effect of the 27.1 SDK elsewhere.** Apple describes Duo-specific changes only. Confirm with the existing iPhone 17 Pro test run on the first 27.1 build.

## Verification matrix

| Check | Closed | Open | Folded | Split View |
| --- | --- | --- | --- | --- |
| Six UI flows | ✓ | ✓ | | |
| Continuity table | to open | to closed | ✓ | ✓ |
| Largest text size | ✓ | ✓ | | ✓ |
| Dark mode | ✓ | ✓ | | |
| Right-to-left language | ✓ | ✓ | | ✓ |
| VoiceOver order | ✓ | ✓ | | |
| Resize sweep in the resizable simulator and iPhone Mirroring | 320 to 1000 pt wide | | | |

## Out of scope

Live Activities and the Dynamic Island, widgets, the camera accessories for the cover display, and custom hinge effects. A Live Activity for "Leave in N min" is the obvious later use of the strip.

## Sources

Apple:

- [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo), Human Interface Guidelines, 9 September 2026
- [Three steps to prepare your app for iPhone Duo](https://developer.apple.com/iphone-duo/prepare/)
- [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/), Tech Talk
- [Strike a pose with adaptive layouts on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111463/), Tech Talk
- [Prepare and submit your apps for iPhone Duo](https://developer.apple.com/news/?id=kkphp5qo), news, 5 October 2026
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo), documentation. Linked by Apple but not read for this plan.

Third party, for hardware specifications and dates only:

- [iPhone Duo roundup](https://www.macrumors.com/roundup/iphone-duo/), MacRumors

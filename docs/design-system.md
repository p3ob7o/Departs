# Departs - Design System

## 1. Brand Identity

### Logo
- **Icon**: A split-flap display showing the letter "D" with a small arrow (→) beneath it, referencing airport/train station departure boards.
- **Shape**: Rounded square (iOS icon radius), dark background (#1C1C1E).
- **Wordmark**: "Departs" set in SF Pro Display Bold (or Inter Bold as web fallback).
- **Usage**: The icon is used as the app icon / favicon / PWA icon. The wordmark appears only on splash/loading screens, never in the app UI itself.

### Icon Sizes
| Context | Size |
|---------|------|
| App icon (PWA manifest) | 512x512, 192x192, 180x180 |
| Favicon | 32x32, 16x16 |
| Apple touch icon | 180x180 |

## 2. Color Palette

### Light Mode

| Token | Hex | Usage |
|-------|-----|-------|
| `--color-bg-primary` | `#FFFFFF` | Bottom sheet background, main surfaces |
| `--color-bg-secondary` | `#F2F2F7` | Page background behind the map |
| `--color-bg-tertiary` | `#E5E5EA` | Divider lines, subtle borders |
| `--color-text-primary` | `#1C1C1E` | Headings, primary text, departure times |
| `--color-text-secondary` | `#8E8E93` | Subtitles, line descriptions, clock icons |
| `--color-text-tertiary` | `#C7C7CC` | Chevrons, placeholder text |
| `--color-accent` | `#007AFF` | Radius circle, user location halo, links |
| `--color-stop-pin` | `#34C759` | Transit stop map pin |
| `--color-user-dot` | `#007AFF` | User location dot on map |
| `--color-route` | `#007AFF` | Walking route dashed line |

### Dark Mode

| Token | Hex | Usage |
|-------|-----|-------|
| `--color-bg-primary` | `#1C1C1E` | Bottom sheet background, main surfaces |
| `--color-bg-secondary` | `#000000` | Page background behind the map |
| `--color-bg-tertiary` | `#38383A` | Divider lines, subtle borders |
| `--color-text-primary` | `#FFFFFF` | Headings, primary text, departure times |
| `--color-text-secondary` | `#8E8E93` | Subtitles, line descriptions, clock icons |
| `--color-text-tertiary` | `#48484A` | Chevrons, placeholder text |
| `--color-accent` | `#0A84FF` | Radius circle, user location halo, links |
| `--color-stop-pin` | `#30D158` | Transit stop map pin |
| `--color-user-dot` | `#0A84FF` | User location dot on map |
| `--color-route` | `#FFFFFF` | Walking route dashed line |

### Map Styles
- Light: `mapbox://styles/mapbox/light-v11`
- Dark: `mapbox://styles/mapbox/dark-v11`

## 3. Typography

The app follows iOS system typography conventions using the SF Pro family, with Inter as the web fallback.

### Font Stack
```css
font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'SF Pro Text',
             'Inter', 'Segoe UI', Roboto, sans-serif;
```

### Type Scale

| Token | Size | Weight | Line Height | Usage |
|-------|------|--------|-------------|-------|
| `heading-lg` | 22px | Bold (700) | 28px | Section headers ("Departures:") |
| `heading-md` | 17px | Semibold (600) | 22px | Transport type labels ("Subway", "Tram") |
| `body` | 17px | Regular (400) | 22px | Departure times, line descriptions |
| `body-sm` | 15px | Regular (400) | 20px | Secondary line info ("Line 1 to Grand Central") |
| `caption` | 13px | Regular (400) | 18px | Map labels ("250m"), metadata |

### Text Colors
- Primary content uses `--color-text-primary`
- Secondary/supporting content uses `--color-text-secondary`
- Tertiary/decorative elements use `--color-text-tertiary`

## 4. Spacing & Layout

### Spacing Scale
```
4px  - xs    (tight padding, icon gaps)
8px  - sm    (list item internal spacing)
12px - md    (horizontal padding in rows)
16px - lg    (section padding, bottom sheet horizontal margin)
20px - xl    (vertical spacing between sections)
24px - 2xl   (top padding of bottom sheet content)
```

### Layout Constants

| Element | Value |
|---------|-------|
| Screen width | 100vw (mobile only, max 430px) |
| Bottom sheet border radius | 16px (top-left, top-right) |
| Bottom sheet drag handle | 36px wide, 5px tall, centered, `--color-bg-tertiary` |
| Map area height (Screen 1) | ~55% of viewport |
| Map area height (Screen 2) | ~50% of viewport |
| Bottom sheet min height | ~45% of viewport |
| Safe area bottom padding | `env(safe-area-inset-bottom)` |

## 5. Components

### 5.1 Bottom Sheet
- White (light) or dark gray (dark) surface with rounded top corners (16px radius).
- Drag handle: centered, 36x5px, rounded, tertiary color.
- Content area has 16px horizontal padding, 24px top padding (below handle).
- Scrollable when content exceeds visible area.
- No draggable resize behavior in v1 — fixed position.

### 5.2 Stop Row (Screen 1)
```
┌─────────────────────────────────────────────┐
│ [Icon]  Transport Type          [Chevron]   │
│         Line X to Destination               │
├─────────────────────────────────────────────┤
```
- Height: 64px
- Left: Transport icon (40x40px, see Icons below)
- Center: Two-line text block
  - Line 1: Transport type in `heading-md`
  - Line 2: Line + direction in `body-sm`, secondary color
- Right: Chevron icon (›), tertiary color
- Bottom border: 1px solid `--color-bg-tertiary`, inset 68px from left
- Touch target: full row, minimum 44px height

### 5.3 Departure Row (Screen 2)
```
┌─────────────────────────────────────────────┐
│ 12:15 PM                          [Clock]   │
├─────────────────────────────────────────────┤
```
- Height: 52px
- Left: Time in `body` weight, primary color
- Right: Clock icon (20x20px), secondary color
- Bottom border: 1px solid `--color-bg-tertiary`

### 5.4 Departure Header (Screen 2)
```
┌─────────────────────────────────────────────┐
│ Departures:                                 │
│ Subway Line 1 to Grand Central              │
└─────────────────────────────────────────────┘
```
- "Departures:" in `heading-lg`, bold, primary color
- Line info in `body-sm`, secondary color
- 8px gap between lines
- 20px bottom margin before departure list

### 5.5 Map Markers

#### User Location
- Blue dot: 12px diameter, `--color-user-dot`
- Halo: 24px diameter, `--color-user-dot` at 20% opacity
- Pulsing animation (subtle, 2s period)

#### 250m Radius Circle (Screen 1)
- Stroke: 2px, `--color-accent`
- Fill: `--color-accent` at 8% opacity
- Label: "250m" in `caption` at the circle's edge

#### Stop Pin (Screen 2)
- Green pin marker: `--color-stop-pin`
- White icon inside matching transport type
- Label below pin with stop name in `caption`

#### Walking Route (Screen 2)
- Dashed line, 3px stroke
- Light mode: `--color-route` (blue)
- Dark mode: `--color-route` (white)
- Dash pattern: 8px dash, 6px gap

## 6. Icons

### Transport Type Icons
Each transport type has a dedicated icon rendered in a 40x40px rounded container.

| Type | Icon | Container |
|------|------|-----------|
| Subway / Metro | Circled "M" | Dark gray background, white icon |
| Tram | Tram car silhouette | Dark gray background, white icon |
| Bus | Bus silhouette | Dark gray background, white icon |
| Rail / Train | Train silhouette | Dark gray background, white icon |

Icon source: Use an icon library (Lucide, Phosphor, or SF Symbols equivalents) for consistent line weights.

### UI Icons
| Icon | Size | Usage |
|------|------|-------|
| Chevron right (›) | 16px | Stop row navigation indicator |
| Clock (outline) | 20px | Departure time rows |
| Back arrow (←) | 24px | Navigation back from detail to list |
| Location crosshair | 24px | Loading/error state |

## 7. Motion & Transitions

| Interaction | Animation |
|-------------|-----------|
| Screen 1 → Screen 2 | Bottom sheet slides up with new content, map zooms to show route (300ms ease-out) |
| Screen 2 → Screen 1 | Reverse of above (250ms ease-in) |
| Map load | Fade in (200ms) |
| User location dot | Subtle pulse (2s infinite, scale 1.0 → 1.3 → 1.0 on halo) |
| Stop list load | Staggered fade-in of rows (50ms delay between each) |
| Pull-to-refresh (future) | Standard iOS rubber-band pull |

All animations respect `prefers-reduced-motion: reduce` by disabling or simplifying.

## 8. Dark Mode Implementation

- Triggered by `prefers-color-scheme: dark` media query.
- CSS custom properties switch values — no separate stylesheet.
- Map style switches from `light-v11` to `dark-v11`.
- All surfaces, text, and icons use the token system above — no hardcoded colors in components.
- Images/icons that don't adapt: provide both light and dark variants or use SVGs with `currentColor`.

## 9. Accessibility

- All interactive elements have minimum 44x44px touch targets.
- Color contrast ratios meet WCAG 2.1 AA (4.5:1 for text, 3:1 for large text).
- Transport type is conveyed via text label, not icon alone.
- Departure times use semantic `<time>` elements.
- Map is decorative — screen readers get a text alternative summarizing the content ("Walking route to Subway Line 1, approximately 200 meters").
- Focus management: when navigating to detail view, focus moves to the departure header.

## 10. Responsive Behavior

This is a **mobile-only** app. No tablet or desktop breakpoints in v1.

- Viewport width: assumed 320px – 430px (iPhone SE through iPhone Pro Max).
- Map and bottom sheet scale proportionally to viewport height.
- If accessed on a wider screen, content is centered with a max-width of 430px and a device-frame background (optional, cosmetic).

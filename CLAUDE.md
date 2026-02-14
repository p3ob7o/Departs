# Departs - Project Instructions

## Commands

```bash
npm run dev          # Start dev server (Turbopack)
npm run build        # Production build
npm run test:run     # Run unit tests once (vitest)
npm run test         # Run unit tests in watch mode
npm run test:coverage # Run tests with coverage report
npm run test:e2e     # Run Playwright e2e tests
npm run lint         # ESLint
```

## Environment Variables

Required in `.env.local` (and on Vercel):

```
NEXT_PUBLIC_MAPBOX_TOKEN=pk.*    # Client-side map rendering
MAPBOX_SECRET_TOKEN=sk.*         # Server-side directions API
HERE_API_KEY=*                   # Server-side transit data
```

## Architecture

- **Single-page app** with two screens managed by `selectedStop` state in `page.tsx`
- **API proxy pattern**: client fetches `/api/*` routes, server proxies to HERE/Mapbox with keys
- **No global state store** — hooks (`useGeolocation`, `useNearbyStops`, `useDepartures`) manage async state
- **Path alias**: `@/*` maps to project root

## Key Conventions

- All components in `app/components/`, hooks in `app/hooks/`, API routes in `app/api/`
- Design tokens as CSS custom properties in `globals.css` (light/dark via `prefers-color-scheme`)
- No Geist fonts — uses iOS system font stack (`-apple-system, BlinkMacSystemFont, ...`)
- Map dark mode detected via `matchMedia` inside the Map component (not passed as prop)
- `mapbox-gl/dist/mapbox-gl.css` must be imported in Map.tsx for markers to render

## Testing

- **Unit tests**: Vitest + React Testing Library + MSW for API mocking
- API route tests run in `node` environment; component tests in `jsdom`
- `react-map-gl/mapbox` is aliased to a mock in `vitest.config.ts` (not via `vi.mock`)
- `matchMedia` is mocked in `app/__tests__/setup.ts`
- MSW handlers in `app/__tests__/mocks/handlers.ts` — the `/api/directions` handler returns the already-unwrapped format (flat `{geometry, duration, distance}`, not `{routes: [...]}`)
- Test fixtures in `app/__tests__/fixtures/`

## External APIs

- **HERE Transit v8**: `/v8/stations` (nearby stops), `/v8/boards` (departures). Stop IDs must be URL-encoded.
- **Mapbox Directions**: Walking profile. API route unwraps `routes[0]` before returning to client.
- **Mapbox GL JS**: `light-v11` / `dark-v11` styles via `react-map-gl`

## Browser Automation

- Multiple Chromium browsers are installed. Only **Google Chrome** (profile **"Claude"**) has the Claude extension
- If `tabs_context_mcp` returns a connection error, call `switch_browser` to connect to Chrome

## Deployment

- Vercel (auto-deploys from `main`)
- Production URL: https://departs.vercel.app

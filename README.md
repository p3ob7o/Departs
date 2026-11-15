# Departs

Departs finds nearby public transport stops and shows upcoming departures with a walking route to the stop. It has a mobile-first Next.js web app and a native SwiftUI iOS app, both using the same API hosted on Vercel.

The current search radius is 400 metres. Transit information comes from HERE; walking directions come from Mapbox. The web map uses Mapbox GL and the iOS map uses MapKit. There are no accounts or application database.

- [Project review, branch inventory, proposed fixes, and five product improvements](docs/reviews/2026-11-15-project-audit.md)
- [Development commands and conventions](AGENTS.md)
- [Original product requirements](docs/PRD.md)

Run `npm install` and `npm run dev` for web development. Configure `NEXT_PUBLIC_MAPBOX_TOKEN`, `MAPBOX_SECRET_TOKEN`, and `HERE_API_KEY` in `.env.local` for live provider calls. Unit tests and browser tests use fixtures; browser tests also require `npx playwright install chromium webkit`.

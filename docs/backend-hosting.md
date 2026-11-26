# Departs API hosting

Installed releases through 1.3 (build 14) call `departs.vercel.app`. New releases target `api.departs.now`. Both serve the same root and three GET handlers. Next.js supplies the Vercel adapters. Spacefast Functions supply runtime bindings to the shared code in `app/lib`. The native release and backend releases are independent.

## Ship a backend change

Run tests, lint and both builds. Pull requests get Vercel previews and a **Spacefast Builds** preview check. Verify a real departures batch on the preview before merging.

Merging to `main` automatically deploys to Vercel and Spacefast. In **departs-api → Builds**, find the successful build for the merge commit and confirm its version is ready and live. On `api.departs.now`, check the root notice, nearby stops, a fresh departures batch, filtered per-line departures and a walking route. Both departures forms must return `Cache-Control: no-store`. Check the Vercel deployment for the same commit on `departs.vercel.app`.

### Spacefast CLI fallback

If the GitHub build fails or must be bypassed, publish the approved merged revision from a clean checkout using an authorized Spacefast identity.

```sh
set -eu
git fetch origin main
git switch --detach origin/main
test -z "$(git status --porcelain)"
npm ci
npm run test:run
npm run lint
npm run build
npm run build:spacefast
stage=$(mktemp -d)
mkdir "$stage/functions"
cp .spacefast/worker/functions/index.js "$stage/functions/"
mkdir -p "$stage/functions/api/stops"
cp .spacefast/worker/functions/api/departures.js .spacefast/worker/functions/api/directions.js "$stage/functions/api/"
cp .spacefast/worker/functions/api/stops/nearby.js "$stage/functions/api/stops/"
space=spc_d4d85f4115a84205879c2529834957e2
publish() {
  npx -y spacefast@0.10.0 publish "$stage" --prebuilt --space "$space" --target production --git-commit "$(git rev-parse HEAD)" --api-url https://api.spacefast.com "$@"
}
find "$stage" -type f
publish --dry-run
# After verifying the manifest contains only the packed Functions runtime:
publish --wait
```

Protect CLI output as a credential. Verify the receipt’s Space, live version and commit, then repeat the production checks above. If confirmation is required, stop for the owner.

## Connect GitHub

In the [Spacefast dashboard](https://my.spacefast.com/), select **Departs → departs-api → Builds → Connect GitHub** and choose **p3ob7o/Departs**. If the repository is missing, use **Add repositories** to authorize it on GitHub. Enter the build settings **before confirming**. Connecting the repository immediately queued a live build, even with empty settings.

The connection uses `main` for production and enables branch previews. Its saved settings are below, with both presets unset. The build root is `spacefast/` because at the repository root Spacefast detects Next.js and requires its adapter report, even with the `static` override. The build command invokes the parent package’s bundler and stages its four Function entries in `dist/functions/`.

```json
{
  "rootDirectory": "spacefast",
  "installDirectory": ".",
  "installCommand": "npm ci",
  "buildCommand": "npm --prefix .. run build:spacefast && mkdir -p dist && cp -R ../.spacefast/worker/functions dist/",
  "outputDirectory": "dist"
}
```

On 26 November 2026, GitHub preview V18 matched live V17’s manifest, static file lists and routing summary. All five Vienna requests returned 200 on the preview, including a batch 0.299 seconds old and a walking route.

## Rollback and secrets

On Spacefast, list retained ready versions with `npx -y spacefast@0.10.0 versions ls --space departs-api --api-url https://api.spacefast.com`. Roll back to the chosen version with `npx -y spacefast@0.10.0 rollback vNUMBER --space departs-api --api-url https://api.spacefast.com`. Coordinate any required confirmation with the owner. The live pointer moves, including the version's sealed bindings. On Vercel, select the known-good production deployment and use **Instant Rollback**. Reconcile the source before the next release. Verify both target host and API after either action. [Spacefast versions](https://spacefast.com/docs/versions/) · [Vercel rollback](https://vercel.com/docs/instant-rollback)

`HERE_API_KEY` and `MAPBOX_SECRET_TOKEN` live in Vercel's server environment and in Spacefast's runtime secrets. Coordinate Spacefast writes as releases because each can create a new live version. Access and edge logs can contain client addresses, location queries and long-lived signed bundle URLs. Runtime errors can expose upstream credentials if they include provider URLs. Keep raw logs and receipts owner-readable outside Git. Share only aggregate or redacted observations.

The three Spacefast API adapters require the runtime context argument. Calling one without that argument throws before the handler can return JSON.

An empty Spacefast binding sends an empty key to the provider. After a Space change, check the variable listing for both expected names and verify a live transit and walking response.

## DNS and HTTPS

The backend Space has a serving attachment for `api.departs.now`. The separate lander Space owns the apex attachment. With external DNS, install the API attachment’s required records at the authoritative provider. With Spacefast authoritative DNS, inspect the zone publication and ownership-proof state and the serving-record status for each attached hostname. Spacefast describes an empty manual-record list for names served from its DNS zone. Independently resolve both names, verify the certificate, and compare the API root and a transit request before distributing the app build. The managed hostname is `departs-api.space.fast`. [Custom domains](https://spacefast.com/docs/domains/) · [Domain API](https://api.spacefast.com/openapi.json)

## Check what a rider receives

Spacefast’s departures adapter sets `Cache-Control: no-store` on the shared handler’s response, including validation and provider errors. This covers batch, filtered per-line and legacy single-stop requests. Each accepted departures request reaches the Function. Vercel keeps its 30-second public TTL on successful departures. Nearby stops and walking routes have public TTLs of 86,400 and 3,600 seconds respectively on both hosts. The Spacefast policy ships with the adapter and requires no dashboard traffic rule.

Verify a release using both batch and per-line requests on the release hostname. Repeat the identical URLs after an idle period and check the delivered `no-store` header and the CDN status. Treat a departures HIT or STALE as a regression. For batches, compare the body’s `fetchedAt` to the rider clock. Per-line answers have no source timestamp. Repeat a nearby and a walking request to verify their shared-cache hits. Record URLSession’s `isProxyConnection` when comparing hosts. On the test Mac, direct and system-proxied requests to the same managed-host version both missed for departures, but only the direct route delivered the literal `no-store` header. The proxied route delivered `no-cache, must-revalidate, max-age=0`. Record both the delivered policy and the observed cache state. [Hosted verification](reviews/2026-11-24-spacefast-trial.md#departures-cache-policy)

## Retire the legacy host

Retain Vercel while any supported build starts there. The Vercel hostname cannot be moved by changing DNS. Retire it once supported users have updated or the owner ends those builds' support. A verified Vercel forwarder could retire the old implementation earlier while retaining the hostname. The trial forwarder preview required sign-in and did not establish equivalent query handling, caching or latency. See the [trial measurements](reviews/2026-11-24-spacefast-trial.md).

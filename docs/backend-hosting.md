# Departs API hosting

Installed releases through 1.3 (build 14) call `departs.vercel.app`. New releases target `api.departs.now`. Both serve the same root and three GET handlers. Next.js supplies the Vercel adapters. Spacefast Functions supply runtime bindings to the shared code in `app/lib`. The native release and backend releases are independent.

## Ship a backend change

Run the tests, lint and both builds. Check the deployed preview with a real batch before merging. Vercel deploys branch previews automatically and deploys merged `main` to its production host. Until the GitHub connection is enabled on Spacefast, separately publish each approved merged revision. Start in a clean checkout of the repository, with the authorized Spacefast deployment identity available.

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

Protect CLI output as a credential. Verify the receipt names the intended Space, the version is ready and live, and its commit matches the release. Check HTTPS, root text, validation and a successful transit batch on the custom domain. Inspect the response version and board timestamp. Also check the equivalent Vercel release. If an operation requires confirmation, stop for the owner.

## Connect GitHub

In the backend Space, open **Builds → Connect GitHub → Connect repository**. Select the installation and the Departs repository. If it is missing, use **Add repositories** and have the repository owner grant the Spacefast GitHub App access to Departs. Set the production branch to `main`. Under **Build settings**, use the repository root, `npm ci`, `npm run build:spacefast` and output directory `.spacefast/worker`. Enable production auto-deploy and preview auto-deploy. Verify that a branch push produces a Functions preview and that the first approved merge publishes the matching SHA to live. These connected-build settings require their own end-to-end verification. [Spacefast Git deployments](https://spacefast.com/docs/git/)

## Rollback and secrets

On Spacefast, list retained ready versions with `sf versions ls --space departs-api-trial`, then use `sf rollback vNUMBER --space departs-api-trial` for the chosen known-good version. Coordinate any required confirmation with the owner. The live pointer moves, including the version's sealed bindings. On Vercel, select the known-good production deployment and use **Instant Rollback**. Reconcile the source before the next release. Verify both target host and API after either action. [Spacefast versions](https://spacefast.com/docs/versions/) · [Vercel rollback](https://vercel.com/docs/instant-rollback)

`HERE_API_KEY` and `MAPBOX_SECRET_TOKEN` live in Vercel's server environment and in Spacefast's runtime secrets. Coordinate Spacefast writes as releases because each can create a new live version. Access and edge logs can contain client addresses, location queries and long-lived signed bundle URLs. Runtime errors can expose upstream credentials if they include provider URLs. Keep raw logs and receipts owner-readable outside Git. Share only aggregate or redacted observations.

## Retire the legacy host

Retain Vercel while any supported build starts there. The Vercel hostname cannot be moved by changing DNS. Retire it once supported users have updated or the owner ends those builds' support. A verified Vercel forwarder could retire the old implementation earlier while retaining the hostname. The trial forwarder preview required sign-in and did not establish equivalent query handling, caching or latency. See the [trial measurements](reviews/2026-11-24-spacefast-trial.md).

# Departs API hosting

Spacefast serves Departs at `api.departs.now` (managed hostname `departs-api.space.fast`). The `departs-api` Space runs four Functions from this repository. Builds from iOS 1.3 (15) use the custom domain. The owner retired the Vercel host used through build 14 without forwarding.

## Ship a backend change

Run `npm ci`, `npm run test:run`, `npm run test:coverage`, `npm run lint` and `npm run build:spacefast`. Check the **Spacefast Builds** preview on the PR and exercise a real departures batch before merging. On an approved merge to `main`, open **departs-api → Builds** and find the **push** build for the full merge SHA. Verify it succeeded and its produced or reused version is live. A reused version can carry an earlier source SHA.

The [project config](../sf.jsonc) specifies repository root `.`, install directory `.`, install command `npm ci`, build command `npm run build:spacefast` and output `.spacefast/worker`. Leave the presets unset. With those settings saved on the GitHub connection, the push filter covers the entire repository, including docs-only and iOS-only merges. A PR preview alone does not verify the push filter. [Spacefast Git builds](https://spacefast.com/docs/frameworks/)

### Cut over to repository-root builds

- [ ] Merge the removal PR after approval. Check the automatic production build for that exact merge SHA while the connection still uses its previous settings. Confirm the live version.
- [ ] In the GitHub connection for **Departs → departs-api**, save the five values from `sf.jsonc` above. Keep production on `main` and branch previews enabled. When connecting a new repository, enter the settings before confirming. Connecting queues a live build immediately.
- [ ] Start a production build pinned to the merge SHA using the command below. Verify its settings snapshot, source SHA, successful status and live version.
- [ ] Run the five rider checks below on `api.departs.now`.
- [ ] After the next approved docs-only push to `main`, verify that the automatic push build ran for that SHA and produced or reused a ready version. This establishes that the previous directory filter is gone.

### Manual build fallback

If the automatic release fails or must be bypassed, set `release_sha` to the full approved merge SHA. Keep the receipt owner-readable.

```sh
: "${release_sha:?Set release_sha to the full approved merge SHA}"
umask 077
receipt=$(mktemp)
npx -y spacefast@0.10.0 git build --space departs-api \
  --ref main --branch main --commit "$release_sha" --target production --wait \
  --api-url https://api.spacefast.com >"$receipt" 2>&1
```

If Spacefast returns `422 source_commit_not_saved`, wait for its GitHub mirror and retry with the same SHA while that release is current. An unpinned retry can release the previous commit. Confirm the source SHA on the build record, check its version against the live channel and run the rider checks.

## Check what a rider receives

On the release hostname, bypass system proxies and check the root notice, nearby stops, a batch of those stops, a filtered line from that batch and a walk to a returned stop. Expect 200s, plain text at the root, JSON at all three API paths and a batch timestamp within a few seconds of receipt. Per-line responses have no source timestamp.

The departures Function sets `Cache-Control: no-store` on batch, single-stop, filtered and error responses. Repeat an identical batch and line query. A shared-cache HIT or STALE is a regression. Nearby stops and walks have public TTLs of 86,400 and 3,600 seconds respectively and can produce shared-cache hits. A system proxy can rewrite the delivered cache header. [Hosted measurements](reviews/2026-11-24-spacefast-trial.md#departures-cache-policy)

## Rollback, bindings and logs

List ready versions with `npx -y spacefast@0.10.0 versions ls --space departs-api --api-url https://api.spacefast.com`. With owner approval, restore the chosen version with `npx -y spacefast@0.10.0 rollback vNUMBER --space departs-api --api-url https://api.spacefast.com`. Verify the live version and repeat the rider checks. Reconcile the source before the next release. [Spacefast versions](https://spacefast.com/docs/versions/)

Spacefast seals the runtime bindings `HERE_API_KEY` and `MAPBOX_SECRET_TOKEN` with each version. A variable write can change the live version. After any Space change, check that both names are present and verify a transit request and a walk. An empty binding sends an empty key to the provider. Calling an API entry without its runtime context throws before it can return JSON.

Access and edge logs may include client addresses, location queries and long-lived signed bundle URLs. Upstream URLs can carry provider credentials. Keep raw logs and receipts owner-readable outside Git. Share only redacted observations.

## DNS and HTTPS

The backend Space has the serving attachment for `api.departs.now`. The separate lander Space owns the apex. Check the serving record and certificate for the API hostname when changing domains and verify the root and a transit request before distributing an app build. [Custom domains](https://spacefast.com/docs/domains/)

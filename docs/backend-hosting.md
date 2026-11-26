# Departs API hosting

Spacefast serves Departs at `api.departs.now` (managed hostname `departs-api.space.fast`). The `departs-api` Space runs four Functions from this repository. Builds from iOS 1.3 (15) use the custom domain. The owner retired the Vercel host used through build 14 without forwarding.

## Ship a backend change

Run `npm ci`, `npm run test:run`, `npm run test:coverage`, `npm run lint` and `npm run build:spacefast`. Open the PR’s **Spacefast Builds** check, follow its details to the build for the PR head, and open the produced or reused version’s preview address. If it requires a session, open the version preview in Spacefast and use that session for the requests. Run the [five rider checks](#check-what-a-rider-receives) on that preview before merging. On an approved merge to `main`, open **departs-api → Builds** and find the **push** build for the full merge SHA. Verify it succeeded and its produced or reused version is live. A reused version can carry an earlier source SHA.

The [project config](../sf.jsonc) specifies repository root `.`, install directory `.`, install command `npm ci`, build command `npm run build:spacefast` and output `.spacefast/worker`. Leave **Framework preset** (`frameworkPreset`, CLI `--framework-preset`) and **Platform preset** (`platformPreset`, CLI `--platform-preset`) unset. With those settings saved on the GitHub connection, the push filter covers the entire repository, including docs-only and iOS-only merges. A PR preview alone does not verify the push filter. [Spacefast Git builds](https://spacefast.com/docs/frameworks/)

### Cut over to repository-root builds

- [ ] Merge the removal PR after approval. Keep the old connection settings through the merge: before removal, Spacefast detects the repository-root `next` dependency as Next.js and the Functions build fails. Check the automatic production build for the exact merge SHA and record the last good live version.
- [ ] In the GitHub connection for **Departs → departs-api**, save the five values from `sf.jsonc` above. Keep production on `main` and branch previews enabled. Read **Builds** immediately after saving. Connecting a *new* repository queued a live build immediately in our trial. Whether editing an existing connection queues one is unverified.
- [ ] Run the [pinned production build command](#pinned-production-build) for the approved merge SHA. This build is required during cutover even when the preceding automatic build succeeded. Read the build record: compare its source commit to the full merge SHA and its settings snapshot to all five values above, especially output `.spacefast/worker`. A build can succeed with the wrong output directory. Verify that its produced or reused version is live.
- [ ] Run the [five rider checks](#check-what-a-rider-receives) directly on `https://api.departs.now`. If a check fails, follow [rollback](#rollback-bindings-and-logs) to restore the recorded good version and repeat the checks.
- [ ] After the next approved docs-only push to `main`, verify that the automatic push build ran for that SHA and produced or reused a ready version. This establishes that the previous directory filter is gone.

The removal PR’s automatic preview used the saved `spacefast/` root and its copy-to-`dist` command even with `sf.jsonc` present. Committing the recipe alone does not switch the GitHub connection. Set it explicitly in the checklist above.

### Pinned production build

Use this command during cutover and as a fallback for later automatic releases. Set `release_sha` to the full approved merge SHA. Keep the receipt owner-readable.

```sh
: "${release_sha:?Set release_sha to the full approved merge SHA}"
umask 077
receipt=$(mktemp)
npx -y spacefast@0.10.0 git build --space departs-api \
  --ref main --branch main --commit "$release_sha" --target production --wait \
  --api-url https://api.spacefast.com >"$receipt" 2>&1
```

On 26 November 2026 we observed HTTP 422 with `source_commit_not_saved`; the public error reference lists HTTP 400. If the mirror cannot supply the commit, wait and retry the same full SHA while the release remains current. If the error persists, hold the release. We have no verified second procedure for this cutover. Never retry unpinned: in the trial an unpinned build selected the previous commit. [Spacefast error reference](https://spacefast.com/docs/errors/source_commit_not_saved/)

### Restore the previous build settings

If the recipe makes a build fail, every later build using that broken recipe will fail and the last good version stays live. Restore these five GitHub connection values to resume automatic deploys for changes under `spacefast/`:

| Setting | Previous value |
| --- | --- |
| Root directory | `spacefast` |
| Install directory | `.` |
| Install command | `npm ci` |
| Build command | `npm --prefix .. run build:spacefast && mkdir -p dist && cp -R ../.spacefast/worker/functions dist/` |
| Output directory | `dist` |

This recipe built the removal PR. It restores the old push filter, which can skip changes confined to shared handlers or dependencies outside `spacefast/`. Use it only while repository-root triggering is unnecessary. Restoring settings repairs future builds. If a successful build already put the wrong output live, [restore the last good version](#rollback-bindings-and-logs) as well.

## Check what a rider receives

On the release hostname, bypass system proxies and check the root notice, nearby stops, a batch of those stops, a filtered line from that batch and a walk to a returned stop. Expect 200s, plain text at the root, JSON at all three API paths and a batch timestamp within a few seconds of receipt. Per-line responses have no source timestamp.

The departures Function sets `Cache-Control: no-store` on batch, single-stop, filtered and error responses. Repeat an identical batch and line query. A shared-cache HIT or STALE is a regression. Nearby stops and walks have public TTLs of 86,400 and 3,600 seconds respectively and can produce shared-cache hits. A system proxy can rewrite the delivered cache header. [Hosted measurements](reviews/2026-11-24-spacefast-trial.md#departures-cache-policy)

## Rollback, bindings and logs

List ready versions with `npx -y spacefast@0.10.0 versions ls --space departs-api --api-url https://api.spacefast.com`. With owner approval, restore the chosen version with `npx -y spacefast@0.10.0 rollback vNUMBER --space departs-api --api-url https://api.spacefast.com`. Verify the live version and repeat the rider checks. Reconcile the source before the next release. [Spacefast versions](https://spacefast.com/docs/versions/)

Spacefast seals the runtime bindings `HERE_API_KEY` and `MAPBOX_SECRET_TOKEN` with each version. A variable write can change the live version. After any Space change, check that both names are present and verify a transit request and a walk. An empty binding sends an empty key to the provider. Calling an API entry without its runtime context throws before it can return JSON.

Access and edge logs may include client addresses, location queries and long-lived signed bundle URLs. Upstream URLs can carry provider credentials. Keep raw logs and receipts owner-readable outside Git. Share only redacted observations.

## DNS and HTTPS

The backend Space has the serving attachment for `api.departs.now`. The separate lander Space owns the apex. Check the serving record and certificate for the API hostname when changing domains and verify the root and a transit request before distributing an app build. [Custom domains](https://spacefast.com/docs/domains/)

## Retire Vercel

Vercel documents automatic promotion of the most recent successful production build. We therefore expect a later failed build to leave the last good deployment serving. To stop automatic Vercel checks on future PRs, the owner opens the project's **Settings → Git → Connected Git Repository → Disconnect**. If GitHub requires that check to merge, remove it from the branch rules as well. We expect existing deployments to remain online after Git disconnection. The Git settings guide documents disconnection only. To take the old endpoint offline, pause the project (returns 503) or explicitly delete it. Deletion also removes deployments, domains, variables and project settings. [Vercel production promotion](https://vercel.com/docs/deployment-checks) · [Disconnect Git](https://vercel.com/docs/project-configuration/git-settings) · [Pause or delete a project](https://vercel.com/docs/projects/managing-projects)

# Departs API on Spacefast, phase 1

**The private trial serves the API, but failed exact contract parity.** A rejected batch departure request returned HTTP 500 on both hosted versions. The base commit and the packed worker executed locally both returned the required 502. Keep production on Vercel. Valid live transit data and public caching require a separate trial.

## Deployment

The [Spacefast Next.js recipe](https://spacefast.com/docs/recipes/next/) lists 16.4.x for static export only. The four [Functions](https://spacefast.com/docs/functions/) entries share the existing root, validations, HERE/Mapbox requests, normalization and response construction with the Next.js routes. Only the adapters supply runtime credentials. The production host compiled into the app stays on Vercel.

- Team Departs, Space `spc_d4d85f4115a84205879c2529834957e2`, stable address `https://departs-api-trial.space.fast/`.
- V1 `ver_0518580a3a5f457d9a8c399206b7a6b3`. V2 `ver_1c3e5154198c4a61a6adbe36a223ea72`.
- Only your team can view this Space after signing in. Change the audience in this Space's Access settings.

With Node 26.13.1 and Spacefast CLI 0.10.0, `npm run build:spacefast` bundles the four entry modules under `.spacefast/worker/functions/`. The CLI independently classified this directory as a Functions file router. Each publish used a clean staging directory. The enumerated dry-run manifest for V1 contained only `__spacefast/functions/bundles/e1b3c840ad72eea262e2a720dcd9f0ceba55d4b9adc278148078324ceef57599/bundle.json` (8,760 bytes). V2 added only `trial-version.txt` (30 bytes, one static verification line). Neither artifact included repository history, deployment state, dependencies, credentials, iOS files or documentation.

## Checks

| Check | Result | Evidence |
|---|---|---|
| a. Publish | Passed | Team ID matched the creation receipt. Both publishes reported ready and activated. Independent version and live-channel reads confirmed V1 first and then V2. Opened the protected root with a bounded version session. |
| b. Access | Passed | An unauthenticated GET to the bare live address returned 403. A session on a fixed version returned 200. |
| c. Root | Passed | Production and the trial returned HTTP 200, `text/plain; charset=utf-8` and identical bytes, including the trailing newline after “Departs is now an iOS app.” |
| d. Validation | Passed | Six cases returned identical 400 statuses and JSON on the trial and production. Requests omitted required parameters on each route, exceeded the latitude range, combined batch and single-stop filters, or supplied malformed walking coordinates. Each exits before fetch. Seven production GETs total, including the root. |
| e. Provider rejection | **Failed** | Local `origin/main` at `90bc6e0` ran with the same two dummy credentials. Stops, single departures and walks returned matching 500 statuses and error bodies. Batch departures returned matching JSON but **502 locally and 500 on Spacefast**. Reproduced on V2 with a second batch and a fresh query. HERE and Mapbox independently returned 401 to direct requests with dummy credentials. Hosted departure logs recorded upstream HTTP 401. Walks and stops suppress the upstream status in their handlers. |
| f. Secrets | Passed for inspected artifacts, responses and available logs | Both Space-scoped variables listed `secret: true` with an empty value. Their values were supplied through stdin. |
| g. Headers | Passed for private responses | See header table. The private host changes the root's public policy. Live provider success responses remain unverified. |
| h. Rollback | **Not possible with this authorization** | V2 served the distinct static file and reached live. Spacefast stopped rollback to V1 with `confirmation_required`, request ID `35dc4491a5a2a7ea0ece096a66dabd46`. The service requires a person to approve this exact action. V2 stayed live. No rollback or subsequent promotion occurred. |

| Path | Success policy in shared code | Observed on private trial |
|---|---|---|
| `/` | `public, max-age=3600` | 200, `private, no-store` |
| `/api/stops/nearby` | `public, max-age=86400` | 400 and 500, `private, no-store` |
| `/api/departures` | `public, max-age=30` | 400 and 500, `private, no-store` |
| `/api/directions` | `public, max-age=3600` | 400 and 500, `private, no-store` |

The transit error paths set no Cache-Control header in the shared code. Local MSW successes returned all three expected public policies. The batch error test also exercises the worker entry with a mocked HERE 401. Running the exact packed JavaScript under Node with the same upstream rejection yielded 502 for a batch and 500 for a single stop. That narrows the discrepancy to the hosted path. Its precise cause remains unknown.

## Operational evidence and limitations

- The packed bundle's SHA-256 matched the upload manifest in both dry runs. The published static verification file downloaded through the artifact API matched its input byte for byte. The file index excludes runtime-internal files, and the download API refused that bundle with `validation_error` (HTTP 422, request ID `b027c5c5386a5249b31910b181f934c5`). The bundle scan used the matching local packed bytes. A server-side readback of the internal worker was unavailable.
- Published versions list no build job or build log because compilation happened locally. Checked local build output, the visible runtime log pages, and response headers and bodies for both supplied marker values. A clean scan covers these observations only. Access to infrastructure-internal logs was outside the trial.
- The first receipt reported `hostname_attach_pending`; its version was already ready and live. It supplied no Access URL. A bounded version session provided access without a sharing Link. The default Python HTTP client received edge 403/1010; curl redeemed the same preview session and served the root. Reused the original seven production responses for the successful curl comparison. The CLI rejected global help combined with the API endpoint flag (`validation_error`, no request ID returned); command-specific help accepted it.
- Local checks passed: `npm ci`, `npm run build:spacefast`, `npm run test:run` (98 tests), `npm run test:coverage` (90.72% branches), `npm run lint` and `npm run build`. The Next build still listed all four dynamic paths. Existing tests were preserved. The iOS app, production backend, DNS and public access settings were outside the change.

## Timing and usage

**i. Passed.** Each warm sample used ten sequential curl requests and a separate burst of five concurrent requests. Measurements include the connection from the test Mac to the fixed version hostname. The first four rows measured V1. After 608 seconds with no trial requests, a fresh V2 preview session exchanged its proof for a cookie (302). The first four application GETs then ran concurrently, one per path. The provider-reaching warm samples ran on V2 afterward. Both versions used identical worker bytes.

| Request | HTTP | Sequential median / max, ms | Concurrent median / max, ms | After idle, ms |
|---|---:|---:|---:|---:|
| Root | 200 | 328 / 672 | 336 / 571 | 310 |
| Stops, missing coordinates | 400 | 274 / 410 | 272 / 377 | 490 |
| Departures, missing stop | 400 | 275 / 404 | 281 / 426 | 441 |
| Directions, missing endpoints | 400 | 273 / 388 | 293 / 560 | 736 |
| Stops, dummy HERE key | 500 | 575 / 1,008 | 510 / 566 | — |
| Batch departures, dummy HERE key | 500 | 405 / 533 | 306 / 590 | — |
| Walk, dummy Mapbox token | 500 | 380 / 506 | 349 / 441 | — |

**j. Passed for the team meter.** At 08:07:22 UTC the free team's meter reported one Space, two deployments, 128 worker requests and zero metered cost. The per-Space endpoint returned null, so an independent settled per-Space total was unavailable. The 14 available runtime log entries ended without a further page. The supplied markers appeared in none of those entries, the scanned payloads, or the sampled responses.

## Decision before phase 2

The 502 discrepancy can be investigated further with dummy credentials. Demonstrate parity on the hosted path before routing production traffic. A rollback rehearsal still needs the service's action-specific human approval. To test the success paths, the owner would need to provision scoped HERE and Mapbox runtime secrets and approve a public trial endpoint for cache and phone checks. Test successful live boards and walks, timestamps and query-specific cache expiry, and latency from an iPhone under its 12-second timeout. This trial did not establish production caching, live provider success-path latency, real-device behavior or a production migration.

# Departs API on Spacefast: private compatibility trial

**The private trial serves the API, but failed exact contract parity.** A rejected batch departure request returned HTTP 500 on both hosted versions. The base commit and the packed worker executed locally both returned the required 502. Keep production on Vercel. The follow-up below verifies successful fixture decoding with the app’s networking code. Live transit data and public caching still require a separate trial.

## Deployment

The [Spacefast Next.js recipe](https://spacefast.com/docs/recipes/next/) lists 16.4.x for static export only. The four [Functions](https://spacefast.com/docs/functions/) entries share the existing root, validations, HERE/Mapbox requests, normalization and response construction with the Next.js routes. Only the adapters supply runtime credentials. The production host compiled into the app stays on Vercel.

- Team Departs, private Space `departs-api-trial`. V1 and V2 contain the trial API. V2 is live.
- Only your team can view this Space after signing in. Change the audience in this Space's Access settings.

With Node 26.13.1 and Spacefast CLI 0.10.0, `npm run build:spacefast` bundles the four entry modules under `.spacefast/worker/functions/`. The CLI independently classified this directory as a Functions file router. Each publish used a clean staging directory. The enumerated dry-run manifest for V1 contained only the internal Functions bundle (8,760 bytes). V2 added only `trial-version.txt` (30 bytes, one static verification line). Neither artifact included repository history, deployment state, dependencies, credentials, iOS files or documentation.

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
| h. Rollback | Passed in the owner-approved rehearsal | After action-specific approval, the reviewer rolled back from V2 to V1 in 3 seconds at 08:46 UTC and promoted V2 again without another approval. The live pointer and runtime agreed. |

| Path | Success policy in shared code | Observed on private trial |
|---|---|---|
| `/` | `public, max-age=3600` | 200, `private, no-store` |
| `/api/stops/nearby` | `public, max-age=86400` | 400 and 500, `private, no-store` |
| `/api/departures` | `public, max-age=30` | 400 and 500, `private, no-store` |
| `/api/directions` | `public, max-age=3600` | 400 and 500, `private, no-store` |

The transit error paths set no Cache-Control header in the shared code. Local MSW successes returned all three expected public policies. The batch error test also exercises the worker entry with a mocked HERE 401. Running the exact packed JavaScript under Node with the same upstream rejection yielded 502 for a batch and 500 for a single stop. That narrows the discrepancy to the hosted path. Its precise cause remains unknown.

## Operational evidence and limitations

- The packed bundle's SHA-256 matched the upload manifest in both dry runs. The published static verification file downloaded through the artifact API matched its input byte for byte. The file index excludes runtime-internal files, and the download API refused that bundle with `validation_error` (HTTP 422). The bundle scan used the matching local packed bytes. A server-side readback of the internal worker was unavailable.
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

**j. Passed for the team meter.** At 08:07:22 UTC the free team's meter reported one Space, two deployments, 128 worker requests and zero metered cost. The per-Space endpoint returned null, so an independent settled per-Space total was unavailable. The initial read, five seconds after the final request, contained 14 runtime entries. The reviewer’s later read contained all 20. The supplied markers appeared in none of those entries, the scanned payloads, or the sampled responses.

## Round 2: what changed between the worker and the client

**The hosted path changed every tested 502 to 500.** A synthetic response reproduced the change without any transit code. Both response constructors, an empty body, a rejected HERE call, and a walking route with no result gave the same outcome. The synthetic body and the worker’s status header survived. V2’s tagged live batch appeared as 500 in both origin and edge logs. Together these findings locate the live discrepancy at or before the logged origin response. They do not identify the internal component or establish how every possible HTTP status is handled.

Spacefast CLI 0.10.0 published two preview-only versions. The full inventory is **V1** (original API), **V2** (API plus static verification file, live), **V3** (API plus probes, preview) and **V4** (API with fixture provider responses, preview). All four were ready. The V3 and V4 hostnames ran their own functions and returned their respective version headers. Live stayed on V2. All requests in this round used the private Space or the local reference; production received none. The reviewer independently matched the V2 runtime’s bundle digest to the local bytes and confirmed its compatibility date of 2026-07-01.

### Status observations

“Origin” and “edge” are statuses observed in the corresponding log streams. The API exposed those rows for tagged live requests only. A dash means no attributable row. Both V3 constructor variants gave the listed result. A 204 requires a null body, so both switches used the same legal empty response for that row.

| Version and request | Worker status | Origin | Edge | Received | What reached the client |
|---|---:|---:|---:|---:|---|
| V3 synthetic, each of 200, 201, 204, 400, 404, 418, 500, 501, 503, 520 | As listed | — | — | Same | Original body and sent-status header; 204 had no body |
| V3 synthetic 502, both constructors, empty body, and after HERE 401 | 502 | — | — | 500 | Original body and sent-status header |
| V3 synthetic 429 | 429 | — | — | 429 | Replacement HTML; worker header absent |
| V3 synthetic 504 | 504 | — | — | 504 | Replacement HTML; worker header absent |
| V3 synthetic 599 | 599 | — | — | 429 | Replacement HTML; worker header absent |
| V2 live root / invalid input / rejected single stop | 200 / 400 / 500 | 200 / 400 / 500 | 200 / 400 / 500 | 200 / 400 / 500 | Normal application responses |
| V2 live rejected batch | 502 in the shared code and packed-worker control | 500 | 500 | 500 | Same JSON error as the local 502 |

The reviewer’s live requests and this round’s separate `sf fetch` requests agreed. The previews could not be routed through the live hostname while V2 served it. Runtime logs corroborated probe execution, but an application log is not an origin access-log status.

### Runtime secrets

The worker reported both dummy bindings present. The HERE value was 21 bytes and the Mapbox value 23 bytes. Each SHA-256 matched the independently hashed marker. The CLI documents per-branch **build** overrides. Spacefast documents that writing a Space variable queues a version that replaces live. Rotation and restoration therefore remained untested under the preview-only restriction. [Environment variables](https://spacefast.com/docs/environment-variables/)

### Fixture success, errors and body integrity

The local reference was the packed V4 worker under Node. The comparison used SHA-256 over decoded body bytes. For a successful batch, the expected bytes were reconstructed with the hosted `fetchedAt` in place of the local timestamp. No other field was normalized. The table reports curl defaults and, after the slash, curl with the captured app headers. Timing differences are `fetchedAt` minus the response’s whole-second HTTP `Date`.

| Fixture GET | HTTP | Decoded body vs local | Result or timestamp difference (seconds) |
|---|---|---|---|
| Nearby radius 400, 800, 1600 m | 200 / 200 | Identical at all three radii | Three stops each |
| Batch, two IDs | 200 / 200 | Matched after timestamp substitution | 2 boards; +0.553 / +0.242 |
| Batch, 17 IDs | 200 / 200 | Matched after timestamp substitution | 17 boards; +0.133 / +0.749 |
| Batch, 50 IDs | 429 / 429 | HTML replaced expected JSON | The real Swift client separately decoded all 50 boards |
| Batch, one known and one missing ID | 200 / 200 | Matched after timestamp substitution | 1 board, 1 missing; +0.143 / +0.382 |
| Per line: space, umlaut, comma, slash and parentheses | 200 / 200 | Identical for each query | One matching departure each |
| Direction with raw `+` / encoded `%2B` | 200 / 200 on each | Each matched its own local reference | Raw plus matched the space-direction row. Encoded plus matched the distinct literal-plus row. |
| Legacy grouped board; walk | 200 / 200 | Identical | 7 groups; 120.5 m walk with 4 geometry points |
| HERE 401, 429, two 500 responses, invalid JSON; Mapbox no route | 500 / 500 | Identical error bodies | Packed V4 returned 502 for every case. The hosted status changed. |

All successful transit responses above used `application/json`, omitted Content-Length, and carried `Vary: Cookie` and `Cache-Control: private, no-store`. Default curl received uncompressed successes; the app-header requests received gzip. The five hosted 500 cases used JSON without content encoding or Content-Length and had the same private cache and Vary headers. Both 50-ID curl responses were uncompressed HTML, 1,168 bytes, with no Vary or Cache-Control. The HTTP client, request construction and timing differed in the successful Swift run; this experiment did not isolate the cause of that difference.

### Methods, paths, client and framing

| Request | Packed worker | Hosted result |
|---|---:|---|
| HEAD / POST / OPTIONS on departures without a stop | 400 / 405 / 405 | 400 with empty body / 405 / 405. Both 405s advertised GET and HEAD. |
| Unknown path; trailing slash on departures | 404; 400 | Same statuses. The trailing slash still reached validation. |
| Doubled slash inside API or echo path | 400 on departures; 200 on echo | Both returned 404 |
| 2 KiB query on echo / departures | 200 / 400 | 200 / 400. Echo received the full parameter value. |
| 16 KiB query on echo / departures | 200 / 400 | Both returned 414 without a version header |
| Repeated stopIds | 400 | 400. Echo received both pairs in order. |
| Echo with POST / OPTIONS / HEAD | 200 each | POST and OPTIONS reported the incoming method. HEAD returned no body. |

The macOS CFNetwork harness used the app’s own APIService and models, exchanged its preview session in the same URLSession, and decoded stops at all three radii, batches of 2, 17 and 50, missing boards, grouped and individual services, and the walk. On a literal-plus request the app received the space-direction row. The two fixture rows made this visible even though both returned one departure. This reproduces the pre-existing client encoding behavior. Every non-200 status maps to the same client error.

Curl, a request without User-Agent and a request carrying the harness’s four captured headers reached echo. Python’s default client received 403. Echo saw the expected User-Agent (or its absence) and `Accept-Encoding: gzip, br` on all three admitted requests. Only the names of other headers were recorded by echo. For deterministic bodies of 128, 16,384 and 65,536 bytes, default curl received uncompressed bytes and gzip requests received gzip. All six decoded hashes matched the local reference and the worker’s digest header. The responses varied on Cookie and omitted Content-Length.

### Timing, concurrency and usage

| Test | Observation |
|---|---|
| Fixture provider scheduled to reply after 11 / 13 s | The handler aborted each attempt after 10 s and retried. Hosted curl received 500 with the expected error JSON at 20.26 / 20.40 s. The app’s 12 s timeout surfaced as URL error −1001 at about 13 s in both runs. |
| Worker sleep of 29 / 31 s | 200 JSON at 29.43 s / 500 plain text at 30.35 s. These bound the observed cutoff for this trial. |
| Unhandled throw | 500 problem JSON at 0.54 s |
| 2 / 5 simultaneous one-second sleeps | All succeeded, in 1.41–1.65 s / 1.29–1.68 s |
| 10 simultaneous one-second sleeps | Six 200s and four 429s, 0.26–1.76 s overall. No Retry-After header. Testing stopped at this burst. |

The team meter rose from 132 to 295 worker requests and from two to four deployments. Both readings showed zero metered cost and an OK budget status. Per-Space settled usage remained unavailable. The final usage reading was measured through 10:20:45 UTC. Effective capacity under other workloads remains unmeasured.

**Friction and remaining evidence.** An initial dry run treated the default-export echo module as a static asset. Named method exports corrected the manifest before upload. The first log query rejected the supplied timestamp format. UTC timestamps ending in Z worked. The private version hostnames had no attributable access or edge rows in the live-host log streams. Scoped real HERE and Mapbox credentials are still needed to measure genuine provider success, data quality, and latency. A public endpoint is needed to prove anonymous access, cache hits, query isolation, TTL expiry and board freshness. Cellular performance needs an iPhone. The variable lifecycle and the precise component that changes 502 remain open; neither question requires real provider credentials.

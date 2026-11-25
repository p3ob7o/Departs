# Departs API on Spacefast

**The paid-plan Space served a ten-minute rider session without a refusal.** The app’s 24 network requests all returned 200. Anonymous curl requests could reuse public cached responses, including a 50-ID batch. The app’s refreshes saw different caching behavior. The hosted no-route status still differed from Vercel, and larger bursts produced 429s. See the [paid-plan results](#production-port-and-paid-plan-trial-25-november-2026) and [release procedure](../backend-hosting.md).

The November 24 sections below record the earlier free-plan trials and the pre-#52 filter. Main now treats raw and escaped plus signs equivalently.

## Deployment

The [Spacefast Next.js recipe](https://spacefast.com/docs/recipes/next/) lists 16.4.x for static export only. The four [Functions](https://spacefast.com/docs/functions/) entries share the existing root, validations, HERE/Mapbox requests, normalization and response construction with the Next.js routes. Only the adapters supply runtime credentials. The production host compiled into the app stays on Vercel.

- Team Departs, Space `departs-api-trial`. V1 and V2 contained the trial API. V2 served the live hostname during the private rounds.
- The private publish receipt described its audience as “Only your team can view this Space after signing in. Change the audience in this Space's Access settings.”

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
| g. Headers | Passed for private responses | See header table. The private host changed the root's public policy. The public V6 results appear below. |
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
- Local checks passed: `npm ci`, `npm run build:spacefast`, `npm run test:run` (98 tests), `npm run test:coverage` (90.72% branches), `npm run lint` and `npm run build`. The Next build still listed all four dynamic paths. Existing tests were preserved. The first round changed the trial backend only.

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

Spacefast CLI 0.10.0 published two preview-only versions. At the end of that round the inventory was **V1** (original API), **V2** (API plus static verification file, live), **V3** (API plus probes, preview) and **V4** (API with fixture provider responses, preview). All four were ready. The V3 and V4 hostnames ran their own functions and returned their respective version headers. Live stayed on V2. All requests in this round used the private Space or the local reference; production received none. The reviewer independently matched the V2 runtime’s bundle digest to the local bytes and confirmed its compatibility date of 2026-07-01.

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
| HEAD / POST / OPTIONS on departures without a stop | 400 / 405 / 405 | 400 with empty body / 405 / 405. Both 405s advertised GET and HEAD. The Next.js reference returned 204 for OPTIONS with `Allow: GET, HEAD, OPTIONS`, and 405 for POST with an empty body and no Allow header. |
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
| Unhandled throw | Spacefast generated a problem document with JSON `status: 502` and delivered HTTP 500 in 0.54 s. The mismatch also affects this platform-generated response. |
| 2 / 5 simultaneous one-second sleeps | All succeeded, in 1.41–1.65 s / 1.29–1.68 s |
| 10 simultaneous one-second sleeps | Six 200s and four 429s, 0.26–1.76 s overall. No Retry-After header. Testing stopped at this burst. |

The team meter rose from 132 to 295 worker requests and from two to four deployments. The reviewers found no worker-meter increment for the two rejected 50-ID requests. This points to refusal before the function, leaving little support for response size as the cause. The three sleep bursts sent 18 requests within 3.4 seconds. Six successes in the last burst fit either concurrent capacity or short-window rate limiting. Both meter readings showed zero cost and an OK budget status. Per-Space settled usage remained unavailable. The final reading covered activity through 10:20:45 UTC.

**Private-round interpretation.** Curl sent the four captured app headers to echo. CFNetwork itself exercised the real API paths using the fixture version. The first dry run classified the default-export echo module as static. Named method exports corrected its manifest. UTC timestamps ending in Z worked for the log API. Filtering access or edge logs by a version hostname returned 422. The live hostname supports those queries. Raw access and edge logs can include long-lived signed bundle links and client addresses. Keep them owner-readable and outside the repository.

## Public trial with real providers, 24 November 2026

### 1. Public access

At 13:03:44 UTC the team had six deployments, 298 metered worker requests and zero metered cost. The owner had written the two provider secrets separately, creating V5 and V6. The inventory showed V1 through V6 ready. V6 served the live host. The following command granted anonymous read access to every live path, with a 45-minute expiry. A fresh curl process received the plain-text root with HTTP 200. No sharing link or session exchange was involved. [Spacefast Share CLI](https://spacefast.com/docs/cli/share/)

```sh
npx -y spacefast@0.10.0 share grant --space spc_d4d85f4115a84205879c2529834957e2 --to public --role viewer --path '/**' --target live --expires 45m --json --api-url https://api.spacefast.com
```

### 2. Real data against production

Each pair consisted of independent anonymous GETs started within one millisecond of each other on the Mac. The nearby radius was 400 m. The batch contained every returned stop ID, including those for which HERE supplied no board.

| Place | Stops | Batch boards / missing | Filtered departures | Walk |
|---|---:|---:|---:|---|
| Vienna | 17 | 17 / 0 | 4 | Identical geometry, duration and distance |
| Berlin Alexanderplatz | 28 | 24 / 4 | 2 | Identical geometry, duration and distance |
| New York City Hall | 49 | 39 / 10 | 4 | Identical geometry, duration and distance |

All 12 pairs returned 200 and gzip-compressed JSON. Stops, filtered departures and walks matched byte-for-byte after decoding. Only the top-level `fetchedAt` differed in the batches. Vercel returned the public TTL for each endpoint and `Age: 0` on the initial misses. Spacefast delivered `private, no-store` and `Vary: Cookie`.

### 3. Caching and board freshness

| Vienna batch, independent curl processes | First | Immediate repeat | At 10 s | At 35 s |
|---|---|---|---|---|
| Spacefast status / CDN | 200 / MISS | 429 | 200 / MISS | 200 / MISS |
| Seconds from Spacefast `fetchedAt` to receipt | 0.30 | — | 0.23 | 0.19 |
| Vercel status / CDN | 200 / HIT | 200 / HIT | 200 / HIT | 200 / MISS |
| Vercel `Age`, seconds | 9 | 10 | 19 | 0 |
| Seconds from Vercel `fetchedAt` to receipt | 9.31 | 9.81 | 19.31 | 0.12 |

Vercel served three separate clients the same batch bytes and timestamp before refreshing. Spacefast returned a fresh timestamp with each 200, including across the curl and Swift runs. The successful samples fit the app’s window of five seconds ahead to 60 seconds behind. No stored Spacefast batch was available to age-test. Distinct city queries returned their own boards, and the two spellings of the Berlin direction returned different rows. These samples showed no cross-query reuse. The documented shared-cache key includes host, path and query. [Caching](https://spacefast.com/docs/caching/)

The root, stops, per-line and walking paths also ran in four repeat rounds, starting at 0, immediately after the first round, 10 and 35 seconds. All 16 Spacefast responses were 200 with `X-ac` reporting MISS, gzip, `Vary: Cookie`, `private, no-store` and no Age or ETag. Successful API responses on Vercel carried `public, max-age=86400` for stops, 30 for departures and 3600 for walks, with gzip and no Vary or ETag. Vercel’s later four-route repeat rounds all met its HTTP 403 Security Checkpoint. Those responses cannot measure the origin’s cache policy. The tested Spacefast configuration was an expiring public grant on the live host. Other hostnames and access configurations were outside the experiment.

### 4. The app’s HTTP client

The macOS harness compiled the app’s APIService, URL construction and Codable models, with a fresh URLSession and the public base address. It decoded all three stop lists, all three real batches, per-line arrays of 0, 4 and 0 from the first stop’s line metadata, and walks with 2, 11 and 7 geometry points. The simultaneous comparisons above selected an active line from each batch, so their per-line counts differ. Against Berlin U2 to S+U Pankow, the app’s raw plus returned zero and the same URLSession with an escaped plus decoded four. Separate curl comparisons gave 0 and 4 on each host. This is the existing app encoding behavior.

### 5. A real 502 branch

Mapbox supplied no walking route between Oahu and Maui. The public worker returned `{"error":"No walking route found"}` with HTTP 500. That exact body identifies the handler branch whose literal status is 502. An earlier open-ocean test hit a different upstream failure branch and returned its usual 500. The contemporaneous Vercel island request met its 403 checkpoint.

### 6. Refusals under normal city requests and isolated bursts

Every five seconds, each client requested the largest real batch for its city ten times. Curl received 7/10, 9/10 and 9/10 successes in Vienna, Berlin and New York. The app’s URLSession decoded 10/10 in each. Those sequences overlapped other trial traffic. The live-host edge records for the five rejected curl requests included `rateLimited: true` and `rateLimitReason: hostratelimit`. Some Vienna requests shared a query and second with the speed run. Every candidate 429 row carried the same reason.

Each burst used different real single-stop queries within the group. The three groups at each size were separated by a minimum of 60 seconds without trial traffic. The table counts admitted HTTP 200s. Log counts use host, query and time after log ingestion.

| Simultaneous requests | First | Second | Third | Edge evidence across all three |
|---:|---:|---:|---:|---|
| 2 | 2/2 | 2/2 | 2/2 | 6 × 200 (rateLimited=false) |
| 5 | 5/5 | 5/5 | 5/5 | 15 × 200 (rateLimited=false) |
| 10 | 6/10 | 6/10 | 6/10 | 18 × 200 (rateLimited=false), 12 × 429 (rateLimited=true, reason empty) |
| 15 | 7/15 | 6/15 | 6/15 | 19 × 200 (rateLimited=false), 5 × 429 (rateLimited=true, crawler-ua), 21 × 429 (rateLimited=true, reason empty) |

The paced batch refusals named a host-level edge rule. All 38 burst refusals had a true rate-limit flag. The reason was empty for 33 and crawler-ua for five. Both classes also appeared as 429 in matching origin access records. An origin log entry does not establish that the application ran. The 429 responses had no Retry-After header. These requests used one hostname, Space and network. The logs do not expose a fixed threshold or establish an independent per-address or per-URL counter. A 429 under this workload does not measure paid-plan capacity. Live-host logs were read after each group and then reread after ingestion because the initial reads could be empty. The origin log query rejected the edge-only hostname option with CLI validation_error. Reading the Space’s access stream and selecting its live hostname locally worked. [Rate limiting](https://spacefast.com/docs/infrastructure/rate-limiting/) · [Edge request logs](https://spacefast.com/docs/infrastructure/edge-request-logs/)

### 7. Speed from the test Mac

Each row used 20 sequential curl GETs per host. The two hosts ran side by side, and other city tests overlapped part of the warm run. Values are median / nearest-rank 90th percentile / maximum of **all** attempts in milliseconds. The last column gives Spacefast then Vercel status and elapsed time after 603 seconds of trial silence. Root was first, followed by each previously idle API path. These timings include network setup. They do not isolate worker startup.

| Vienna request | Spacefast ms | 200s | Vercel ms | 200s | After idle, HTTP / ms (Spacefast · Vercel) |
|---|---:|---:|---:|---:|---|
| Root | 362 / 475 / 1126 | 20/20 | 89 / 183 / 190 | 0/20 | 200 / 550 · 200 / 901 |
| Stops | 539 / 620 / 721 | 20/20 | 161 / 253 / 297 | 20/20 | 200 / 659 · 200 / 85 |
| Full batch | 513 / 732 / 848 | 11/20 | 196 / 289 / 294 | 20/20 | 200 / 700 · 200 / 310 |
| Per line | 543 / 762 / 1068 | 20/20 | 195 / 256 / 373 | 20/20 | 200 / 916 · 200 / 235 |
| Walk | 441 / 567 / 603 | 20/20 | 184 / 233 / 503 | 18/20 | 200 / 300 · 200 / 95 |

The nine unsuccessful Spacefast batch requests received 429. Their fast responses lower the all-attempt median. Successful Spacefast batches took 618 / 787 / 848 ms. Vercel’s 20 warm roots and two warm walks received its 403 HTML security checkpoint. The 18 successful Vercel walks took 175 / 261 / 503 ms. After the quiet interval both roots returned identical plain-text bytes. Vercel’s root delivered its public 3,600-second TTL and Spacefast’s root delivered private, no-store. The four post-idle API payloads also matched after allowing the batch timestamp.

### 8. Client identity

For the same public Vienna batch, default curl and curl with the four captured app headers received 200. Curl with no User-Agent and the actual Python default client received 429. Both edge rows named hostratelimit. The real app URLSession succeeded independently. The observed client outcomes do not isolate a particular request header as the cause.

### 9. Forwarding for installed builds

Branch `trial/vercel-forward` at `a06e0c9`, based on `origin/main` at `c0cdbf9`, contains only the two external rewrites for `/` and `/api/:path*`. Vercel reported a successful preview deployment. The first anonymous nearby-stops GET returned 302 to Vercel sign-in. Two Berlin requests also included the preview because the local comparison client retained it in its host list. They received the same 302. No session exchange or follow-up through authentication occurred. Forwarded response status, body, headers, query preservation and latency remain unverified. The forwarding branch has no PR.

### 10. Access restored, usage and cost

The explicit revocation returned CLI `confirmation_required`. The response supplied no approval ID. The operation stopped there. The grant expired at 13:48:45.891 UTC. At 13:48:48 UTC a new anonymous root request returned **403**. All three API paths also returned 403 to anonymous GETs with no provider parameters. V6 remained live. The team worker-request meter moved from 298 to 563 (+265), measured through 13:31:29 UTC. Deployments remained at 6. The team meter showed $0 and budget status ok. The closing read occurred after access expired. Its measurement cutoff covered the last successful public GET. The two Spaces on this team share the meter.

The trial sent 142 ordinary GETs directly to production. Even charging every Spacefast transit GET to its provider and counting both possible attempts for every departure request, this client workload could have issued at most 524 provider calls through Spacefast. A batch is one HERE call per attempt regardless of stop count. Actual provider-billed calls were unavailable.

The Personal plan costs $0/month and includes $1 of shared monthly usage. At the listed $0.30 per million worker requests, the meter increase alone corresponds to roughly $0.000079, before allowances and other meters. Personal lists 10 GB uncached traffic, then $0.04/GB. It lists two dynamic compute workers per Space. The observed edge refusals cannot be converted into a concurrency entitlement or a promise that a paid plan fixes them. Provider charges, domain registration and Vercel forwarding traffic remain separate. [Pricing & Limits](https://spacefast.com/docs/pricing/)

### 11. What a move needs

1. **Deploy the verified artifact.** Keep the shared handlers and bundle the four Functions entries with `npm run build:spacefast`. Check the staged manifest, run the API tests, then publish the prebuilt artifact. For automatic releases, an owner with repository access must authorize Spacefast’s GitHub App and select Departs. Configure the build command and output directory explicitly, set `main` as the production branch, and enable branch previews. Verify a preview on a push before switching live. Each secret write created a new version here, so coordinate rotations with releases. Rollback was exercised in the private trial. [Publish from Git](https://spacefast.com/docs/git/) · [Functions](https://spacefast.com/docs/functions/) · [Environment variables](https://spacefast.com/docs/environment-variables/)
2. **Put an owned API hostname in the next app release.** Assign a subdomain the owner controls, publish the exact records required at its DNS provider, complete any ownership challenge, and wait for active managed HTTPS. Recheck the direct API and raw/encoded query cases on that hostname. Domain registration and renewal are separate costs. The Personal plan lists 20 custom domains. [Custom domains](https://spacefast.com/docs/domains/) · [Pricing & Limits](https://spacefast.com/docs/pricing/)
3. **Keep a working route for installed builds.** The existing binary always starts at `departs.vercel.app`, which stays with Vercel. The lowest-risk cutover is to keep today’s Vercel backend for old builds and release the owned hostname for new builds. That temporarily operates two backends. A verified Vercel external rewrite could later reduce this to one backend while keeping the old hostname. Vercel still handles requests and may meter delivery. A temporary 307 is another option because the app’s default URLSession follows HTTPS redirects for these GETs. That adds a phone round trip and requires preservation of the complete encoded query. Closing Vercel would end refresh on remaining old builds. The protected preview left the rewrite’s on-wire behavior, added latency and Vercel usage unmeasured. [Vercel rewrites](https://vercel.com/docs/rewrites) · [Apple URLSession](https://developer.apple.com/documentation/foundation/urlsession)
4. **Set release criteria around a rider’s first refresh.** Establish acceptable success and latency for a board refresh plus up to three walks on an iPhone over cellular. Confirm provider quotas, permitted cache durations and any attribution requirements under the owner’s HERE and Mapbox agreements. Decide how to deliver the three TTLs and preserve the original batch timestamp. Verify freshness, query separation, error statuses, methods and the legacy forwarder before moving old builds. The largest live batch here was 49 IDs. The 50-ID success was a private fixture. One Mac, one network and one limited public-access window cannot establish fleet reliability or a global cold-start or capacity guarantee.

## Production port and paid-plan trial, 25 November 2026

The API reported the team plan as `plus`. At 00:46:53 UTC Spacefast marked V7 ready and promoted it to live. Its source was a configuration update. The file manifest matched V6, with zero files added, removed or changed. The activity feed did not identify the configuration field that triggered the release.

The production port starts at main’s `c7e2cac`. It includes the #52 filter, the null-line provider-array regression, and the same Next.js and Functions adapters exercised in the trial. At a fixed clock, all 13 local main/branch fixture comparisons matched on status, every response header and exact body bytes. They covered the root, nearby stops, single, grouped, filtered and batch departures, walking directions and invalid inputs. The branch passed 107 tests, lint and both production builds. V8 published the four Functions entries from `1b66780`. A permanent public viewer grant covers the live paths. The secret values stayed with the platform.

Spacefast attached `api.departs.now` to the backend at 00:57 UTC and supplied two routing records. At 01:15 UTC two independent public resolvers returned SERVFAIL. The project owner’s coordinator separately verified that the registry delegated the zone to Spacefast nameservers, both refused the zone, and the zone was configured for external DNS. All public Spacefast measurements in this section used the managed hostname. A switch of authoritative DNS requires the owner’s separate decision.

### Rider and provider data

A macOS harness ran the app’s actual APIService, TransitStore, models, walk scheduling and persistence with an empty preference suite. A stationary Vienna rider stayed on Home, opened the first available line for four ticks, and returned to Home. The harness supplied a fresh accurate location on each 30-second tick for ten minutes. There was one listed physical group at this hour. Every one of the 24 network transactions succeeded: two nearby lookups, 20 departure requests and two walks. All were CDN misses with `no-cache, must-revalidate, max-age=0`. URLSession also reported a local-cache transaction for nearby stops. This tests the Mac networking stack and this rider’s demand. A cellular phone and a daytime list of many stops remain separate cases.

Ten anonymous 50-ID batches on each host all returned 200. The IDs came from the three cities’ real station lists. Spacefast returned 44 boards and six missing on its first batch. Its default curl response carried `public, max-age=30`, unlike the November 24 temporary-grant experiment. At expiry, Spacefast served the previous timestamp once at age 30.8 seconds and refreshed it for the following hit. Vercel fetched a new batch at expiry. Both sequences remained within the app’s 60-second past limit. The plan, access grant and platform configuration changed between trials, so these observations cannot isolate the effect of the plan upgrade alone.

### Error and cache behavior

| Request | Spacefast | Vercel or local Next.js reference |
|---|---|---|
| Walk from Oahu to Maui | 500 JSON | Production 502, identical JSON |
| Missing stop parameter | 400 JSON | Production 400, identical JSON |
| Unknown API route | 404 HTML, 13,571 decoded bytes | Production 404 HTML, 6,999 decoded bytes |
| OPTIONS on departures | 405, 19-byte body, Allow GET and HEAD | Production 204, empty body, Allow GET, HEAD and OPTIONS |
| Unhandled exception | On a private paid-plan preview, HTTP 500 and a platform problem document with body status 502 | An isolated production build of main with a synthetic throwing handler returned HTTP 500 and an empty body. No exception route was added to either live backend. |

With a permanent public grant, default curl received live Functions responses with the application TTLs, Vary on Accept-Encoding, and shared-cache hits. Stops hit again at 35 seconds. The 30-second Vienna batch was served stale once during revalidation. V10 tested two path-specific `Cache-Control` overrides including `s-maxage`. Spacefast compiled both and recorded `header_cache_control_platform_managed` for each. The delivered headers retained their original max-age and omitted s-maxage on both paths. Stops still hit, the batch still went stale during refresh, and invalid input returned `no-store`. V11 restored the original four-entry artifact. Documented cache-bypass rules disable caching. The routing compiler reserves CDN-specific control headers. [Caching](https://spacefast.com/docs/caching/) · [Routing](https://spacefast.com/docs/routing/)

In a private fixture preview, two synthetic timestamp entries in `env.DB` used the stops and departures TTLs. On the second request both entries hit. After 32 more seconds the stops entry hit again and departures generated a new timestamp. Every response was still a CDN miss. The temporary table was removed. This establishes cross-request application storage and independent expiry. The experiment stored no rider locations or provider payloads. [Functions](https://spacefast.com/docs/functions/)

### Capacity, freshness and cost

Six requests spaced two seconds apart and six spaced one second apart all succeeded. Bursts of two and five also succeeded. A burst of ten returned six stale successes, three successful misses and one 429. The team worker meter moved from 611 to 617. In a separate burst of ten distinct previously unrequested stop queries, every request missed. Six returned 200, four returned 429, and the worker meter moved from 645 to 651. This supports refusal before worker execution for the four rejected cold requests. It does not establish a fixed cap of six on all workloads. Testing stopped at the first refusal in each series. The measured 429 was a 1,168-byte HTML “429 Too Many Requests” page with an ETag, no Retry-After and no application JSON. The settled mixed-burst edge log flagged the refusal as rate-limited with an empty reason. One client address and one Space cannot distinguish a client limit from a Space limit.

With local URL caching disabled, macOS URLSession requested the same batch four times, alternating default and reload policies. Spacefast returned four misses, four new timestamps and `no-cache, must-revalidate, max-age=0`. Vercel returned a miss and three hits, with its public 30-second TTL. The reload policy alone does not account for the host difference.

The measurement window added 85 team worker requests (566 to 651), with zero metered dollars. There were 51 production requests, including one OPTIONS, and no 403. Curl waited at least 2.1 seconds between production requests; URLSession waited three seconds after each completion. On Spacefast, 114 public GETs could have needed a provider result: 53 successful or no-route misses, 34 hits, 22 stale responses and five refused requests. Vercel had 43 such GETs: ten misses and 33 hits. Counting a possible background refresh on each stale response, pessimistically charging each refusal to the provider, and allowing each departure fetch its one retry gives ceilings of 151 provider calls through Spacefast and 17 through Vercel. The team meter counts workers rather than HERE or Mapbox calls. Exact upstream attempts and provider billing were unavailable. The fixture and database experiments made zero provider calls.

The timing comparison used one network. After restoring the unmodified artifact, the Spacefast cache started empty. Vercel’s first stops request still hit its persistent cache. A warm-hit comparison therefore answers a different question from an app refresh that misses. The following tables retain the cache state alongside the timings.

### Paid-plan observations by request group

Ordered observations use HTTP status/CDN status. Multipliers count consecutive identical results. Each row reads left to right. For latency rows the first observation is after idle, followed by four warm requests. The production reference stopped on its first 403 if encountered.

| Host | Group | Status / cache, in request order |
|---|---|---|
| Spacefast | Ten-minute rider, HTTP transactions | 200/MISS ×12, 200/MISS (local URL cache), 200/MISS ×12 |
| Spacefast | 50 IDs, paced | 200/MISS, 200/HIT ×5, 200/STALE, 200/HIT ×3 |
| Vercel | 50 IDs, paced | 200/MISS, 200/HIT ×5, 200/MISS, 200/HIT ×3 |
| Spacefast | One request every 2 s | 200/MISS ×6 |
| Spacefast | One request per second | 200/STALE ×6 |
| Spacefast | burst-2 | 200/STALE ×2 |
| Spacefast | burst-5 | 200/STALE ×5 |
| Spacefast | burst-10 | 200/STALE ×6, 429/MISS, 200/MISS ×3 |
| Spacefast | No route / invalid / missing / OPTIONS | 500/MISS, 400/MISS, 404/MISS, 405/BYPASS |
| Vercel | No route / invalid / missing / OPTIONS | 502/MISS, 400/MISS, 404/MISS, 204/MISS |
| Spacefast | cache stops | 200/MISS, 200/HIT ×3 |
| Spacefast | cache batch | 200/MISS, 200/HIT ×2, 200/STALE |
| Vercel | cache stops | 200/MISS, 200/HIT ×3 |
| Vercel | cache batch | 200/MISS, 200/HIT ×2, 200/MISS |
| Private measurement preview | Unauthenticated preview | 403/MISS |
| Private measurement preview | Throwing fixture | 500/MISS |
| Private measurement preview | DB create / TTL reads / cleanup | 200/MISS ×8 |
| Spacefast with header rules | cache stops | 200/MISS, 200/HIT ×3 |
| Spacefast with header rules | cache batch | 200/MISS, 200/HIT ×2, 200/STALE |
| Spacefast with header rules | Invalid stops / batch | 400/MISS ×2 |
| Spacefast | latency-root | 200/MISS, 200/HIT ×4 |
| Spacefast | latency-stops | 200/MISS, 200/HIT ×4 |
| Spacefast | latency-batch | 200/MISS, 200/HIT ×4 |
| Spacefast | latency-line | 200/MISS, 200/HIT ×4 |
| Spacefast | latency-walk | 200/MISS, 200/HIT ×4 |
| Vercel | latency-root | 200/MISS, 200/HIT ×4 |
| Vercel | latency-stops | 200/HIT ×5 |
| Vercel | latency-batch | 200/MISS, 200/HIT ×4 |
| Vercel | latency-line | 200/MISS, 200/HIT ×4 |
| Vercel | latency-walk | 200/MISS, 200/HIT ×4 |
| Spacefast | fresh 10 simultaneous | 429/MISS, 200/MISS ×4, 429/MISS, 200/MISS, 429/MISS ×2, 200/MISS |
| Spacefast | URLSession, default / reload / default / reload | 200/MISS ×4 |
| Vercel | URLSession, default / reload / default / reload | 200/MISS, 200/HIT ×3 |

### Latency from the test Mac

The first GET followed at least ten minutes without trial traffic to that host. Other endpoints followed the root and had also been idle. Four repeats per path followed. Figures include DNS lookup, TLS and transfer. A CDN hit or HTTP refusal cannot establish worker startup time.

| Host | Path | First status / cache / ms | Warm median / p90 / maximum, ms | Warm 200s |
|---|---|---|---|---:|
| Spacefast | root | 200 / MISS / 902 | 36 / 53 / 53 | 4 / 4 |
| Spacefast | stops | 200 / MISS / 885 | 38 / 43 / 43 | 4 / 4 |
| Spacefast | batch | 200 / MISS / 828 | 34 / 35 / 35 | 4 / 4 |
| Spacefast | line | 200 / MISS / 812 | 33 / 34 / 34 | 4 / 4 |
| Spacefast | walk | 200 / MISS / 704 | 32 / 36 / 36 | 4 / 4 |
| Vercel | root | 200 / MISS / 830 | 85 / 90 / 90 | 4 / 4 |
| Vercel | stops | 200 / HIT / 77 | 80 / 83 / 83 | 4 / 4 |
| Vercel | batch | 200 / MISS / 372 | 81 / 84 / 84 | 4 / 4 |
| Vercel | line | 200 / MISS / 251 | 77 / 84 / 84 | 4 / 4 |
| Vercel | walk | 200 / MISS / 340 | 73 / 75 / 75 | 4 / 4 |

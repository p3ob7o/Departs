# Two screens — Phase 0 validation

Source: [two-screen plan](ios-two-screens.md), owner decisions O1–O9 and accepted choices A1–A9. This phase changes the departures backend only. It changes no app version, device support or native code.

## Contract

`GET /api/departures?stopIds=a,b,c` accepts 1–50 comma-separated IDs and responds with `{ fetchedAt, boards: [{ stopId, groups }], missing }`. One HERE request asks for 50 departures per platform and two per transport. Groups keep the existing line identity and predicted-time ordering. Empty boards and missing boards are different states. Missing or capped-away lines are not synthesized.

The timestamp is captured immediately before the successful provider attempt and is retained in the 30-second CDN response. The provider fetch explicitly uses `no-store`, so a fresh timestamp cannot wrap a reused Next.js data-cache result. Network errors, timeouts and upstream 5xx receive one retry. A final failure logs one fixed error class and, for HTTP errors, the numeric upstream status. No URL, provider body, arbitrary error message or credential is logged.

## Acceptance

| Requirement | Local/fixture result | Preview | Production |
| --- | --- | --- | --- |
| 17 sample IDs, one request, 17 boards | Passed; one MSW-observed provider request; all 17 identities and first two departures match single-stop groups | Passed: 17/17 boards, 28 groups, zero mismatches across all 17 single-stop comparisons | Passed: 17/17 boards, 28 groups, no mismatches |
| Existing `stopId` tests unchanged | Passed; original test file is byte-identical to the plan base | 17/17 Vienna grouped responses match the batch's first two departures | Single-stop comparisons unchanged; no mismatches in this run |
| One sanitized failure log and 502 | Passed for batch 503/401/429, network failures, timeouts and invalid responses; retries bounded to two attempts | Failure injection is a fixture check | Not injected |
| Provider age rather than receipt age (T16) | Passed with a response delayed ten seconds; timestamp remains the request start | Two requests return identical `fetchedAt`; second response is `x-vercel-cache: HIT`, `age: 1` | Verified after merge; details below |
| 1–50 IDs | Passed for 1, 17 and 50; 0/empty entries/51 and ambiguous requests rejected before HERE | 50 accepted: 47 boards plus the same three missing Berlin IDs; every requested ID accounted for | Verified after merge; details below |
| Two live locations | Not claimed locally; no provider credentials in checkout | Vienna and Berlin verified; details and one provider difference below | Verified after merge; details below |

Checks: `npm ci`, `npm run test:run` (**95 tests passed**), `npm run lint`, `npm run build`, and `git diff --check`. Native tests are not rerun for this backend-only phase. No screenshots or raw provider responses are added to Git.

## Decisions made

- Keep the legacy HTTP 500 error response as well as successful single-stop arrays/grouped responses. The plan simultaneously requires unchanged single-stop tests (one asserts 500) and a new 502 upstream error. The additive `stopIds` path uses 502; both paths gain the retry and sanitized logging. This preserves the installed-build contract.
- Trim and deduplicate IDs in first-occurrence order, with the 50-entry limit applied before deduplication. Reject mixing `stopIds` with `stopId`, single-line filters or `groupBy`, and reject repeated `stopIds` parameters, rather than choose an ambiguous interpretation.
- Return boards in requested-ID order, including empty returned boards. Ignore unrelated returned platform IDs; list absent requested IDs in `missing`. A malformed upstream payload is a failure, not an empty successful result.
- Keep the existing 30-second HTTP cache policy; `fetchedAt` makes its age explicit. Do not change single-stop response bodies to add a timestamp.
- HERE accepted 50 IDs in one call on preview, so no server splitting is needed.

## Live preview, 16 November 2026

Verified source `9899c716b871b04ddae09e9b6602af1d98eb7593` on [the protected preview](https://departs-qz8pa6vx9-p3ob7os-projects.vercel.app), using the owner's existing Vercel CLI authentication. The Vercel connector was not available in this session. Provider credentials were not downloaded. Raw responses remain outside Git and there is no evidence branch.

- **Vienna, 48.20134 / 16.34941, 18:45 CET:** 17 nearby platforms, 17 returned boards, 28 groups, no missing platforms. One batch HTTP request compared with 17 single-stop grouped calls: every line identity and first two departures matched exactly. The batch took 1.306 seconds including CLI startup/authentication, not a provider-latency benchmark.
- **Berlin Alexanderplatz, 52.5219 / 13.4132, 18:45 CET:** 27 requested platforms, 24 returned boards and three missing IDs (`49031_23292`, `49031_19677`, `49031_19684`). Each missing platform's single-stop call also returned no groups. All returned line identities matched; 23/24 boards matched the first two times exactly.
- **Provider difference to retain as a known limit:** one Berlin U2 → S+U Pankow group differed between the two-departure batch and four-departure single-stop response. Concurrent uncached checks at 18:48 reproduced it: batch times 18:50/18:58, single-stop first two 18:50/18:54. All were scheduled (`realTime: false`). This is a difference in the provider responses under the two request limits, not client filtering. Keep the plan's two-per-transport request; do not add fan-out or silently change its request budget. Exact timetable parity is established for the required 17-platform Vienna sample, not promised for every provider response.
- **Limit:** a single batch of 50 distinct Vienna/Berlin IDs returned 47 boards and exactly those three known absent Berlin IDs, HTTP 200. The 50-ID request took 1.173 seconds including CLI overhead. No provider-limit split or additional per-ID call was required by the handler.
- **Cache:** the second identical request was a CDN HIT with age one second and the same provider timestamp. The server does not relabel a cached response as newly fetched.

The preview verification used **53 departure HTTP requests**: an access probe, two location batches plus 44 single-stop comparisons, two limit checks, two cache checks, and two concurrent Berlin diagnostic calls. These were brief checks, not a load test. Production was not called during this preview verification. Provider quota, cost per batched call and latency under load remain unmeasured.

## Findings covered

- **T2:** bounded retry and one credential-safe final failure log, tested for status and network failures.
- **T4:** one provider request for a 17-platform batch; native opening/refresh counts belong to Phase 1.
- **T16:** provider-call timestamp retained across response delay/CDN caching; app freshness consumption belongs to Phase 1.

## Production verification, 16 November 2026

The owner approved merging #26 and #27. Plan #26 landed as `e0ece6d7e92c9829030a98087e5b89ae45b33255`; Phase 0 was retargeted to `main` and merged as `fbce84061c45a797e6f3d53d986679e084d1234c`. Vercel then deployed the batch handler on the existing production host.

At 18:56 CET, Vienna returned 17/17 boards and 28 groups, and Berlin returned 24/27 boards and 111 groups. Berlin had the same three absent IDs as preview. Every sampled line identity and first two times matched the concurrent single-stop comparison in this run. This does not erase the reproducible Berlin preview difference above. A wider Vienna query returned 26/26 boards. A CDN HIT with age one retained the provider timestamp. These checks used 47 departure HTTP requests; raw responses stay outside Git.

Failure injection, provider quota/cost, load latency and capped-hub behavior were not tested on production.

## Landing and release order

The backend is in production. Later native phases must each be retargeted to and merged into `main` in order with owner approval; merging into an already-merged phase branch does not update `main`. The app's version/build remain unchanged. Version 1.2 preparation, further merges and TestFlight uploads require a new owner instruction.

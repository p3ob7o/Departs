# Two screens — Phase 0 validation

Source: [two-screen plan](ios-two-screens.md), owner decisions O1–O9 and accepted choices A1–A9. This phase changes the departures backend only. It changes no app version, device support or native code.

## Contract

`GET /api/departures?stopIds=a,b,c` accepts 1–50 comma-separated IDs and responds with `{ fetchedAt, boards: [{ stopId, groups }], missing }`. One HERE request asks for 50 departures per platform and two per transport. Groups keep the existing line identity and predicted-time ordering. Empty boards and missing boards are different states. Missing or capped-away lines are not synthesized.

The timestamp is captured immediately before the successful provider attempt and is retained in the 30-second CDN response. The provider fetch explicitly uses `no-store`, so a fresh timestamp cannot wrap a reused Next.js data-cache result. Network errors, timeouts and upstream 5xx receive one retry. A final failure logs one fixed error class and, for HTTP errors, the numeric upstream status. No URL, provider body, arbitrary error message or credential is logged.

## Acceptance

| Requirement | Local/fixture result | Preview | Production |
| --- | --- | --- | --- |
| 17 sample IDs, one request, 17 boards | Passed; one MSW-observed provider request; all 17 identities and first two departures match single-stop groups | Pending | Awaiting owner-approved merge |
| Existing `stopId` tests unchanged | Passed; original test file is byte-identical to the plan base | Pending live parity | Existing production unchanged |
| One sanitized failure log and 502 | Passed for batch 503/401/429, network failures, timeouts and invalid responses; retries bounded to two attempts | Failure injection is a fixture check | Not injected |
| Provider age rather than receipt age (T16) | Passed with a response delayed ten seconds; timestamp remains the request start | Pending CDN check | Awaiting merge |
| 1–50 IDs | Passed for 1, 17 and 50; 0/empty entries/51 and ambiguous requests rejected before HERE | Provider limit pending | Awaiting merge |
| Two live locations | Not claimed locally; no provider credentials in checkout | Pending | Awaiting merge |

Checks: `npm ci`, `npm run test:run` (**95 tests passed**), `npm run lint`, `npm run build`, and `git diff --check`. Native tests are not rerun for this backend-only phase. No screenshots or raw provider responses are added to Git.

## Decisions made

- Keep the legacy HTTP 500 error response as well as successful single-stop arrays/grouped responses. The plan simultaneously requires unchanged single-stop tests (one asserts 500) and a new 502 upstream error. The additive `stopIds` path uses 502; both paths gain the retry and sanitized logging. This preserves the installed-build contract.
- Trim and deduplicate IDs in first-occurrence order, with the 50-entry limit applied before deduplication. Reject mixing `stopIds` with `stopId`, single-line filters or `groupBy`, and reject repeated `stopIds` parameters, rather than choose an ambiguous interpretation.
- Return boards in requested-ID order, including empty returned boards. Ignore unrelated returned platform IDs; list absent requested IDs in `missing`. A malformed upstream payload is a failure, not an empty successful result.
- Keep the existing 30-second HTTP cache policy; `fetchedAt` makes its age explicit. Do not change single-stop response bodies to add a timestamp.
- No speculative server splitting is added before checking HERE's live limit. If the preview demonstrates a limit below 50, split on the server and reverify before accepting this phase.

## Findings covered

- **T2:** bounded retry and one credential-safe final failure log, tested for status and network failures.
- **T4:** one provider request for a 17-platform batch; native opening/refresh counts belong to Phase 1.
- **T16:** provider-call timestamp retained across response delay/CDN caching; app freshness consumption belongs to Phase 1.

## Landing and release order

This draft PR targets `feat/ios-two-screens`. After preview acceptance, ask the owner to approve merging plan PR #26 into `main`, then retarget this Phase 0 PR to `main`, inspect its diff and checks, and merge it. Do not merge it into the already-merged plan branch. Verify both live locations on production after Vercel deploys. Later phase PRs follow the same retarget-to-`main` sequence. No merge, production deployment, version 1.2 preparation or TestFlight upload is authorized by this implementation phase.

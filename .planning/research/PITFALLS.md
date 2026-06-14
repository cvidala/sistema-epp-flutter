# Pitfalls Research

**Domain:** Advanced testing — Flutter load tests, Supabase Edge Function tests, golden file tests on existing system
**Researched:** 2026-06-13
**Confidence:** HIGH (all three areas verified against official docs, community post-mortems, and codebase inspection)

---

## Critical Pitfalls

### Pitfall 1: Hive singleton leaks state across load tests

**What goes wrong:**
`OfflineQueueService` stores its open box reference via `Hive.box<String>('outbox_entregas')`. When a load test creates 50+ entries in one test group, then a second group calls `OfflineQueueService.init()` again, Hive silently re-uses the already-open box rather than reopening it. The second group starts with all the entries left by the first group. Counts are wrong, ordering assertions fail, and backoff tests see stale `nextRetryAt` values from previous runs.

The existing tests in `offline_queue_test.dart` avoid this correctly with `hive_test`'s `setUpTestHive`/`tearDownTestHive`. Load tests that skip this pattern or that run multiple concurrent groups will hit it.

**Why it happens:**
Hive is designed as an in-process singleton. If `Hive.openBox()` is called when the box is already open, it returns the existing instance — no error, no reset. Developers assume each test starts clean because `setUp` is called, but calling `OfflineQueueService.init()` a second time does nothing when the box is open from a previous test.

**How to avoid:**
- Every load test group must call `setUpTestHive()` before `OfflineQueueService.init()` and `tearDownTestHive()` after.
- Do NOT call `Hive.openBox()` directly in load tests — go through `setUpTestHive`/`tearDownTestHive` from `package:hive_test` which handles the temporary directory and full cleanup.
- Use a unique box name per test file if tests must run concurrently (`'outbox_load_${DateTime.now().microsecondsSinceEpoch}'`), or use `--concurrency=1` for Hive-dependent test files.

**Warning signs:**
- A load test passes in isolation but fails when the full `flutter test test/unit/` suite runs.
- `listPending()` returns N + M entries when M entries were expected (N leftover from a prior test).
- `HiveError: Box has already been closed` — this is the inverse: tearDown ran but setUp did not reinitialize before the next test.

**Phase to address:**
Phase 1 (Load/stress tests for Hive queue). Enforce the `setUpTestHive`/`tearDownTestHive` pattern as a precondition before writing any load test.

---

### Pitfall 2: fakeAsync cannot drive real Hive I/O — stress tests hang silently

**What goes wrong:**
Load tests that wrap Hive operations inside `fakeAsync()` hang forever or produce misleading "pending timers" errors. `fakeAsync` controls Dart's timer queue but has no power over native I/O operations, including Hive's file writes (`hive_flutter` uses `path_provider` and native filesystem). The zone waits for futures that will never resolve within the fake-time frame.

**Why it happens:**
Developers reach for `fakeAsync` to control `nextRetryAt` timestamps (backoff logic) and to compress simulated time. This works for pure-Dart logic. It breaks when the same test also calls `OfflineQueueService.enqueue()` or `listPending()` that touch Hive boxes, because those futures are backed by native I/O outside the zone.

**How to avoid:**
- Use real `async`/`await` for all Hive operations in load tests.
- Control backoff timestamps by constructing `OfflineEntrega` with explicit `nextRetryAt` strings set to past/future ISO timestamps — no timer manipulation needed.
- If time manipulation is needed (e.g., simulating the 60-minute cap), use `Clock` injection or pass a `now` parameter to the method under test rather than relying on `fakeAsync` to advance wall time.
- The existing tests in `offline_queue_test.dart` already use this pattern correctly — replicate it at load scale.

**Warning signs:**
- A test hangs for more than 5 seconds with no output.
- The test runner reports "Pending timers: 1 timer (periodic)" with no failure message.
- Tests pass when run individually (`flutter test test/unit/offline_queue_load_test.dart`) but hang in the full suite.

**Phase to address:**
Phase 1 (Load/stress tests). Document the fakeAsync incompatibility in the test file header as a comment so future contributors don't reintroduce it.

---

### Pitfall 3: Edge Function test triggers real Resend email sends in CI

**What goes wrong:**
`notif-vencimiento/index.ts` calls `fetch('https://api.resend.com/emails', ...)` with a live `RESEND_API_KEY`. A test that invokes this function against the real project — or even against a local `supabase functions serve` instance with secrets loaded — sends actual emails to actual `email_notif` addresses in the `perfiles` table. If CI uses the production Supabase project (which this repo currently does for integration tests), every CI run sends notification emails to real users.

**Why it happens:**
The function has no test-mode guard. Secrets are injected identically in test and production environments. Developers testing "does the function respond 200?" don't realize the function also iterates all orgs and fires emails for each.

**How to avoid:**
Two complementary strategies are required — use both:

1. **Mock `fetch` in Deno unit tests.** Test the function's business logic (grouping by org, building subject lines, building HTML) without a real HTTP call. Use Deno's `stub()` from `@std/testing/mock` to replace `globalThis.fetch` for the Resend call and assert it was called with the correct payload:
   ```typescript
   import { stub } from "jsr:@std/testing/mock";
   const fetchStub = stub(globalThis, "fetch", () =>
     Promise.resolve(new Response('{"id":"test"}', { status: 200 }))
   );
   try {
     // invoke handler logic
   } finally {
     fetchStub.restore();
   }
   ```

2. **Add a `DRY_RUN` env var guard in the function itself.** When `Deno.env.get('DRY_RUN') === 'true'`, skip the `fetch` call and log what would have been sent. This guard can be set in `.env.local` for all local/CI runs.

**Warning signs:**
- A test against `supabase functions serve` succeeds with a 200 — and a real user emails you asking why they received a test notification.
- `RESEND_API_KEY` appears in GitHub Actions secrets alongside `SUPABASE_SERVICE_ROLE_KEY` without a corresponding `DRY_RUN=true` guard.
- Resend billing shows unexpected send volume spikes after CI runs.

**Phase to address:**
Phase 2 (Edge Function tests). The `DRY_RUN` guard must be added to `notif-vencimiento/index.ts` before any test scaffold is written.

---

### Pitfall 4: Edge Function tests run against production data, not isolated test data

**What goes wrong:**
`notif-vencimiento` queries `get_vencimientos_proximos()` (an RPC) and reads `perfiles`. If tests invoke the function against the real Supabase project (the pattern already established for integration tests in this repo), the function will email all real workers with expiring EPP — not just test data. Inserting test EPP records with fake vencimiento dates to trigger the function also contaminates the production DB.

**Why it happens:**
This repo's integration tests (RLS, triggers, RPCs) run against the real project with real credentials — confirmed in `test.yml`. This is intentional and was a deliberate decision. The same pattern applied to Edge Functions that send emails is dangerous.

**How to avoid:**
- Test the function's logic layer (DB query → grouping → email construction) with Deno unit tests and mocked DB client, completely decoupled from the real Supabase project.
- For integration-level "does the function reach the DB and return 200?" tests, either: (a) use a Supabase local stack (`supabase start`) with seeded test data, or (b) add the `DRY_RUN` guard and accept that the function connected but did not send.
- Never insert test vencimiento records with real EPP IDs into the production project just to trigger test scenarios — use dedicated test rows that are cleaned up in `tearDown` or that use a prefix like `test_` on `localEventId`-equivalent fields.

**Warning signs:**
- The Edge Function test setup inserts rows into `stock_epps` or `entregas_epp` in the production project and doesn't clean them up.
- CI uses `SUPABASE_SERVICE_ROLE_KEY` (production) for Edge Function tests with no `DRY_RUN` guard.
- `get_vencimientos_proximos()` returns real worker data during a test run.

**Phase to address:**
Phase 2 (Edge Function tests). Define the test boundary (unit with mocks vs. integration with local stack) before writing any test.

---

### Pitfall 5: Golden files generated on macOS fail on Linux CI

**What goes wrong:**
Golden files generated locally on macOS (text rendered with CoreText) differ pixel-by-pixel from the same widget rendered on Ubuntu CI (text rendered with FreeType/Skia with different font hinting). The test suite that passes locally fails every CI run, even when no UI changes were made. The developer updates goldens to fix CI, but now they fail locally.

This project's CI uses `ubuntu-latest` (confirmed in `test.yml`). Development happens on macOS (Darwin 25.5.0 from environment). Golden files committed from macOS will always fail on CI.

**Why it happens:**
`matchesGoldenFile` compares PNG bitmaps pixel-by-pixel (with zero tolerance by default). macOS and Linux use different font rendering pipelines. Even with identical Dart/Flutter versions, text widgets render differently across platforms. The problem is structural, not a bug.

**How to avoid:**
Choose one of two approaches before writing any golden file:

**Option A (recommended for this project — simplest):** Generate and validate goldens exclusively on Linux. Add a dedicated `golden-tests` CI job on `ubuntu-latest`. Never commit goldens from macOS. Run `flutter test --update-goldens` locally only via Docker with a Linux image (e.g., `cirrusci/flutter`), or update goldens by pushing a branch and letting CI regenerate them.

**Option B:** Use the `alchemist` package (`flutter_test_goldens`), which provides deterministic font loading and platform-agnostic rendering. Alchemist generates two golden variants: `ci/` (Linux-generated, validated in CI) and `local/` (macOS-generated, for local review). Requires updating the test runner and introducing a new dependency.

For TrazApp's scale (3 target screens), Option A is sufficient.

**Warning signs:**
- First golden test commit on macOS passes locally but immediately fails in CI with a pixel-diff error.
- The diff image shows blurry/different text rendering, not structural differences.
- `flutter test --update-goldens` is run locally and the result is committed without verifying on CI first.

**Phase to address:**
Phase 3 (Golden file tests). Establish the platform strategy as the first step, before writing a single `matchesGoldenFile` call.

---

### Pitfall 6: Custom fonts render as "Ahem" squares in golden files

**What goes wrong:**
Flutter's test environment does not load fonts declared in `pubspec.yaml` automatically. Golden tests run against `ObrasPage`, `WorkersPage`, or `NewDeliveryPage` capture images where all text is rendered as solid squares (the "Ahem" placeholder font). The golden files look nothing like the real UI. They pass because the comparison baseline was also generated with Ahem squares — until a font is explicitly loaded, at which point every previously passing test breaks.

**Why it happens:**
Test environments strip asset loading for performance. `pubspec.yaml` declares `uses-material-design: true` and no custom fonts, but Material icons are also assets that must be explicitly loaded. The widget renders structurally correct but visually wrong.

**How to avoid:**
Add a `flutter_test_config.dart` at the test root that loads fonts before any test runs:
```dart
import 'package:flutter_test/flutter_test.dart';
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await loadAppFonts(); // from flutter_test_goldens or equivalent
  await testMain();
}
```
For Material Design icons specifically, use `await tester.runAsync(() => loadFonts())` with the Material symbols font loaded via `FontLoader`. Verify the golden preview actually shows readable text before committing any baseline.

**Warning signs:**
- Golden baseline images show squares/boxes where text should be.
- A baseline was committed without visually reviewing the PNG.
- Adding `flutter_test_goldens` or loading a font causes all existing goldens to fail at once.

**Phase to address:**
Phase 3 (Golden file tests). The font loading setup must be verified in the first golden test before scaling to all three target screens.

---

### Pitfall 7: Stale golden files break CI after any UI change without a clear update workflow

**What goes wrong:**
A developer changes a button color or margin in `ObrasPage`, opens a PR, and CI fails with a golden diff. They don't know how to update the baseline. They either: (a) run `flutter test --update-goldens` on macOS and commit — causing the macOS-vs-Linux failure again, (b) blindly commit PNGs without reviewing the diff — hiding a real regression, or (c) skip the update and leave CI broken for days.

**Why it happens:**
There is no documented golden update procedure. Golden update is not part of the PR workflow. Binary PNG files in git are hard to review in PRs.

**How to avoid:**
Document the update procedure explicitly in `test/golden/README.md` (or inline in the test file):
1. Push branch with UI change.
2. CI golden job fails and uploads a diff artifact.
3. Reviewer downloads the artifact and approves visually.
4. Developer runs the CI golden job with `--update-goldens` flag (via a manual workflow dispatch or by re-running with a special env var).
5. Updated PNGs are committed and pushed.

Add `test/golden/` to `.gitattributes` with `*.png binary` to prevent spurious text diffs and merge conflicts on binary files.

**Warning signs:**
- `git diff` shows golden PNG changes as unreadable binary diffs.
- A PR changes goldens without a linked UI change — this is a silent regression risk.
- The CI golden job has been red for multiple commits without anyone updating the baseline.

**Phase to address:**
Phase 3 (Golden file tests). Define the update workflow and `.gitattributes` entry as part of the initial golden test setup.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Skip `setUpTestHive`/`tearDownTestHive` in load tests | Faster to write | Tests pollute each other; order-dependent failures | Never |
| Use production Supabase project for Edge Function tests without `DRY_RUN` guard | No local setup needed | Real emails sent to real users on every CI run | Never |
| Generate goldens on macOS and commit directly | No Docker/CI setup needed | Every CI run fails; false positive cadence destroys trust in the suite | Never |
| Use `fakeAsync` to compress time in Hive load tests | Simpler test code | Test hangs silently; no failure message, just timeout | Never |
| Commit golden PNGs without reviewing the visual diff | Faster PR turnaround | Silent regressions; baseline drifts from real UI | Never |
| Test entire screens in goldens instead of isolated widgets | Less test code | Goldens break on any screen-level change, not just the widget under test | Only for smoke tests; prefer isolated widgets |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Hive + load tests | Call `OfflineQueueService.init()` without `setUpTestHive` first | Always wrap with `setUpTestHive`/`tearDownTestHive` from `package:hive_test` |
| Hive + concurrent test files | Run `flutter test` with default concurrency on multiple files that share the same box name | Use `--concurrency=1` for Hive test files or use unique box names per file |
| Resend API + Edge Function tests | Invoke the function with live `RESEND_API_KEY` in CI | Mock `globalThis.fetch` in Deno unit tests; add `DRY_RUN` env var guard in the function |
| Supabase real project + Edge Function tests | Insert test data for vencimiento scenarios into production DB | Use Deno unit tests with mocked Supabase client, or `supabase start` local stack |
| Flutter golden tests + macOS development | Generate and commit goldens from macOS; validate on `ubuntu-latest` CI | Either always generate goldens on Linux, or use `alchemist` for platform-agnostic rendering |
| Flutter golden tests + custom fonts | Run `matchesGoldenFile` without loading fonts | Load fonts in `flutter_test_config.dart` before any golden test runs |
| Flutter golden tests + git | Commit binary PNGs into the main test directory without workflow docs | Add `*.png binary` to `.gitattributes`; document the update procedure |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Load test enqueues 1000 items synchronously in one test | Test takes 30+ seconds; CI times out at 15 min | Batch enqueues with `Future.wait` and limit to realistic scale (50–100 items) | At ~500+ items with real Hive I/O |
| Edge Function test invokes the function N times in sequence against the real project | Each invocation hits the real DB and Resend API; slow + costly | Unit-test business logic with mocks; one integration smoke test is enough | At any scale if emails are live |
| Golden tests on large screens at `devicePixelRatio: 3.0` | PNG files are 3–5 MB each; git repo grows rapidly; CI artifact upload is slow | Use `devicePixelRatio: 1.0` in test setup for goldens unless the test specifically targets retina rendering | At 10+ golden files |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| `RESEND_API_KEY` in GitHub Actions secrets without `DRY_RUN` guard in the function | Every CI run sends real emails; API key usage may be rate-limited or billed | Add `DRY_RUN` guard to the function; only inject `RESEND_API_KEY` in a deploy-time secret, not a test-time secret |
| `SUPABASE_SERVICE_ROLE_KEY` used for Edge Function tests that mutate data | Test data inserted into the production DB bypasses RLS; may expose other tenants' data if cleanup fails | Use the `anon` key or a test-specific service role with limited table access for Edge Function test invocations |
| Golden test screenshots of real user data in test fixtures | Screenshots committed to git may contain PII from demo/staging data | Use entirely synthetic data in widget test fixtures; no real RUTs, names, or obra names |

---

## "Looks Done But Isn't" Checklist

- [ ] **Load tests:** `setUpTestHive`/`tearDownTestHive` present in every `setUp`/`tearDown` — verify by running tests out of order and confirming counts are correct.
- [ ] **Load tests:** No `fakeAsync` wrapping Hive operations — verify by checking the test file for `import 'package:fake_async/fake_async.dart'` combined with `enqueue`/`listPending` calls.
- [ ] **Edge Function tests:** `DRY_RUN` guard added to `notif-vencimiento/index.ts` and the guard is tested (test confirms no `fetch` call when `DRY_RUN=true`).
- [ ] **Edge Function tests:** `globalThis.fetch` is stubbed in Deno unit tests — verify by running tests without network access and confirming they pass.
- [ ] **Golden tests:** Font loading configured in `flutter_test_config.dart` — verify by opening one baseline PNG and confirming text is readable (not squares).
- [ ] **Golden tests:** Goldens generated on Linux, not macOS — verify by checking git blame on the PNG files or by re-running `flutter test --update-goldens` on CI and confirming no diff.
- [ ] **Golden tests:** `.gitattributes` entry for `*.png binary` exists — verify with `git diff test/golden/` after a golden update shows binary diff, not text.
- [ ] **Golden tests:** Update procedure documented — verify a team member can explain how to update a baseline after a legitimate UI change without causing a macOS/Linux regression.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Hive state pollution discovered after 20 load tests written | MEDIUM | Add `setUpTestHive`/`tearDownTestHive` to all groups; re-run full suite to find count-dependent tests that need adjustment |
| Real emails sent during CI run | LOW (one-time embarrassment) | Add `DRY_RUN` guard immediately; notify affected users it was a test; revoke and rotate `RESEND_API_KEY` if exposed in logs |
| Golden files committed from macOS, CI always red | MEDIUM | Delete all golden PNGs; re-run `flutter test --update-goldens` on Linux (via CI or Docker); recommit; add platform enforcement note |
| Stale goldens blocking main branch for a week | HIGH | Temporarily disable the golden job in CI; update goldens on Linux; re-enable; add the update workflow to prevent recurrence |
| `fakeAsync` hang discovered in CI | LOW | Remove `fakeAsync` wrapper; replace timestamp control with explicit `nextRetryAt` string construction |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Hive state pollution between load tests | Phase 1 — Load tests | Run `flutter test test/unit/offline_queue_load_test.dart` twice in sequence; both runs pass with correct counts |
| `fakeAsync` + Hive I/O hang | Phase 1 — Load tests | CI completes Phase 1 tests in under 30 seconds total |
| Real Resend emails during tests | Phase 2 — Edge Function tests | Run Edge Function test suite with `RESEND_API_KEY` set; confirm no email received; confirm mock was called |
| Production data contamination via Edge Function | Phase 2 — Edge Function tests | Production DB shows no new test rows after CI run; no `get_vencimientos_proximos` RPC called against prod |
| macOS-vs-Linux golden failure | Phase 3 — Golden tests | CI golden job passes on first push without any local update-goldens run |
| Fonts rendering as Ahem squares | Phase 3 — Golden tests | Baseline PNGs visually reviewed and contain readable text |
| Stale goldens breaking CI after UI changes | Phase 3 — Golden tests | PR with intentional button color change shows clear diff artifact and has documented update path |

---

## Sources

- Flutter golden test CI failures: https://medium.com/@m1nori/flutter-golden-tests-fail-in-github-actions-why-and-how-to-fix-65e3b69ee86e
- Golden test common mistakes: https://leancode.co/glossary/golden-tests-in-flutter
- Hive box already open issue: https://github.com/isar/hive/issues/544
- Hive concurrent isolate access: https://github.com/isar/hive/issues/77
- fakeAsync + real async operations: https://medium.com/flutter/understanding-async-in-flutter-tests-a304a7604b3c
- Flutter test concurrency issues: https://github.com/flutter/flutter/issues/168268
- Supabase Edge Function testing: https://supabase.com/docs/guides/functions/unit-test
- Deno mock fetch: https://deno.land/x/mock_fetch@0.3.0
- Deno stub API: https://docs.deno.com/examples/mocking_tutorial/
- Golden test font loading: https://gist.github.com/davidsdearaujo/89c2fa21be68c98f6983fb897d5cc2f5
- Non-deterministic golden generation: https://github.com/flutter/flutter/issues/92590
- flutter_test concurrency flag: https://github.com/flutter/flutter/issues/125940
- Codebase inspection: `lib/services/offline_queue_service.dart`, `supabase/functions/notif-vencimiento/index.ts`, `test/unit/offline_queue_test.dart`, `.github/workflows/test.yml`

---
*Pitfalls research for: Advanced testing on Flutter/Supabase — load tests, Edge Function tests, golden file tests*
*Researched: 2026-06-13*

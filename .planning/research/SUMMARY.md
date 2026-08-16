# Project Research Summary

**Project:** TrazApp v2.0 — Advanced Testing Suite
**Domain:** Flutter/Supabase QA — load/stress tests, Edge Function tests, golden file tests
**Researched:** 2026-06-13
**Confidence:** HIGH

## Executive Summary

TrazApp v2.0 adds three distinct test layers on top of an existing foundation of 50 unit tests, 14 integration tests, and 3 E2E tests running in GitHub Actions on `ubuntu-latest`. The three new layers are structurally independent and each demands a different toolchain: Hive load/stress tests (pure Dart, no new dependencies), Deno Edge Function tests (TypeScript, separate CI job), and Flutter golden file tests (requires `alchemist`, Linux-only baseline generation). The recommended approach is to implement them in that exact order — load tests first (zero friction), Edge Function tests second (isolated Deno toolchain), golden tests third (highest setup cost).

The primary risks are not correctness bugs but infrastructure choices that, if made wrong, create permanently broken CI. The two most dangerous decisions are (1) generating golden files on macOS and validating on Linux CI (guaranteed failure due to font rendering differences), and (2) allowing Edge Function tests to reach the real Resend API or real Supabase project (real emails sent to real users on every CI run). Both of these pitfalls have zero recovery value — they must be prevented upfront, not fixed reactively.

The overall architecture is additive: all three test types extend existing infrastructure without modifying production code, with two minor exceptions — `notif-vencimiento/index.ts` needs a `DRY_RUN` env var guard before any Edge Function test is written, and the three target page widgets (`ObrasPage`, `WorkersPage`, `NewDeliveryPage`) need test-friendly constructor variants before golden tests can render them with deterministic fake data.

---

## Key Findings

### Recommended Stack

The existing `pubspec.yaml` already covers Hive stress tests with `hive_test ^1.0.1` and `flutter_test` (SDK). No new packages are required for load tests. For golden tests, `alchemist ^0.14.0` is recommended over raw `matchesGoldenFile` — it provides CI/local dual-mode rendering that solves the macOS-vs-Linux font drift problem automatically by obscuring text in CI mode. For mocking services in golden tests, `mocktail ^1.0.5` is preferred over `mockito` because it requires zero code generation. For Deno tests, all dependencies are declared inline via JSR imports and require no `pubspec.yaml` changes.

**Core technologies:**
- `alchemist ^0.14.0`: Golden test runner — solves macOS/Linux CI font drift via `CiGoldensConfig(obscureText: true)`; replaces discontinued `golden_toolkit`
- `mocktail ^1.0.5`: Service mocking in golden tests — zero-codegen, null-safe, no `build_runner`
- `network_image_mock ^2.1.1`: Blocks `NetworkImage` in widget tests — prevents test failures on worker photo URLs
- `fake_async ^1.3.2`: Advances simulated time in Hive stress tests — avoids wall-clock waits for backoff timer tests (already a transitive dep, needs explicit declaration)
- `jsr:@std/assert@^1.0.0` + `jsr:@std/testing@^1.0.0/mock`: Deno assertion and stub library — official Deno stdlib, no third-party dependencies

### Expected Features

**Must have (table stakes — v2.0 launch):**
- Load: high-volume enqueue (N=200) with full recovery via `listAll()` — validates queue integrity at realistic scale
- Load: `Future.wait()` concurrent burst (20 simultaneous enqueues) — simulates rapid tap-happy usage
- Load: mixed-status `listPending()` at volume (100 items across all states) — validates the critical filter path
- Edge: `buildEmailHtml()` pure function test — catches HTML regression with no mocking
- Edge: CRITICO vs AVISO subject line logic — pure function test, no I/O
- Edge: Resend fetch call structure test (stub `globalThis.fetch`) — verifies external API contract
- Edge: Resend failure handling (stub returns non-ok) — verifies resilience of daily notification job
- Golden: `ObrasPage` loading state + data-loaded state (offline mode, pre-populated Hive)
- Golden: `WorkersPage` with workers list
- Golden: `NewDeliveryPage` initial render

**Should have (v2.x):**
- Edge: multi-org email grouping test (2 orgs → 2 Resend calls)
- Edge: full `supabase functions invoke` smoke test (when Deno CI is stable)
- Golden: `NewDeliveryPage` traffic light states (OK/WARNING/BLOQUEO snapshots)
- Golden: offline mode indicator visible in `ObrasPage`/`WorkersPage`

**Defer (v3+):**
- Golden: dark mode snapshots (only relevant when dark theme is added)
- Golden: tablet/large screen layouts (only relevant when iPad support is targeted)
- Load: N=500 backoff DateTime precision micro-benchmark
- Edge: pg_cron trigger path testing (infrastructure, not app logic)

### Architecture Approach

The v2.0 test architecture is a strict additive overlay on the existing `test/` tree. No existing test files are modified. Three new directories are created: `test/stress/` (Hive stress tests, tagged `@Tags(['stress'])`), `test/golden/` (Flutter golden tests, tagged `@Tags(['golden'])`), and `supabase/functions/tests/` (Deno tests, entirely separate from Flutter toolchain). The CI pipeline gains three new steps appended after the existing jobs: a `flutter test test/stress/` step, a `deno test supabase/functions/tests/` step (with `denoland/setup-deno` action), and a `flutter test test/golden/` step.

**Major components:**
1. `test/stress/offline_queue_stress_test.dart` — Hive volume tests using the same `setUpTestHive`/`tearDownTestHive` pattern as existing unit tests; no new dependencies
2. `supabase/functions/tests/notif-vencimiento-test.ts` — Deno unit tests using JSR stdlib stubs; tests pure-function extractions of the Edge Function business logic
3. `test/golden/` + `test/golden/helpers/golden_test_helpers.dart` — Flutter golden tests using `alchemist` for CI-safe rendering; page widgets need test-friendly constructors
4. `.github/workflows/test.yml` (modified) — appends three new test steps; existing jobs unchanged

### Critical Pitfalls

1. **Hive state pollution between load tests** — Every test group must call `setUpTestHive()`/`tearDownTestHive()` from `package:hive_test`. Calling `OfflineQueueService.init()` when the box is already open silently reuses the existing box; the second test group starts with leftover entries from the first. Prevention: enforce the pattern before writing any load test. Run tests out of order to verify counts.

2. **Real Resend emails sent during CI** — `notif-vencimiento/index.ts` has no test-mode guard. Any invocation with live `RESEND_API_KEY` sends emails to real users. Prevention: add `DRY_RUN` env var guard to the function before writing any test; stub `globalThis.fetch` in all Deno unit tests.

3. **Golden files generated on macOS fail on Linux CI** — CoreText vs. FreeType font rendering differ pixel-by-pixel. Prevention: generate all golden baselines on Linux only; use `alchemist` CI mode (`obscureText: true`) so CI comparisons are platform-agnostic.

4. **Custom fonts render as "Ahem" squares in golden files** — Flutter test environment does not auto-load fonts from `pubspec.yaml`. Prevention: add `flutter_test_config.dart` at `test/` root with `loadAppFonts()` before any golden test runs; visually review every baseline PNG before committing.

5. **`fakeAsync` wrapping Hive I/O causes silent test hangs** — `fakeAsync` controls Dart timers but not Hive's native filesystem I/O; affected futures never resolve. Prevention: use real `async`/`await` for all Hive operations; control `nextRetryAt` via explicit ISO string construction.

---

## Implications for Roadmap

### Phase 1: Hive Load/Stress Tests
**Rationale:** Zero new dependencies — `hive_test` is already present. Directly extends the existing `offline_queue_test.dart` pattern. Fastest path to a CI-visible quality gate. No production code changes required.
**Delivers:** `test/stress/offline_queue_stress_test.dart` with `@Tags(['stress'])` tests; new `flutter test test/stress/` CI step.
**Addresses:** High-volume enqueue recovery, concurrent burst (`Future.wait()`), mixed-status filter at volume, backoff boundary correctness.
**Avoids:** Hive state pollution (Pitfall 1), `fakeAsync` hang (Pitfall 2).

### Phase 2: Deno Edge Function Tests
**Rationale:** Self-contained — entirely separate from Dart/Flutter toolchain. Requires one pre-work item (add `DRY_RUN` guard to `notif-vencimiento/index.ts`) and one CI addition (`denoland/setup-deno` action). No Supabase secrets needed for unit tests.
**Delivers:** `supabase/functions/tests/notif-vencimiento-test.ts`; new Deno CI job; `DRY_RUN` guard in the Edge Function; pure-function extractions for business logic.
**Uses:** `jsr:@std/assert@^1.0.0`, `jsr:@std/testing@^1.0.0/mock` (inline Deno imports, no pubspec changes).
**Avoids:** Real Resend emails during CI (Pitfall 3), production data contamination (Pitfall 4).

### Phase 3: Flutter Golden File Tests
**Rationale:** Highest setup cost — requires `alchemist` package, `flutter_test_config.dart` with font loading, test-friendly constructors on three pages, Linux-only baseline generation, `.gitattributes` entry, and a documented update workflow. Implemented last to avoid blocking Phases 1 and 2.
**Delivers:** `test/golden/` directory with goldens for `ObrasPage`, `WorkersPage`, `NewDeliveryPage`; `test/golden/helpers/golden_test_helpers.dart`; committed Linux-generated PNG baselines; golden update workflow documentation.
**Uses:** `alchemist ^0.14.0`, `mocktail ^1.0.5`, `network_image_mock ^2.1.1`, `fake_async ^1.3.2` (new dev dependencies).
**Avoids:** macOS-vs-Linux rendering failure (Pitfall 5), Ahem squares (Pitfall 6), stale goldens blocking CI (Pitfall 7).

### Phase Ordering Rationale

- Phase 1 before Phase 2: Load tests have zero new infrastructure cost; completing them first proves the "extend existing tests" pattern before crossing toolchain boundaries to Deno.
- Phase 2 before Phase 3: Edge Function tests are self-contained and shippable independently. Golden tests require widget refactors that could distract from Phase 2 completeness.
- Phase 3 last: The CI expansion experience from Phase 2 builds confidence before adding the heavier golden infrastructure.
- All three phases are technically independent but this ordering minimizes CI complexity debt at each step.

### Research Flags

Phases needing focused codebase inspection before task planning:
- **Phase 2:** The exact extraction boundaries in `notif-vencimiento/index.ts` (which logic to extract as pure functions) require reading the current file before writing tasks.
- **Phase 3:** The minimal widget refactor needed for `ObrasPage`, `WorkersPage`, `NewDeliveryPage` to support test-friendly constructors requires inspecting those files before writing tasks.

Phases with well-documented patterns (skip research-phase):
- **Phase 1:** All patterns are already demonstrated in `test/unit/offline_queue_test.dart`. This is a volume/scale extension of existing code. No new concepts.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All package versions verified on pub.dev; Deno imports verified via official Supabase and Deno stdlib docs |
| Features | HIGH (load + golden) / MEDIUM (Edge) | Load and golden scope well-established; Edge Function test scope has known Deno mocking friction for the Supabase client path |
| Architecture | HIGH | Confirmed against official Supabase Edge Function test conventions; Flutter golden patterns verified across multiple primary sources; Hive constraints confirmed via GitHub issues |
| Pitfalls | HIGH | All pitfalls verified via official docs, GitHub issues, and codebase inspection of actual project files |

**Overall confidence:** HIGH

### Gaps to Address

- **Edge Function: Supabase client mocking boundary** — The exact refactor needed in `notif-vencimiento/index.ts` is unknown until the file is inspected. Approach is clear (extract pure functions); scope is not.
- **Golden tests: page widget refactor scope** — Whether a test-friendly constructor can be added non-destructively to `ObrasPage`/`WorkersPage`/`NewDeliveryPage` needs codebase inspection before Phase 3 task writing.
- **CI golden update workflow decision** — The update procedure (Linux-only baseline generation) needs a decision on Docker vs. CI manual dispatch vs. separate `goldens.yml` workflow. Process decision, not technical.

---

## Sources

### Primary (HIGH confidence)
- https://pub.dev/packages/alchemist — version 0.14.0 confirmed, publisher betterment.dev
- https://pub.dev/packages/mocktail — version 1.0.5, publisher felangel.dev
- https://supabase.com/docs/guides/functions/unit-test — official Deno test file structure and JSR imports
- https://docs.deno.com/examples/stubbing_tutorial/ — `stub()` from `jsr:@std/testing/mock`
- https://api.flutter.dev/flutter/flutter_test/matchesGoldenFile.html — official golden file matcher
- https://github.com/Betterment/alchemist — CI mode documentation
- https://github.com/isar/hive/issues/544 — Hive box already-open behavior confirmed
- https://github.com/isar/hive/issues/77 — Hive multi-isolate access constraints confirmed
- https://dart.dev/language/concurrency — Dart single-threaded event loop confirmation

### Secondary (MEDIUM confidence)
- https://verygood.ventures/blog/alchemist-golden-tests-tutorial/ — Alchemist CI/local dual-mode
- https://leancode.co/glossary/golden-tests-in-flutter — golden test best practices
- https://medium.com/@m1nori/flutter-golden-tests-fail-in-github-actions-why-and-how-to-fix-65e3b69ee86e — macOS/Linux rendering mismatch
- https://medium.com/flutter/understanding-async-in-flutter-tests-a304a7604b3c — `fakeAsync` limitations with real I/O

### Tertiary (LOW confidence)
- Codebase inspection: `lib/services/offline_queue_service.dart`, `supabase/functions/notif-vencimiento/index.ts`, `test/unit/offline_queue_test.dart`, `.github/workflows/test.yml` — confirmed existing infrastructure state

---
*Research completed: 2026-06-13*
*Ready for roadmap: yes*

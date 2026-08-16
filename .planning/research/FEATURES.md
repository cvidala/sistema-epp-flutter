# Feature Research

**Domain:** Advanced testing suite for Flutter + Supabase app (v2.0 milestone)
**Researched:** 2026-06-13
**Confidence:** HIGH (golden tests, Hive load tests) / MEDIUM (Edge Function tests — Deno mocking has known friction)

---

## Domain Context

Three distinct test types, each with different mechanics, toolchains, and failure modes. Existing infrastructure: 50 unit tests + 14 Supabase integration tests + 3 E2E service tests + GitHub Actions CI on `ubuntu-latest`. The new types build on top of this foundation.

---

## Test Type 1: Load/Stress Tests — Hive Offline Queue

### What These Tests Verify

Hive's `OfflineQueueService` stores EPP deliveries as JSON strings in a `Box<String>` keyed by `localEventId`. The existing unit tests cover correctness (state transitions, backoff filter, sort order) but only one item at a time. Load tests answer: "does the queue remain consistent and performant under realistic volume and concurrent write pressure?"

The queue is Flutter-single-threaded (Dart event loop), so "concurrent" means rapid sequential `await` calls interleaved via `Future.wait`. True multi-isolate concurrency is possible but unlikely in normal app usage. Both scenarios need coverage.

### Table Stakes (Expected in Any Serious Offline Queue Test Suite)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| High-volume enqueue (N=100-500 items) | Validates Hive box doesn't corrupt under bulk writes | LOW | `hive_test` `setUpTestHive()` already used in unit tests — same pattern |
| All items recoverable after bulk write | `listAll().length == N` after N enqueues | LOW | Direct assertion on `OfflineQueueService.listAll()` |
| `listPending()` filters correctly at volume | SENT/FAILED/future-backoff items excluded from N pending | LOW | Existing filter logic tested at 1 item; must hold at 100+ |
| Chronological sort preserved under load | Insert out-of-order timestamps, verify `listPending()` returns sorted | LOW | Existing `ordena por createdAtClientIso` test at 2 items |
| No data loss on rapid sequential writes | No Hive key collisions, no JSON truncation | LOW | UUID v4 keys make collision impossible; test anyway |
| State machine transitions at volume | Bulk `markSent()` + `markFailed()` on N items, verify final states | MEDIUM | Tests `update()` under repeated writes |

### Differentiators (Valuable but Not Assumed)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| `Future.wait()` concurrent write burst | Simulates multiple rapid taps on "save delivery" before first sync | MEDIUM | 10-50 simultaneous `enqueue()` calls; verify no lost/duplicate entries |
| Backoff timing precision at volume | 50 items all with `nextRetryAt` set to now±1s; verify listPending boundary | MEDIUM | Exposes off-by-one in DateTime.now() comparison |
| Memory footprint measurement | Track `listAll().length` vs estimated JSON byte size at N=500 | LOW | `jsonEncode(e.toMap())` size per item is predictable (~500 bytes) |
| `markSent()` idempotency under repeat calls | Calling markSent twice on same ID does not corrupt state | LOW | Edge case in sync retry logic |
| Mixed-status bulk scenario | 200 items: 50 PENDING, 50 ERROR-backoff-expired, 50 ERROR-backoff-active, 50 SENT — verify listPending returns exactly 100 | MEDIUM | Most realistic stress scenario |

### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Real Supabase sync under load | "Test the full pipeline" | Makes load tests slow, fragile, and network-dependent; defeats the isolation goal | Keep load tests pure Hive; the E2E tests cover sync correctness |
| N=10,000+ items | "Be thorough" | Hive on mobile is not designed as a bulk database; the queue never exceeds ~50 items in production; testing 10k creates a false performance requirement | Test at N=500 (10x realistic maximum); that's the meaningful boundary |
| Benchmark timing assertions | "Ensure it's fast enough" | Flaky on CI — `ubuntu-latest` runners have variable performance | Assert correctness only; add a warning log if operation exceeds a threshold, do not fail the test on duration |
| Multi-isolate concurrency | "Real production scenario" | The Flutter app uses a single isolate; Hive 2.x has known multi-isolate caveats; testing something that doesn't happen in production adds complexity without value | Test rapid sequential `Future.wait()` instead |

### Dependencies on Existing Infrastructure

- `hive_test` 1.0.1 already in `dev_dependencies` — `setUpTestHive()` / `tearDownTestHive()` available
- `OfflineQueueService.init()` already called in `setUp()` in existing tests — same pattern extends to load tests
- No additional packages required
- Tests run in `flutter test test/unit/` — same CI job, no new workflow needed

---

## Test Type 2: Edge Function Tests — `notif-vencimiento`

### What These Tests Verify

The function: queries `get_vencimientos_proximos` RPC, groups results by org, fetches `perfiles` with `recibe_notif_venc=true`, calls Resend API at `https://api.resend.com/emails`, returns `200` with a summary string. Tests must cover: RPC data handling, email grouping logic, subject line construction (CRITICO vs AVISO), Resend call structure, and date boundary conditions.

**Critical insight from research:** The function is tightly coupled — `Deno.serve` handler directly calls `createClient`, `rpc`, `from`, and `fetch` inline. Mocking requires either (a) extracting logic into testable pure functions, or (b) using Deno's `stub()` from `@std/testing/mock` on the `globalThis.fetch`. Option (b) is feasible for the Resend call. The Supabase RPC calls require a real Supabase connection or careful module-level injection.

**Recommended approach:** Two-track strategy — pure unit tests for business logic extracted into helper functions (`buildEmailHtml`, date classification, subject construction), plus integration tests against real Supabase for the full invocation path.

### Table Stakes (Expected in Any Edge Function Test Suite)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| `buildEmailHtml()` output contains expected fields | The function already exports this helper; verify EPP name, worker RUT, dias_restantes appear in HTML | LOW | Pure function, no mocking needed |
| Subject line: CRITICO path | `criticos.length > 0` → subject starts with `🔴` and contains `dias_restantes` of first item | LOW | Pure logic, no I/O |
| Subject line: AVISO-only path | `criticos.length == 0, avisos.length > 0` → subject starts with `⚠️` | LOW | Pure logic |
| Empty vencimientos → 200 "Sin vencimientos" | RPC returns `[]` → function returns early with 200 | MEDIUM | Requires real Supabase or mocked RPC; confirms early-exit path |
| Resend API call structure | POST body contains `from`, `to` (array), `subject`, `html` fields | MEDIUM | Stub `globalThis.fetch` with `@std/testing/mock`; verify call args |
| Resend failure → logged error, function still returns 200 | Non-ok Resend response → `errores` array populated, overall response remains 200 | MEDIUM | Mock fetch to return non-ok; verify response body contains error count |
| `email_notif` validation filters invalid emails | Profiles with null or no-`@` email are excluded from `to` array | LOW | Pure filter logic extractable from function |

### Differentiators (Valuable but Not Assumed)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Date boundary: `dias_restantes = 0` (vence hoy) | The RPC returns `nivel_alerta = 'CRITICO'` for 0 days — verify function handles it without crashing | MEDIUM | Requires constructing fixture Vencimiento object |
| Date boundary: `dias_restantes = 7` vs `8` | 7 → CRITICO, 8 → AVISO (the clasificación is done in the RPC, not the function; but the function trusts this) | LOW | Document the assumption; test that the function correctly handles both nivel_alerta values |
| Multi-org email grouping | 3 vencimientos from 2 different org_ids → 2 separate Resend calls, not 1 combined | HIGH | Requires mocking or real data with multiple orgs |
| `formatFecha()` correctness for Chilean locale | `es-CL` date format — verify output contains expected format for ISO boundary dates | LOW | Pure function, easy to unit test |
| Full invocation via `supabase functions invoke` | End-to-end call against the deployed function with test data | HIGH | Requires Supabase CLI, local serve, or deployed function; slow CI |
| No recipients for an org → skips Resend call | `recibe_notif_venc=false` for all profiles in org → no email sent | MEDIUM | Tests the `continue` guard in the loop |

### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Actually sending Resend emails in tests | "Verify delivery" | Sends real emails to real or test addresses; hits Resend API rate limits; leaves side effects | Stub `globalThis.fetch` to capture call args without sending; assert on request body |
| Testing the full pg_cron trigger path | "Verify scheduling" | pg_cron is Supabase infrastructure, not app logic; cannot be unit-tested | Verify cron SQL config exists in migration; document expected schedule |
| Mocking Supabase client internals | "Avoid hitting real DB" | Supabase `createClient` + RLS stubs diverge from production; this project already decided against mocks for Supabase (see PROJECT.md Key Decisions) | Use real Supabase for integration path; extract pure functions for unit path |

### Dependencies on Existing Infrastructure

- Deno runtime required (not present in current Flutter CI job)
- Tests live in `supabase/functions/tests/notif-vencimiento-test.ts` (Deno convention)
- Run with: `deno test --allow-all supabase/functions/tests/notif-vencimiento-test.ts`
- `@std/testing/mock` from JSR for stub/spy (Deno standard library)
- New CI job required: `deno_tests` on `ubuntu-latest` with Deno setup step — isolated from Flutter job
- Existing Supabase secrets (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`) reusable for integration path
- `RESEND_API_KEY` secret needed in CI if testing non-mocked path (avoid this — use stub instead)

---

## Test Type 3: Flutter Golden File / Visual Snapshot Tests

### What These Tests Verify

Golden tests render a widget to a pixel buffer and compare against a stored reference PNG. They catch: layout regressions (widget moved/resized), color/theme changes, text truncation, missing UI states. They do NOT replace unit tests for logic — they only validate visual output.

**Critical insight:** `ObrasPage`, `WorkersPage`, and `NewDeliveryPage` all call Supabase in `initState()`. Golden tests must inject fake/mock data instead of triggering live network calls. This requires either wrapping with a fake `SupabaseClient` or restructuring the test to pump the widget in a state where network calls don't fire (e.g., offline mode, or mocking services).

For TrazApp's architecture (StatefulWidget + direct `Supabase.instance.client`), the practical approach is: test the loading skeleton state (before async completes) or inject test data via constructor parameters where possible. `ObrasPage(modoOffline: true)` with pre-populated `OfflineCacheService` data is the cleanest test path for ObrasPage.

**Platform CI issue:** Current CI runs on `ubuntu-latest`. Golden files generated on macOS will differ from Linux due to font rendering. **Alchemist** (`@betterment/alchemist`) solves this via `CiGoldensConfig(obscureText: true)` which replaces text with colored blocks — makes CI goldens platform-independent.

### Table Stakes (Expected in Any Golden Test Suite)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| One golden per critical screen | ObrasPage, WorkersPage, NewDeliveryPage each have at least 1 golden | LOW | The base requirement |
| Loading state snapshot | The `loading=true` skeleton/spinner is captured | LOW | Pump widget, don't pumpAndSettle — catches the async load start |
| Data-loaded state snapshot | Populated list of obras/workers/EPP items rendered | MEDIUM | Requires injecting fake data; offline mode + pre-populated Hive cache |
| Empty state snapshot | Zero obras, zero workers — the empty list/message UI | LOW | Easy via empty list injection |
| Error state snapshot | `error != null` shown on screen | LOW | Requires triggering error path, or setting state directly |
| Deterministic test data | Fixed strings, no DateTime.now(), no network images | LOW | Replace `supabase_flutter` calls with Hive cache reads in modoOffline |
| `--update-goldens` workflow documented | Team knows how to regenerate goldens after intentional UI changes | LOW | One command, but must be in CI README |

### Differentiators (Valuable but Not Assumed)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Multiple device sizes (phone vs tablet) | Catches layout breaks on larger screens; NewDeliveryPage scrolls | MEDIUM | `setSurfaceSize()` per scenario; or Alchemist `constraints` |
| Dark mode snapshot | TrazApp uses Material3 — verify dark theme renders correctly | MEDIUM | Inject `ThemeData.dark()` via Alchemist `AlchemistConfig(theme: ...)` |
| Offline mode indicator visible | `modoOffline=true` banner or icon appears in ObrasPage/WorkersPage | LOW | High value: catches accidental removal of offline indicator |
| Traffic light states (OK/WARNING/BLOQUEO) in NewDeliveryPage | The `EvaluacionEntrega` semaphore colors are critical UX | MEDIUM | Requires injecting `EvaluacionEntrega` with each status value |
| Pending queue count badge visible in WorkersPage | Shows N items in offline queue | MEDIUM | Requires pre-populating OfflineQueueService |
| Alchemist CI + platform split | CI goldens use obscured text (platform-safe); dev goldens use real fonts | MEDIUM | Solves the macOS/Linux CI rendering mismatch definitively |

### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Full screen end-to-end golden (all 3 pages in sequence) | "Test the whole flow visually" | Full E2E golden tests are extremely brittle; any widget change anywhere breaks them | One focused golden per screen state; keep scope narrow |
| Golden test for every widget in the app | "Complete visual coverage" | Maintenance burden grows faster than value; updating goldens after any theme change becomes a chore | Focus on screens where regressions are costly: the 3 delivery flow screens |
| Pixel-perfect matching on CI without tolerance | "Catch every change" | Text anti-aliasing creates unavoidable 0.1-0.5% pixel differences across CI runners | Use `CiGoldensConfig(diffThreshold: 0.005)` or Alchemist obscureText for CI |
| Testing animated states | "Verify loading animation looks right" | `pumpAndSettle` timeouts; animations are non-deterministic in test | Use `pumpOnce` (Alchemist) for animated states; test start/end frames only |
| Running goldens on `ubuntu-latest` without Alchemist | "Keep CI simple" | Font rendering on Linux differs from macOS dev machine; tests fail spuriously | Either use Alchemist obscureText CI mode OR add a dedicated `macos-latest` golden job |

### Dependencies on Existing Infrastructure

- `alchemist` package required (not currently in `pubspec.yaml`) — add to `dev_dependencies`
- Existing `widget_test.dart` uses `testWidgets` with `MaterialApp(home: LoginPage())` — same scaffold applies
- `OfflineCacheService` must be pre-populated in `setUp()` for ObrasPage golden (Hive already available via `hive_test`)
- `flutter_test_config.dart` needed at `test/` root for global `AlchemistConfig` (CI environment detection)
- New CI job or step needed: golden tests separated from unit tests (tag `@Tags(['golden'])`) — either on `macos-latest` (platform goldens) or keep on `ubuntu-latest` with Alchemist CI mode (recommended for simplicity)
- Generated golden PNG files committed to `test/goldens/` in git — expect initial PR of ~10-30 PNG files

---

## Feature Dependencies

```
[Load/Stress Tests — Hive]
    └── requires ──> [hive_test setUpTestHive() pattern]  (already in place)
    └── requires ──> [OfflineQueueService.init() in setUp()]  (already in place)

[Edge Function Tests — notif-vencimiento]
    └── requires ──> [Deno runtime in CI]  (new — Deno setup action needed)
    └── requires ──> [extracted pure functions from index.ts]  (refactor needed for unit path)
    └── optional ──> [real Supabase secrets for integration path]  (already in CI secrets)

[Golden File Tests — Flutter]
    └── requires ──> [alchemist package in dev_dependencies]  (new)
    └── requires ──> [flutter_test_config.dart with AlchemistConfig]  (new)
    └── requires ──> [OfflineCacheService Hive pre-population in setUp()]  (extends existing hive_test pattern)
    └── requires ──> [golden PNG files committed to git]  (new files, first PR)

[Edge Function Tests] ──independent──> [Load/Stress Tests]
[Edge Function Tests] ──independent──> [Golden File Tests]
[Load/Stress Tests] ──independent──> [Golden File Tests]
```

### Dependency Notes

- **Golden tests require Alchemist:** The alternative (raw `matchesGoldenFile` with custom comparator) is more code for the same outcome. Alchemist is maintained by Betterment, has 175+ code snippets in Context7, and is the de-facto standard for CI-safe Flutter goldens.
- **Edge Function tests require function refactoring:** `buildEmailHtml` is already exported. The subject-line and email-filter logic should be extracted into pure functions to enable unit testing without mocking Supabase.
- **Load tests have zero new dependencies:** Everything needed (`hive_test`, `OfflineQueueService`) already exists. This is the lowest-friction item in the milestone.

---

## MVP Definition for v2.0

### Launch With (v2.0)

Minimum coverage to close the milestone with meaningful quality gates.

- [ ] **Load: high-volume enqueue + full recovery** — N=200 items enqueued, `listAll().length == 200`, `listPending()` returns correct subset
- [ ] **Load: Future.wait() concurrent burst** — 20 simultaneous enqueues, no data loss
- [ ] **Load: mixed-status listPending at volume** — 100 items across all states, verify filter correctness
- [ ] **Edge: `buildEmailHtml()` contains required fields** — pure function test, no mocking
- [ ] **Edge: subject line CRITICO vs AVISO logic** — pure function test
- [ ] **Edge: Resend fetch call structure** — stub globalThis.fetch, verify POST body
- [ ] **Edge: Resend failure handling** — stub returns non-ok, verify function returns 200 with error count
- [ ] **Golden: ObrasPage loading state** — spinner/skeleton visible
- [ ] **Golden: ObrasPage with obras list (modoOffline=true)** — populated list
- [ ] **Golden: WorkersPage with workers list** — populated list
- [ ] **Golden: NewDeliveryPage initial render** — form with EPP items visible

### Add After Validation (v2.x)

- [ ] **Edge: multi-org grouping** — 2 orgs → 2 Resend calls (requires test data setup)
- [ ] **Edge: full `supabase functions invoke` integration test** — slow, add when Deno CI is stable
- [ ] **Golden: NewDeliveryPage traffic light states** — OK/WARNING/BLOQUEO snapshots
- [ ] **Golden: dark mode** — if dark theme is added to TrazApp

### Future Consideration (v3+)

- [ ] **Load: N=500 backoff precision** — micro-benchmark of DateTime boundary
- [ ] **Golden: tablet/large screen layouts** — only relevant if iPad support is added

---

## Feature Prioritization Matrix

| Feature | Developer Value | Implementation Cost | Priority |
|---------|----------------|---------------------|----------|
| Load: high-volume enqueue/recovery | HIGH — validates queue integrity at realistic scale | LOW — same hive_test pattern | P1 |
| Load: concurrent burst | HIGH — simulates real tap-happy usage | MEDIUM — Future.wait() + assertion | P1 |
| Load: mixed-status filter at volume | HIGH — the listPending() filter is critical path | MEDIUM | P1 |
| Edge: buildEmailHtml pure unit test | MEDIUM — catches HTML regression | LOW — no mocking | P1 |
| Edge: subject line logic | MEDIUM — CRITICO/AVISO wording is compliance-visible | LOW | P1 |
| Edge: Resend stub + call structure | HIGH — verifies external API contract | MEDIUM — Deno stub setup | P1 |
| Edge: Resend failure handling | HIGH — resilience of daily notification job | MEDIUM | P1 |
| Golden: ObrasPage + WorkersPage states | HIGH — layout regressions in main flow caught | MEDIUM — Alchemist + Hive data injection | P1 |
| Golden: NewDeliveryPage initial render | HIGH — most complex screen, most regression risk | MEDIUM — Supabase mocking challenge | P1 |
| Edge: multi-org grouping test | MEDIUM | HIGH — test data complexity | P2 |
| Golden: traffic light states | MEDIUM — visual compliance indicator | MEDIUM | P2 |
| Golden: tablet sizes | LOW — not a current target platform | LOW | P3 |

---

## Sources

- [Testing Supabase Edge Functions | Supabase Docs](https://supabase.com/docs/guides/functions/unit-test)
- [Deno Mocking and Test Doubles](https://docs.deno.com/examples/mocking_tutorial)
- [Alchemist — Context7 docs](/betterment/alchemist)
- [Alchemist — Very Good Ventures tutorial](https://verygood.ventures/blog/alchemist-golden-tests-tutorial/)
- [Golden Tests in Flutter: Common Mistakes, Best Practices | LeanCode](https://leancode.co/glossary/golden-tests-in-flutter)
- [Flutter Golden Tests Fail in GitHub Actions — Fix](https://medium.com/@m1nori/flutter-golden-tests-fail-in-github-actions-why-and-how-to-fix-65e3b69ee86e)
- [Flutter Golden Tests with Tolerance](https://tomasrepcik.dev/blog/2024/2024-09-19-flutter-golden-test-with-tolerance/)
- [Hive docs — isar/hive on Context7](/isar/hive)
- [Errors with mocking in Supabase Edge Functions on Deno](https://questions.deno.com/m/1204083275073593394)

---

*Feature research for: TrazApp v2.0 — advanced testing (load/stress, Edge Functions, golden file tests)*
*Researched: 2026-06-13*

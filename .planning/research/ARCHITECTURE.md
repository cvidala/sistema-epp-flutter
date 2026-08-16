# Architecture Research

**Domain:** Advanced test types integration — Flutter/Supabase QA system (v2.0)
**Researched:** 2026-06-13
**Confidence:** HIGH

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    EXISTING TEST INFRASTRUCTURE                  │
├──────────────┬──────────────────┬──────────────────────────────┤
│  test/unit/  │ test/integration/│    integration_test/          │
│  (50 tests)  │ (14 tests)       │    (E2E, macOS device)        │
│  hive_test   │ supabase/ + e2e/ │                               │
│  no network  │ requires .env    │                               │
└──────────────┴──────────────────┴──────────────────────────────┘
          ↑ v2.0 adds 3 new test slices below ↑

┌──────────────────────────────────────────────────────────────────┐
│                    V2.0 TEST LAYERS (NEW)                         │
├──────────────────┬──────────────────┬────────────────────────────┤
│  test/stress/    │  supabase/        │  test/golden/              │
│  offline_queue_  │  functions/tests/ │  (golden files +           │
│  stress_test.dart│  notif_vencimiento│   test_helpers/)           │
│  (Dart, no net)  │  _test.ts (Deno)  │   (Flutter, Linux CI)     │
│  hive_test box   │  deno test runner │   matchesGoldenFile        │
└──────────────────┴──────────────────┴────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Existing or New |
|-----------|----------------|-----------------|
| `test/unit/offline_queue_test.dart` | State machine, backoff filter, serialization | Existing (50 tests) |
| `test/stress/offline_queue_stress_test.dart` | High-volume enqueue, concurrent access simulation, backoff-under-load | **NEW** |
| `supabase/functions/tests/notif-vencimiento-test.ts` | Deno unit tests: RPC mock, Resend mock, date boundary cases | **NEW** |
| `test/golden/` + `test/golden/helpers/` | Golden file tests for ObrasPage, WorkersPage, NewDeliveryPage | **NEW** |
| `test/golden/helpers/golden_test_helpers.dart` | Font loading, fake data pump, widget wrapper | **NEW** |
| CI `test.yml` | Existing: analyze + unit + integration. Must add: deno test + golden test steps | **MODIFIED** |

---

## Recommended Project Structure

```
test/
├── unit/                          # Existing — no changes
│   ├── hash_chain_test.dart
│   ├── offline_queue_test.dart
│   ├── stock_calculator_test.dart
│   ├── forensic_test.dart
│   └── perfil_usuario_test.dart
├── integration/                   # Existing — no changes
│   ├── supabase/
│   │   ├── helpers/
│   │   │   ├── test_client.dart
│   │   │   └── test_data.dart
│   │   ├── rls_test.dart
│   │   ├── rpcs_test.dart
│   │   └── triggers_test.dart
│   └── e2e/
│       └── sync_service_e2e_test.dart
├── stress/                        # NEW — Hive stress tests
│   └── offline_queue_stress_test.dart
└── golden/                        # NEW — Golden file tests
    ├── helpers/
    │   └── golden_test_helpers.dart
    ├── obras_page_golden_test.dart
    ├── workers_page_golden_test.dart
    └── new_delivery_page_golden_test.dart

supabase/
└── functions/
    ├── notif-vencimiento/
    │   └── index.ts               # Existing — no changes
    └── tests/                     # NEW — Deno unit tests
        └── notif-vencimiento-test.ts

integration_test/                  # Existing — no changes
├── epp_app_test.dart
├── kiosko_test.dart
├── dashboard_test.dart
└── helpers/
    └── test_setup.dart

.github/workflows/
└── test.yml                       # MODIFIED — add deno test + golden steps
```

### Structure Rationale

- **test/stress/**: Separate from `test/unit/` because stress tests are slower (100-500 operations) and should not run by default in the sub-2-minute unit loop. Tagged `@Tags(['stress'])` so CI can include/exclude selectively.
- **test/golden/**: Separate from `test/unit/` because golden tests require `testWidgets`, produce `.png` artifacts, and must run in a specific rendering environment. CI generates golden files on Linux only.
- **supabase/functions/tests/**: Supabase official convention (source: Supabase Edge Functions docs). Deno's own file discovery finds `*-test.ts` automatically. Placing it under `functions/tests/` (not `test/`) keeps it out of `flutter test` discovery.
- **No barrel files**: Consistent with existing codebase conventions — direct relative imports only.

---

## Architectural Patterns

### Pattern 1: Hive Stress Testing with hive_test + Sequential Async Load

**What:** Use `hive_test` package (already a dev dependency) to spin up an in-memory Hive box, then drive `OfflineQueueService` with a high volume of enqueue/update/listPending calls in a tight async loop on the main isolate.

**When to use:** Testing that the service correctly filters backoff state and preserves ordering under load without involving threads. Dart's event loop is single-threaded per isolate; "concurrency" here means interleaved async operations, which is the real-world scenario for `OfflineQueueService`.

**Why not Dart isolates:** `OfflineQueueService` uses `Hive.box<String>('outbox_entregas')` as a static singleton. Hive boxes are not multi-isolate safe in Hive 2.x — spawning a second isolate that opens the same box races the file on disk. The correct stress model is sequential volume (hundreds of items) and time-warping via `DateTime` injection to stress the backoff filter.

**Trade-offs:** Does not test OS-level file I/O contention. Does test the service logic under realistic async pressure.

**Example:**
```dart
@Tags(['stress'])
void main() {
  group('OfflineQueueService — stress (STR-01)', () {
    setUp(() async {
      await setUpTestHive();
      await OfflineQueueService.init();
    });
    tearDown(() async => tearDownTestHive());

    test('500 enqueues all visible in listPending', () async {
      for (var i = 0; i < 500; i++) {
        await OfflineQueueService.enqueue(
          OfflineEntrega(
            localEventId: 'stress-$i',
            createdAtClientIso: DateTime.now().toIso8601String(),
            // ... minimal fields
          ),
        );
      }
      expect(OfflineQueueService.listPending(), hasLength(500));
    });

    test('backoff under load: 200 ERROR items with past retryAt all appear', () async {
      final past = DateTime.now().subtract(const Duration(hours: 1)).toIso8601String();
      for (var i = 0; i < 200; i++) {
        await OfflineQueueService.enqueue(
          OfflineEntrega(localEventId: 'back-$i', status: 'ERROR', nextRetryAt: past, ...),
        );
      }
      expect(OfflineQueueService.listPending(), hasLength(200));
    });
  });
}
```

### Pattern 2: Deno Edge Function Unit Tests with globalThis.fetch Stub

**What:** Test `notif-vencimiento/index.ts` logic in isolation by stubbing `globalThis.fetch` (intercepts Resend API calls) and providing a mock Supabase client. Uses `Deno.test` natively — no extra test framework needed.

**When to use:** Verifying the function's branching logic (no vencimientos → early return, CRITICO vs AVISO grouping, org-level email aggregation, date boundary conditions) without hitting real Supabase or Resend.

**Key insight:** The function imports `createClient` from esm.sh at runtime. The test file must either (a) mock the Supabase client constructor, or (b) use `supabase functions serve --env-file .env.test` + HTTP invoke via `fetch('http://localhost:54321/functions/v1/notif-vencimiento')`. For pure unit isolation, approach (a) is preferred for the logic tests; approach (b) is reserved for smoke-test invocation.

**Trade-offs:** Mocking `createClient` requires exporting a factory from the function or using dynamic import with a `__DEV__` flag. The cleanest approach is to extract the core logic into a pure function that the handler calls — then test the pure function directly without needing to mock the Deno server lifecycle.

**File:** `supabase/functions/tests/notif-vencimiento-test.ts`

**Example:**
```typescript
// Stub globalThis.fetch to intercept Resend API
const originalFetch = globalThis.fetch;

Deno.test('sends email when vencimientos exist', async () => {
  let capturedBody: unknown;
  globalThis.fetch = async (url, init) => {
    if (String(url).includes('resend.com')) {
      capturedBody = JSON.parse(init?.body as string);
      return new Response(JSON.stringify({ id: 'fake-id' }), { status: 200 });
    }
    return originalFetch(url, init);
  };

  // Invoke function handler directly (extracted as testable function)
  const result = await handleNotifVencimiento(mockSupabaseClient, mockVencimientos);

  assertEquals(result.status, 200);
  assertExists(capturedBody);
  globalThis.fetch = originalFetch;
});
```

**Run command:**
```bash
deno test supabase/functions/tests/ --allow-env --allow-net
```

### Pattern 3: Flutter Golden File Tests on Linux with Font Loading

**What:** `testWidgets` + `matchesGoldenFile` captures a pixel-perfect PNG snapshot of a widget tree and compares it against a committed baseline. Fails if pixels differ.

**When to use:** Regression detection for UI-critical screens (ObrasPage list, WorkersPage card, NewDeliveryPage form). Not for entire app screens with live Supabase data — only for widget subtrees fed with deterministic fake data.

**Critical constraint — platform rendering:** Golden files generated on macOS will fail on Linux CI due to font anti-aliasing differences (confirmed by multiple sources). The established solution is: generate and commit golden files **on Linux** (or inside a Docker container matching CI). Local macOS development uses `--update-goldens` only inside the CI environment, or uses a Linux VM/Docker for golden generation.

**Critical constraint — fonts:** Flutter test renderer uses a default "ahem" test font unless explicitly loaded. System fonts (Material Icons, Roboto) render differently across OS versions. Use `loadFonts()` in test setup to load actual app fonts from the bundle, or constrain tests to icon-free widgets.

**Widget scope:** Target isolated, deterministic widget subtrees. For pages with Supabase dependencies (ObrasPage, WorkersPage), create a stripped mock constructor that accepts pre-loaded `List<Map<String,dynamic>>` data instead of triggering `initState` network calls. This requires minor, non-breaking refactors to the pages.

**Trade-offs:** Golden tests are brittle during active UI development. Update goldens intentionally via `flutter test --update-goldens test/golden/` only when a visual change is intentional.

**Example:**
```dart
// test/golden/helpers/golden_test_helpers.dart
Future<void> loadAppFonts() async {
  // Load fonts from bundle so goldens match production rendering
  final fontLoader = FontLoader('Roboto');
  // ... load from assets
  await fontLoader.load();
}

// test/golden/obras_page_golden_test.dart
void main() {
  setUpAll(loadAppFonts);

  testWidgets('ObrasPage — lista vacía (golden)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: ObrasPagePreview(obras: []),  // testable constructor
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(ObrasPagePreview),
      matchesGoldenFile('goldens/obras_page_empty.png'),
    );
  });
}
```

---

## Data Flow

### Stress Test Flow (Hive Queue)

```
Test setUp
    ↓
setUpTestHive() → in-memory Hive box (hive_test)
    ↓
OfflineQueueService.init() → opens 'outbox_entregas' box
    ↓
[loop N times] OfflineQueueService.enqueue(OfflineEntrega(...))
    ↓ (each enqueue writes JSON to Hive box)
OfflineQueueService.listPending() → reads + filters all keys
    ↓
assertions on count, order, backoff exclusion
    ↓
tearDownTestHive() → closes + deletes temp Hive dir
```

### Edge Function Test Flow (Deno)

```
Deno.test setup
    ↓
globalThis.fetch stub installed (intercepts Resend API)
    ↓
Mock Supabase client → returns controlled Vencimiento[] data
    ↓
handler(mockClient, mockData) → executes function logic
    ↓ (no real network calls; stubs capture payloads)
assert: correct email grouping by org
assert: CRITICO vs AVISO subject line logic
assert: empty vencimientos → early 200 return
    ↓
stub restored
```

### Golden Test Flow

```
setUpAll: loadAppFonts()
    ↓
testWidgets: pumpWidget(MaterialApp > PagePreview(fakeData))
    ↓
pumpAndSettle() — let animations settle
    ↓
matchesGoldenFile('goldens/name.png')
    ↓ (first run with --update-goldens): writes PNG baseline
    ↓ (subsequent runs): pixel-compares against committed PNG
    ↓
CI: fail if diff > 0px (no tolerance by default)
```

### CI Pipeline (Modified)

```
[Existing]                          [New steps — appended]
flutter analyze                     deno test supabase/functions/tests/
    ↓                                   ↓
flutter test test/unit/ test/widget  flutter test test/golden/
    ↓                                   ↓
flutter test test/integration/       flutter test test/stress/ --tags stress
    ↓
upload coverage
```

---

## Integration Points

### New vs Modified Components

| Component | Status | Touches Existing Code? |
|-----------|--------|------------------------|
| `test/stress/offline_queue_stress_test.dart` | **NEW** | No — uses `OfflineQueueService` API unchanged |
| `supabase/functions/tests/notif-vencimiento-test.ts` | **NEW** | No — tests in isolation; index.ts unchanged unless logic extraction refactor done |
| `test/golden/` directory + helper | **NEW** | Minor: pages need a test-friendly constructor variant (or `const` preview widget) |
| `test/golden/helpers/golden_test_helpers.dart` | **NEW** | No |
| `.github/workflows/test.yml` | **MODIFIED** | Append new CI steps only |
| `pubspec.yaml` | **MODIFIED** | Add `golden_toolkit` or keep raw `matchesGoldenFile` — decision below |

### Dependency Changes (pubspec.yaml)

No new `dependencies:` (production) are needed. Dev changes only:

```yaml
dev_dependencies:
  # Existing
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  hive_test: ^1.0.1
  # No new packages needed if using raw matchesGoldenFile
  # Optional: add alchemist ^0.8.0 for font consistency (recommended by LeanCode)
```

`hive_test` is already in `pubspec.yaml` — stress tests can use it immediately.

For golden tests: `alchemist` wraps `matchesGoldenFile` with deterministic font loading and CI/local split modes. Recommended but optional — raw `matchesGoldenFile` works if goldens are generated on Linux.

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Hive (local) | `setUpTestHive()` / `tearDownTestHive()` from `hive_test` | Already used in `test/unit/offline_queue_test.dart` — exact same pattern for stress |
| Resend API | `globalThis.fetch` stub in Deno test | Never hit real Resend in tests — stub always |
| Supabase RPC (`get_vencimientos_proximos`) | Mock `SupabaseClient` returned from `createClient` | Inject mock via constructor arg or module-level factory |
| Flutter rendering | `flutter_test` golden comparator | Must run on Linux for CI consistency |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Stress tests ↔ OfflineQueueService | Direct Dart API calls | No mocking needed — hive_test provides in-memory storage |
| Deno tests ↔ notif-vencimiento/index.ts | Import handler as function or HTTP invoke | Extracting `_handleRequest(client, data)` is cleaner than HTTP roundtrip |
| Golden tests ↔ Page widgets | Instantiate with fake data via test constructor | Pages need a `ObrasPage.preview({required List obras})` factory or a widget subtree split |
| CI ↔ Deno tests | `deno test` command in `test.yml` | Deno must be installed in CI runner; use `denoland/setup-deno` action |

---

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| Current (solo dev, <100 tests) | All test types run in single CI job sequentially; goldens committed in repo |
| Medium (team, 200+ tests) | Split CI into parallel jobs: unit/stress job, golden job, edge function job; golden diffs reviewed via PR artifact |
| Large (multiple apps, 500+ tests) | Golden files moved to a separate S3-compatible bucket; Deno tests run in Supabase CLI `supabase test functions` command |

### Scaling Priorities

1. **First bottleneck — CI time:** Golden tests add ~30-60s per screen. Tag as `@Tags(['golden'])` and run in a separate CI job after unit tests pass, to avoid blocking fast feedback.
2. **Second bottleneck — Golden file conflicts:** Multiple devs updating UI creates golden diffs on every PR. Mitigation: `--update-goldens` is a conscious action gated by a CI environment variable (`UPDATE_GOLDENS=true`).

---

## Anti-Patterns

### Anti-Pattern 1: Generating Golden Files on macOS, Validating on Linux CI

**What people do:** Run `flutter test --update-goldens` locally on macOS, commit PNGs, then wonder why CI fails.
**Why it's wrong:** Font subpixel rendering differs between macOS (Quartz) and Linux (FreeType). The committed PNG will never match what Linux CI renders, making golden tests permanently broken.
**Do this instead:** Generate goldens inside Linux Docker (`flutter/flutter:stable` image) or accept CI-only goldens by setting `FLUTTER_TEST_CI_GOLDEN=true` and using separate golden paths for local vs CI.

### Anti-Pattern 2: Testing Full Pages with Live Supabase Calls in Golden Tests

**What people do:** `pumpWidget(const MyApp())` and try to golden the ObrasPage after login.
**Why it's wrong:** Network calls in `initState` make the widget non-deterministic. `pumpAndSettle()` will timeout waiting for async state. Golden tests must be pixel-stable.
**Do this instead:** Create a `ObrasPagePreview` constructor or a standalone `ObrasPageBody` widget that accepts pre-loaded data. The production `ObrasPage` stays unchanged; the preview widget is test-only scaffolding.

### Anti-Pattern 3: Using Dart Isolates for Hive Stress Tests

**What people do:** Spawn multiple isolates calling `OfflineQueueService.enqueue()` simultaneously to simulate "concurrency."
**Why it's wrong:** Hive 2.x boxes are not multi-isolate safe. Two isolates opening the same box path will race on disk writes and corrupt the box. The production app is single-threaded (Flutter main isolate only) — isolate concurrency is not a real-world scenario for this service.
**Do this instead:** Test high sequential volume (500+ operations) and time-based backoff boundaries. This matches actual usage patterns and is safe with `hive_test`.

### Anti-Pattern 4: Hitting Real Resend API in Edge Function Tests

**What people do:** Run `supabase functions serve` and invoke with real `.env` credentials, letting it call `api.resend.com`.
**Why it's wrong:** Tests become non-deterministic (depends on Resend uptime), can generate real emails to real addresses, and are rejected by CI environments without API key secrets.
**Do this instead:** Stub `globalThis.fetch` in Deno tests. For smoke-test invocation (optional, manual only), use `supabase functions invoke notif-vencimiento --local` against a seeded local Supabase with `--no-verify-jwt`.

---

## Build/Execution Order

The ordering respects existing infrastructure dependencies and incremental complexity:

```
Phase 1: Hive Stress Tests
  Rationale: No new dependencies (hive_test already present). Pure Dart.
  Fastest path to value — directly extends existing offline_queue_test.dart patterns.
  Run: flutter test test/stress/ --tags stress

Phase 2: Deno Edge Function Tests
  Rationale: Self-contained (Deno runtime, separate from Dart toolchain).
  Requires: deno installed locally + in CI. No Supabase secrets needed for unit tests.
  Run: deno test supabase/functions/tests/ --allow-env

Phase 3: Golden File Tests
  Rationale: Most setup cost — requires page widget refactors + Linux golden generation.
  Requires: Linux environment for baseline generation, font loading decisions.
  Run: flutter test test/golden/ --tags golden
       flutter test test/golden/ --update-goldens  (Linux only, intentional)
```

**CI job ordering in `test.yml`:**
```
Existing steps (unchanged)
    → flutter analyze
    → flutter test test/unit/ test/widget_test.dart --coverage
    → flutter test test/integration/supabase/ test/integration/e2e/ --tags integration
New steps (appended)
    → flutter test test/stress/ --tags stress
    → Setup Deno (denoland/setup-deno@v1)
    → deno test supabase/functions/tests/ --allow-env --allow-net
    → flutter test test/golden/ --tags golden
```

Golden update workflow (separate, manual trigger):
```yaml
# In test.yml or a separate goldens.yml:
- name: Update Goldens
  if: env.UPDATE_GOLDENS == 'true'
  run: flutter test test/golden/ --update-goldens
- name: Commit Updated Goldens
  if: env.UPDATE_GOLDENS == 'true'
  run: git add test/golden/goldens/ && git commit -m "chore: update golden baselines"
```

---

## Sources

- [Supabase Edge Function unit testing](https://supabase.com/docs/guides/functions/unit-test) — official Deno test file structure (`functions/tests/*-test.ts`)
- [Deno mock fetch discussion](https://github.com/denoland/deno/discussions/18809) — `globalThis.fetch` stub pattern
- [Flutter golden file test writing guide](https://github.com/flutter/flutter/wiki/Writing-a-golden-file-test-for-package:flutter) — official Flutter team conventions
- [Golden tests Linux CI font issue](https://hevawu.github.io/blog/2022/04/13/Run-Flutter-Golden-Tests-Between-MacOS-And-CI) — macOS vs Linux rendering difference (MEDIUM confidence — blog post, consistent with official Flutter team guidance)
- [Alchemist golden tests tutorial](https://verygood.ventures/blog/alchemist-golden-tests-tutorial/) — VGV recommendation for font-deterministic golden tests
- [Flutter golden tests best practices — LeanCode](https://leancode.co/glossary/golden-tests-in-flutter) — "Run on Linux in CI" recommendation
- [Dart concurrency docs](https://dart.dev/language/concurrency) — confirms single-threaded event loop; isolates share no memory
- [matchesGoldenFile API reference](https://api.flutter.dev/flutter/flutter_test/matchesGoldenFile.html) — official matcher

---

*Architecture research for: TrazApp v2.0 advanced test types integration*
*Researched: 2026-06-13*

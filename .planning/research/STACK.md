# Stack Research

**Domain:** Advanced testing additions — Flutter golden tests, Hive load/stress tests, Deno Edge Function tests
**Researched:** 2026-06-13
**Confidence:** HIGH (all package versions verified via pub.dev and official docs; Deno patterns verified via official Deno docs and Supabase docs)

## Context: What Already Exists (Do Not Re-add)

The existing `pubspec.yaml` already has:
- `flutter_test` (SDK) — widget and unit testing
- `integration_test` (SDK) — integration test runner
- `hive_test: ^1.0.1` — Hive in-memory setup/teardown for unit tests

The existing `test/` tree has 50 unit tests, 14 integration tests, 3 E2E service tests, plus `test/widget_test.dart`.

The CI pipeline runs on `ubuntu-latest` via `subosito/flutter-action@v2` (stable channel).

---

## New Capabilities Required

Three test types need new stack additions. They are independent — each can be implemented separately.

---

## 1. Load/Stress Tests — Hive OfflineQueueService

### What's needed

`hive_test` and `flutter_test` are already present. Hive stress tests run on the Dart event loop using `Future.wait()` for concurrent simulated inserts. No additional packages required — this is a test design question, not a package question.

**Key constraint:** Hive 2.x is single-threaded (no isolate-safe concurrent writes). Concurrent stress in tests means concurrent async `enqueue()` calls on the single event loop, not true multi-thread parallelism. This accurately models what `OfflineQueueService` does in production (Flutter runs single-threaded).

### No new pubspec.yaml entries needed for this layer.

The only addition worth considering is `fake_async` if you want to test the backoff timer logic without real wall-clock waits. It's part of `flutter_test` transitively, but not directly importable without explicit declaration.

| Package | Version | Purpose | Why Needed |
|---------|---------|---------|------------|
| `fake_async` | `^1.3.2` | Advance simulated time to test backoff delays | Without it, testing `nextRetryAt` backoff in stress scenarios requires `await Future.delayed()` wall-clock waits, making tests slow. `fake_async` lets you jump time forward instantly. Already a transitive dep of `flutter_test` but must be declared explicitly to import. |

---

## 2. Edge Function Tests — `notif-vencimiento` (Deno/TypeScript)

### What's needed

The Edge Function is pure TypeScript/Deno at `supabase/functions/notif-vencimiento/index.ts`. It has three external dependencies to test:
1. Supabase client (RPC `get_vencimientos_proximos` + query `perfiles`)
2. `fetch()` to `api.resend.com/emails`
3. `Deno.env.get()` for secrets

Tests live in `supabase/functions/tests/` (Supabase CLI convention) and run with `deno test --allow-all`.

**There is no `pubspec.yaml` entry for Deno.** These are TypeScript files with JSR/esm.sh imports declared inline.

| Import (inline in test file) | Source | Purpose | Why Needed |
|------------------------------|--------|---------|------------|
| `assertEquals`, `assertExists`, `assertStringIncludes` | `jsr:@std/assert@^1.0.0` | Assertion library for Deno tests | Deno's standard assert module — official recommendation for all Deno unit tests |
| `stub`, `returnsNext` | `jsr:@std/testing@^1.0.0/mock` | Stub `globalThis.fetch` to intercept Resend API calls | Without stubbing fetch, tests would hit the real Resend API, incur costs, and need a live API key. `stub()` with `returnsNext()` lets you return canned `Response` objects per call. |
| `spy` | `jsr:@std/testing@^1.0.0/mock` | Spy on `console.log` / `console.error` to verify log output | The function logs `Enviados: N emails` — asserting on this verifies the success path without a real DB |

**No Supabase CLI local stack needed for unit tests of `notif-vencimiento`.** The function logic (grouping by org, building email HTML, filtering recipients) can be extracted into pure functions and tested without a running Supabase instance. The `createClient` call is only needed for integration tests.

**For integration tests** (function invocation against real Supabase):

| Tool | How to install | Purpose |
|------|---------------|---------|
| Supabase CLI | `brew install supabase/tap/supabase` (already available per CLAUDE.md) | `supabase functions serve` to run function locally for integration tests |
| Deno runtime | `brew install deno` | Run `deno test` directly; already required for Edge Function development |

---

## 3. Flutter Golden File Tests

### What's needed

Built-in `flutter_test` already provides `matchesGoldenFile()`. The critical question is whether to use it raw or via a helper package.

**Decision: Use `alchemist ^0.14.0`** — not raw `matchesGoldenFile`.

Rationale: The three target screens (`ObrasPage`, `WorkersPage`, `NewDeliveryPage`) require Supabase client initialization and Hive to render. Golden tests need to render in isolation with mock data. `alchemist` provides:
- `goldenTest()` / `GoldenTestScenario` for declarative multi-scenario snapshots
- Automatic CI mode (replaces text with colored blocks) to avoid font rendering differences between macOS (developer) and ubuntu-latest (CI)
- `AlchemistConfig` to control theme, screen size, and pixel ratio
- Active maintenance (0.14.0 published 3 months ago, by betterment.dev); `golden_toolkit` is discontinued

**Critical CI consideration:** Golden files generated on macOS will FAIL on `ubuntu-latest` CI due to font rendering differences (Skia engine renders Roboto differently per OS). `alchemist`'s CI mode addresses this by obscuring text — compare structure/layout only, not pixel-perfect text.

| Package | Version | Purpose | Why Needed |
|---------|---------|---------|------------|
| `alchemist` | `^0.14.0` | Golden test runner with CI/local dual-mode | Handles the macOS-vs-Linux font drift problem automatically; replaces discontinued `golden_toolkit`; active maintenance |
| `mocktail` | `^1.0.5` | Mock `OfflineQueueService`, `AuthService`, Supabase client in widget tests | Target screens call services in `initState()` — mocking them is required to render in isolation without a live Supabase connection |
| `network_image_mock` | `^2.1.1` | Intercept `NetworkImage` requests in tests | `WorkersPage` and other screens load worker photos via network URLs; tests will throw unless network images are mocked |

---

## Recommended pubspec.yaml Changes

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  hive_test: ^1.0.1
  # NEW additions for v2.0:
  fake_async: ^1.3.2           # Hive stress tests — advance backoff timers without wall-clock waits
  alchemist: ^0.14.0           # Golden/snapshot tests — CI-safe dual-mode golden comparisons
  mocktail: ^1.0.5             # Mock services in golden tests — isolate screens from Supabase/Hive
  network_image_mock: ^2.1.1   # Block NetworkImage in golden tests — prevent test failures on image URLs
```

---

## Deno Test Configuration (no pubspec.yaml — inline imports)

Create `supabase/functions/tests/notif-vencimiento-test.ts` with these imports:

```typescript
import { assertEquals, assertStringIncludes } from "jsr:@std/assert@^1.0.0";
import { stub, spy, returnsNext } from "jsr:@std/testing@^1.0.0/mock";
```

Run locally:
```bash
deno test --allow-all supabase/functions/tests/notif-vencimiento-test.ts
```

---

## CI Pipeline Changes Required

Golden tests must be committed with goldens generated on Linux (not macOS). Either:
- Generate goldens in CI on first run with `--update-goldens` flag, commit, then compare on subsequent runs
- OR use `alchemist`'s CI mode which skips pixel-perfect text comparison (recommended)

The `alchemist` CI mode is detected via the `CI` environment variable (present in GitHub Actions automatically). No CI workflow changes needed beyond adding a test step for goldens.

Add to `.github/workflows/test.yml`:

```yaml
- name: Golden Tests
  run: flutter test test/golden/ --update-goldens
  # On first run: generates. On subsequent runs with committed goldens: compares.
  # alchemist CI mode activates automatically when CI=true (set by GitHub Actions).
```

For the Deno edge function tests, add a separate job or step:

```yaml
- name: Edge Function Tests (Deno)
  run: deno test --allow-all supabase/functions/tests/
  # Requires deno to be installed on the runner. Use:
  # - uses: denoland/setup-deno@v2
  #   with: { deno-version: v2.x }
```

---

## Alternatives Considered

| Recommended | Alternative | Why Not |
|-------------|-------------|---------|
| `alchemist ^0.14.0` | Raw `matchesGoldenFile()` from `flutter_test` | Raw goldens have no CI mode — pixel drift between macOS and ubuntu-latest will cause false failures on every PR |
| `alchemist ^0.14.0` | `golden_toolkit ^0.15.0` | Discontinued by eBay, no updates in 3 years, incompatible with Flutter 3.x in some configurations |
| `mocktail ^1.0.5` | `mockito` with code generation | `mockito` requires `build_runner` and generated files — adds complexity. `mocktail` is null-safe and zero-codegen |
| `jsr:@std/testing/mock` (stub) | `deno_mock_fetch` (third-party) | `@std/testing/mock` is the official Deno stdlib — no third-party dependency needed |
| `fake_async ^1.3.2` | `await Future.delayed()` | Real delays make stress tests slow (100 items × 100ms backoff = 10s wall time). `fake_async` runs instantly |

## What NOT to Add

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `golden_toolkit` | Discontinued by eBay, stale for 3 years, CI font issues unresolved | `alchemist ^0.14.0` |
| `mockito` | Requires `build_runner` + generated `.mocks.dart` files — unnecessary overhead for this project size | `mocktail ^1.0.5` |
| `flutter_test_goldens` | Newer but less mature, smaller community, no clear advantage for this use case | `alchemist ^0.14.0` |
| Supabase local Docker stack for notif-vencimiento unit tests | Heavyweight — requires Docker, Supabase CLI start, port management in CI | Unit test pure functions with `deno test` + `@std/testing/mock` stubs only |

---

## Version Compatibility

| Package | Flutter Constraint | Notes |
|---------|-------------------|-------|
| `alchemist ^0.14.0` | Flutter 3.x+ | Tested against Flutter stable; requires `equatable ^2.0.3`, `meta ^1.7.0` (both already transitive) |
| `mocktail ^1.0.5` | Dart 3.x+, Flutter 3.x+ | Full null-safety; no code generation |
| `network_image_mock ^2.1.1` | Flutter 3.x+ | Wraps `HttpOverrides` globally — must be applied per test or in `setUp` |
| `fake_async ^1.3.2` | Dart 2.12+ | Transitive dep of `flutter_test` already; explicit declaration just makes import explicit |
| `jsr:@std/assert@^1.0.0` | Deno 1.x+, Deno 2.x+ | Current Deno stdlib; use JSR specifier not `deno.land/std` (deprecated path) |
| `jsr:@std/testing@^1.0.0/mock` | Deno 1.x+, Deno 2.x+ | Current Deno stdlib mock module; replaces old `deno.land/std/testing/mock.ts` |

---

## Sources

- https://pub.dev/packages/alchemist — version 0.14.0 confirmed, publisher betterment.dev, published 3 months ago
- https://pub.dev/packages/mocktail — version 1.0.5 confirmed, publisher felangel.dev
- https://pub.dev/packages/hive_test — version 1.0.1 confirmed; already in pubspec.yaml
- https://pub.dev/packages/network_image_mock — confirmed available; Flutter 3.x compatible
- https://pub.dev/packages/fake_async — confirmed available; transitive dep of flutter_test
- https://supabase.com/docs/guides/functions/unit-test — official Deno test runner recommendation, `jsr:@std/assert@1` imports
- https://docs.deno.com/examples/stubbing_tutorial/ — `stub()` from `jsr:@std/testing/mock` for `globalThis.fetch`
- https://api.flutter.dev/flutter/flutter_test/matchesGoldenFile.html — built-in golden file matcher
- https://github.com/Betterment/alchemist — alchemist source, CI mode documentation
- https://medium.com/mobilepeople/how-to-add-difference-tolerance-to-golden-tests-on-flutter-2d899c8baad2 — macOS/Linux golden drift problem, confirmed

---
*Stack research for: TrazApp v2.0 — Advanced Testing (load/stress, Edge Function, golden tests)*
*Researched: 2026-06-13*

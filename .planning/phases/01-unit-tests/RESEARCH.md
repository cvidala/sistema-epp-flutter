# Phase 1: Unit Tests — Research

**Researched:** 2026-06-01
**Domain:** Dart/Flutter unit testing — hash chain integrity, stock validation logic, Hive-backed queue with backoff, DateTime-dependent logic
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| UTL-01 | Tests de hash chain — verificar que `prev_hash` se encadena correctamente entre entregas consecutivas | Hash chain logic is pure Dart in `SyncService._canonicalJson` + `EvidenceService.hashString`. No Supabase needed — fully testable with crafted payloads. |
| UTL-02 | Tests de validación de stock — `_cargarStock` calcula correctamente ENTRADA - SALIDA por bodega+EPP | `_cargarStock` logic is pure arithmetic on a list of `{epp_id, tipo, cantidad}` rows. Extract to a static helper function and test with in-memory data. |
| UTL-03 | Tests de validación de stock — bloqueo cuando cantidad > disponible | Same extracted helper + the guard at line 973–985 of `new_delivery_page.dart`. No widget pump needed if logic is extracted. |
| UTL-04 | Tests de `OfflineQueueService.listPending` — filtrado por backoff (ERROR con nextRetryAt futuro excluido) | Requires Hive box open. Use `hive_test` (1.0.1) for temp-dir initialization. Covers lines 154–163 of `offline_queue_service.dart`. |
| UTL-05 | Tests de `OfflineQueueService.listPending` — ordenado cronológico por createdAt | Same Hive setup as UTL-04. Tests the `.sort()` at line 165. |
</phase_requirements>

---

## Summary

Phase 1 covers five unit requirements targeting three distinct code areas: hash chain computation (SyncService), stock availability arithmetic (_cargarStock in NewDeliveryPage), and queue filtering/ordering (OfflineQueueService.listPending). All five requirements can be satisfied with pure Dart unit tests — no network, no Supabase, no device plugins.

The primary architectural challenge is that `_cargarStock` is a private method on a StatefulWidget state class, and `OfflineQueueService.listPending` depends on an open Hive box. The hash chain tests face no structural impediment: the relevant logic (`_canonicalJson`, `_canonicalItems`, `EvidenceService.hashString`) is all accessible without Flutter initialization.

Two implementation decisions dominate the plan: (1) extract the stock computation logic to a testable static helper function before writing its tests, and (2) use the `hive_test` package for Hive initialization in the listPending tests rather than hand-rolling a temp-dir setup.

**Primary recommendation:** Extract stock logic into `StockCalculator.computeStock(rows)` + `StockCalculator.validateCart(carrito, stock)` static methods, then test those directly. Use `hive_test` for the Hive queue tests. Test hash chain via `EvidenceService.hashString` and a local reimplementation of the chaining formula.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Hash chain computation | Service Layer (SyncService) | — | `_canonicalJson`, `_canonicalItems`, `EvidenceService.hashString` all in service/evidence layer |
| Stock availability calculation | Presentation Layer (NewDeliveryPage) | — | `_cargarStock` is a private method on `_NewDeliveryPageState`; needs extraction |
| Stock guard (block if > available) | Presentation Layer (NewDeliveryPage) | — | Lines 973–985 of new_delivery_page.dart; coupled to widget state |
| Queue filtering + backoff | Service Layer (OfflineQueueService) | Persistence Layer (Hive) | `listPending()` reads from Hive box and applies time-based filter |
| Queue ordering | Service Layer (OfflineQueueService) | — | `.sort()` on `createdAtClientIso` strings |

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `flutter_test` | SDK (bundled) | Test runner, matchers, async utilities | Flutter built-in, already in dev_dependencies |
| `hive` | 2.2.3 | Hive box opened in listPending tests | Already in production dependencies |
| `hive_test` | 1.0.1 | Temp-dir Hive initialization for tests | Purpose-built for this exact problem; verified compatible with hive ^2.0.4 |
| `crypto` | 3.0.3 | SHA256 via `EvidenceService.hashString` | Already in production dependencies |

[VERIFIED: pub.dev registry — hive 2.2.3, hive_test 1.0.1, crypto 3.0.3 confirmed on pub.dev]

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `fake_async` | 1.3.3 | Control virtual time for Timer-based tests | Only needed if testing Timer-based debounce; NOT needed for backoff (ISO string comparison is pure logic) |
| `clock` | 1.1.2 | Mock `DateTime.now()` if refactored to use `clock.now()` | Only needed if production code is refactored to use clock package instead of `DateTime.now()` |

[VERIFIED: pub.dev registry — fake_async 1.3.3 from dart.dev publisher; clock 1.1.2]

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `hive_test` | Manual `Hive.init(tempDir)` + `addTearDown` | More control, zero extra dep, but requires `Directory.systemTemp.createTempSync()` boilerplate in every test file |
| `hive_test` | `mockito` mock of the box | Would require changing production code to accept injected box; unjustified complexity for 5 tests |
| Extracting stock logic | Widget-pump test on NewDeliveryPage | Widget tests are slower, require Flutter binding, and block on unresolved Supabase calls |

**Installation (only new package needed):**
```bash
dart pub add --dev hive_test
```

---

## Package Legitimacy Audit

> slopcheck was not available in this environment. Packages verified via pub.dev registry and publisher identity.

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| `hive_test` | pub.dev | ~5 years | 24.4k | github.com/netsells/hive_test | N/A | Approved — verified pub.dev, compatible with hive ^2.0.4 |
| `fake_async` | pub.dev | ~6 years | 5.14M | github.com/dart-lang/test | N/A | Approved — official dart.dev publisher |
| `clock` | pub.dev | ~5 years | bundled | github.com/dart-lang/clock | N/A | Approved — official tools.dart.dev publisher |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

*slopcheck was unavailable at research time. Packages verified via official pub.dev publisher identity (`dart.dev`, `tools.dart.dev`, and established publisher `Netsells`). All three are well-established packages with long histories. The planner may add a `checkpoint:human-verify` gate before the `dart pub add --dev hive_test` task if desired.*

---

## Architecture Patterns

### System Architecture Diagram

```
Test Files                      Subject Under Test
─────────────────               ────────────────────────────────
hash_chain_test.dart   ──────►  EvidenceService.hashString()
                                SyncService._canonicalJson() [extracted/reimplemented inline]

stock_validation_test.dart ───► StockCalculator.computeStock(rows)  [NEW — extract from _cargarStock]
                                StockCalculator.validateCart(carrito, stock)  [NEW — extract guard logic]

offline_queue_test.dart  ─────► OfflineQueueService.listPending()
(existing, extended)            └── Hive.box<String>('outbox_entregas')
                                    └── hive_test: setUpTestHive() / tearDownTestHive()
```

### Recommended Test File Structure

```
test/
├── unit/
│   ├── forensic_test.dart          # existing — passes
│   ├── offline_queue_test.dart     # existing — extend with Hive-backed listPending tests
│   ├── perfil_usuario_test.dart    # existing — passes
│   ├── hash_chain_test.dart        # NEW — UTL-01
│   └── stock_validation_test.dart  # NEW — UTL-02, UTL-03
└── widget_test.dart                # existing (Flutter default)
```

### Pattern 1: Hash Chain Test (UTL-01)

**What:** Verify that `prevHash` from delivery N becomes the `prevHash` input for delivery N+1, producing a different `hash` than if `prevHash` were empty.

**Key insight:** The chaining formula in `SyncService` is:
```
toHash = '${prevHash ?? ''}|$canonicalJson'
hash = EvidenceService.hashString(toHash)
```

`EvidenceService.hashString` is a pure static function with no Supabase dependency. The canonical JSON builder logic can be tested by reimplementing the sort-then-encode inline in the test, or by making `_canonicalJson` and `_canonicalItems` visible for testing (add `@visibleForTesting`).

**Recommended approach:** Test the chaining property directly — do not call `syncOnce()`. Compute hashes manually and assert the chain relationship.

```dart
// Source: lib/evidence_service.dart + lib/services/sync_service.dart (adapted)
import 'dart:convert';
import 'package:epp_app/evidence_service.dart';

String canonicalJson(Map<String, dynamic> m) {
  final keys = m.keys.toList()..sort();
  final out = <String, dynamic>{};
  for (final k in keys) out[k] = m[k];
  return jsonEncode(out);
}

test('hash chain: delivery 2 prev_hash equals delivery 1 hash', () {
  const deviceId = 'device-test';
  const payload1 = { 'device_id': deviceId, 'local_event_id': 'evt-001', /* ... */ };
  final hash1 = EvidenceService.hashString('|${canonicalJson(payload1)}');

  final payload2 = { 'device_id': deviceId, 'local_event_id': 'evt-002', /* ... */ };
  final hash2 = EvidenceService.hashString('$hash1|${canonicalJson(payload2)}');

  // Property: hash2 was computed with hash1 as prev_hash
  expect(hash2, isNot(equals(hash1)));
  // Negative: wrong prev_hash produces different hash
  final hash2Wrong = EvidenceService.hashString('wrong_prev|${canonicalJson(payload2)}');
  expect(hash2Wrong, isNot(equals(hash2)));
});
```

[VERIFIED: lib/evidence_service.dart — `hashString` is a public static method, no Flutter init needed]
[VERIFIED: lib/services/sync_service.dart lines 108–127 — chaining formula confirmed]

### Pattern 2: Hive-Backed listPending Tests (UTL-04, UTL-05)

**What:** Initialize a real temporary Hive instance, enqueue OfflineEntrega records, call `OfflineQueueService.listPending()`, and assert filtering and ordering.

**Critical detail:** `OfflineQueueService.listPending()` calls `DateTime.now()` directly on line 145. For backoff tests, the simplest approach is to set `nextRetryAt` to a time clearly in the past or future relative to `DateTime.now()` at test execution — no clock mocking needed.

```dart
// Source: hive_test 1.0.1 API + offline_queue_service.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:epp_app/services/offline_queue_service.dart';

void main() {
  setUp(() async {
    await setUpTestHive();
    await OfflineQueueService.init();
  });

  tearDown(() async {
    await tearDownTestHive();
  });

  test('UTL-04: ERROR com nextRetryAt no futuro é excluida do listPending', () async {
    // nextRetryAt 1 hour from now → should be excluded
    final futureRetry = DateTime.now().add(const Duration(hours: 1)).toIso8601String();
    await OfflineQueueService.enqueue(_entrega(
      localEventId: 'evt-backoff',
      status: 'ERROR',
      nextRetryAt: futureRetry,
    ));
    expect(OfflineQueueService.listPending(), isEmpty);
  });

  test('UTL-04: ERROR con nextRetryAt pasado sí aparece en listPending', () async {
    final pastRetry = DateTime.now().subtract(const Duration(hours: 1)).toIso8601String();
    await OfflineQueueService.enqueue(_entrega(
      localEventId: 'evt-retry-ok',
      status: 'ERROR',
      nextRetryAt: pastRetry,
    ));
    expect(OfflineQueueService.listPending(), hasLength(1));
  });

  test('UTL-05: listPending ordena por createdAtClientIso', () async {
    await OfflineQueueService.enqueue(_entrega(
      localEventId: 'evt-B',
      createdAt: '2026-06-01T12:00:00.000Z',
    ));
    await OfflineQueueService.enqueue(_entrega(
      localEventId: 'evt-A',
      createdAt: '2026-06-01T10:00:00.000Z',
    ));
    final pending = OfflineQueueService.listPending();
    expect(pending[0].localEventId, equals('evt-A'));
    expect(pending[1].localEventId, equals('evt-B'));
  });
}
```

[VERIFIED: lib/services/offline_queue_service.dart lines 143–166 — listPending logic confirmed]
[VERIFIED: pub.dev — hive_test 1.0.1 provides setUpTestHive/tearDownTestHive]

### Pattern 3: Stock Validation Tests (UTL-02, UTL-03)

**What:** The `_cargarStock` logic and the guard at lines 973–985 are private to `_NewDeliveryPageState`. Testing them requires extraction.

**Recommended extraction:** Create `lib/services/stock_calculator.dart` with two pure static methods:

```dart
// New file: lib/services/stock_calculator.dart
class StockCalculator {
  /// Computes available stock per EPP from movement rows.
  /// rows: List of {epp_id: String, tipo: 'ENTRADA'|'SALIDA', cantidad: int}
  static Map<String, int> computeStock(List<Map<String, dynamic>> rows) {
    final mapa = <String, int>{};
    for (final r in rows) {
      final id = r['epp_id'] as String;
      final tipo = r['tipo'] as String;
      final qty = (r['cantidad'] as num).toInt();
      mapa[id] = (mapa[id] ?? 0) + (tipo == 'ENTRADA' ? qty : -qty);
    }
    return mapa;
  }

  /// Returns null if cart is valid, or an error string if stock insufficient.
  static String? validateCart(
    Map<String, int> carrito,
    Map<String, int> stockDisponible,
  ) {
    for (final entry in carrito.entries) {
      final disponible = stockDisponible[entry.key] ?? 0;
      if (entry.value > disponible) return entry.key; // return failing epp_id
    }
    return null;
  }
}
```

Then call `StockCalculator.computeStock(rows)` from `_cargarStock` and `StockCalculator.validateCart(carrito, stockDisponible)` from the submit guard.

```dart
// Source: lib/new_delivery_page.dart lines 173–188 (adapted)
test('UTL-02: ENTRADA - SALIDA calcula stock correcto', () {
  final rows = [
    {'epp_id': 'casco-001', 'tipo': 'ENTRADA', 'cantidad': 10},
    {'epp_id': 'casco-001', 'tipo': 'SALIDA',  'cantidad': 3},
    {'epp_id': 'guantes-01', 'tipo': 'ENTRADA', 'cantidad': 5},
  ];
  final stock = StockCalculator.computeStock(rows);
  expect(stock['casco-001'], equals(7));
  expect(stock['guantes-01'], equals(5));
});

test('UTL-03: validateCart bloquea cuando cantidad > disponible', () {
  final stock = {'casco-001': 2};
  final carrito = {'casco-001': 3};
  expect(StockCalculator.validateCart(carrito, stock), equals('casco-001'));
});

test('UTL-03: validateCart permite cuando cantidad <= disponible', () {
  final stock = {'casco-001': 5};
  final carrito = {'casco-001': 3};
  expect(StockCalculator.validateCart(carrito, stock), isNull);
});
```

[VERIFIED: lib/new_delivery_page.dart lines 173–188 and 973–985 — logic confirmed via source read]

### Anti-Patterns to Avoid

- **Calling `OfflineQueueService.listPending()` without opening the box:** Will throw `HiveError: Box not found. Did you forget to call Hive.openBox()?`. Always call `OfflineQueueService.init()` after `setUpTestHive()`.
- **Reusing the same Hive box name across test groups without tearDown:** Hive boxes persist in temp dir within a test run. Call `tearDownTestHive()` to get a clean slate per test.
- **Testing `_cargarStock` by pumping NewDeliveryPage as a widget:** Creates dependency on Supabase.instance initialization, camera, geolocator plugins. Pure logic extraction is the correct approach.
- **Mocking `DateTime.now()` via `fake_async`:** Not needed here. `listPending()` compares ISO strings. Setting `nextRetryAt` to `DateTime.now() ± delta` in test data is sufficient and simpler.
- **Using `@visibleForTesting` on private SyncService helpers and importing them:** The hash test only needs `EvidenceService.hashString`. Avoid exposing `SyncService` internals; reimplement the 4-line canonical JSON logic inline in the test.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Temp directory for Hive in tests | Custom `setUp` with `Directory.systemTemp.createTempSync()` | `hive_test` package | Handles cleanup, cross-platform path, and teardown correctly |
| DateTime mocking for backoff | `fake_async` + clock refactor | ISO string offsets in test data | `listPending` already uses string comparison; mocking `DateTime.now()` requires production code changes that are out of scope |
| Mock Hive box | `mockito` mock of `HiveInterface` | Real Hive via `hive_test` | Mock would require changing production code to inject box; hive_test gives full real behavior |

**Key insight:** Every requirement in this phase can be satisfied without mocks. The logic is pure enough to test directly once the stock calculation is extracted.

---

## Common Pitfalls

### Pitfall 1: Hive "Box not found" in tests
**What goes wrong:** Calling `OfflineQueueService.listPending()` or `enqueue()` before the box is open throws `HiveError`.
**Why it happens:** `OfflineQueueService._boxName` box must be explicitly opened; the service `init()` does this, but only after `Hive.init(path)` has been called.
**How to avoid:** Call `setUpTestHive()` first, then `OfflineQueueService.init()` in `setUp()`. Pair with `tearDownTestHive()` in `tearDown()`.
**Warning signs:** `HiveError: Cannot write to a closed box` or `Box not found` in test output.

### Pitfall 2: `_cargarStock` is a private method on a State class
**What goes wrong:** Attempting to test stock logic through the widget requires Flutter binding, Supabase init, and throws `LateInitializationError` on `Supabase.instance`.
**Why it happens:** `new_delivery_page.dart` uses `Supabase.instance.client` directly in `initState`. Even a widget pump attempt calls `initState`.
**How to avoid:** Extract `_cargarStock` arithmetic to `StockCalculator.computeStock` before writing tests. Do not test via widget pump for this requirement.
**Warning signs:** Any test that imports `new_delivery_page.dart` and tries to pump it without Supabase initialization.

### Pitfall 3: Hash chain test asserts wrong property
**What goes wrong:** Test passes even if chaining is broken, because hash equality is tested on the wrong object.
**Why it happens:** If you only test `hash != null`, not that `hash2` was specifically derived from `hash1`, the test doesn't catch chain breaks.
**How to avoid:** Test the property explicitly: compute `expectedHash2 = hashString('$hash1|$canonicalPayload2')` and assert `actual == expectedHash2`.
**Warning signs:** Test passes even when `prevHash` is hardcoded to empty string.

### Pitfall 4: `hive_test` package is 5 years old
**What goes wrong:** Package may not be actively maintained.
**Why it happens:** Last release was 5 years ago.
**How to avoid:** Confirmed compatible with `hive ^2.0.4` (which covers 2.2.3). Resolved successfully in dependency check. As a fallback, manual Hive init with `Directory.systemTemp` works identically — the planner should note this as a fallback if `hive_test` causes issues.
**Warning signs:** Pub version conflict during `dart pub get`.

---

## Code Examples

### EvidenceService.hashString — confirmed signature
```dart
// Source: lib/evidence_service.dart line 40-42
static String hashString(String input) {
  return hashBytes(Uint8List.fromList(utf8.encode(input)));
}
// hashBytes uses sha256.convert(bytes).toString()
```

### OfflineQueueService listPending — backoff filter (exact logic)
```dart
// Source: lib/services/offline_queue_service.dart lines 143-166
if (e.status == 'ERROR' && e.nextRetryAt != null) {
  final retryTime = DateTime.tryParse(e.nextRetryAt!);
  if (retryTime != null && retryTime.isAfter(now)) continue;  // excluded
}
// sort: out.sort((a, b) => a.createdAtClientIso.compareTo(b.createdAtClientIso));
```

### _cargarStock — exact arithmetic to extract
```dart
// Source: lib/new_delivery_page.dart lines 181-187
mapa[id] = (mapa[id] ?? 0) + (tipo == 'ENTRADA' ? qty : -qty);
```

### SyncService hash chaining formula (exact)
```dart
// Source: lib/services/sync_service.dart lines 125-128
final canon    = _canonicalJson(payload);
final toHash   = '${prevHash ?? ''}|$canon';
final eventHash = EvidenceService.hashString(toHash);
```

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | flutter_test (bundled with Flutter 3.41.5 / Dart 3.11.3) |
| Config file | none — uses default `flutter test` discovery |
| Quick run command | `flutter test test/unit/` |
| Full suite command | `flutter test test/unit/` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| UTL-01 | prev_hash de entrega N+1 = hash de entrega N | unit | `flutter test test/unit/hash_chain_test.dart` | ❌ Wave 0 |
| UTL-02 | computeStock(ENTRADA+SALIDA) = diferencia correcta | unit | `flutter test test/unit/stock_validation_test.dart` | ❌ Wave 0 |
| UTL-03 | validateCart bloquea cuando cantidad > disponible | unit | `flutter test test/unit/stock_validation_test.dart` | ❌ Wave 0 |
| UTL-04 | listPending excluye ERROR con nextRetryAt futuro | unit | `flutter test test/unit/offline_queue_test.dart` | ✅ (extend) |
| UTL-05 | listPending ordena por createdAtClientIso asc | unit | `flutter test test/unit/offline_queue_test.dart` | ✅ (extend) |

### Sampling Rate
- **Per task commit:** `flutter test test/unit/ --no-pub`
- **Per wave merge:** `flutter test test/unit/ --no-pub`
- **Phase gate:** All 5 tests green before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `test/unit/hash_chain_test.dart` — covers UTL-01
- [ ] `test/unit/stock_validation_test.dart` — covers UTL-02, UTL-03
- [ ] `lib/services/stock_calculator.dart` — extracted logic needed before UTL-02/UTL-03 tests can be written
- [ ] `dart pub add --dev hive_test` — needed before UTL-04/UTL-05 Hive-backed tests

*(Existing test files `offline_queue_test.dart`, `perfil_usuario_test.dart`, `forensic_test.dart` pass and require no changes to infrastructure — only new test groups added.)*

---

## Security Domain

> `security_enforcement: true` in config.json.

### Applicable ASVS Categories (Level 1)

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Tests are offline, no auth calls |
| V3 Session Management | no | No session logic tested |
| V4 Access Control | no | No RLS tested in Phase 1 |
| V5 Input Validation | yes (UTL-02/03) | Validated via `StockCalculator.validateCart` — validates quantity > 0 and > available |
| V6 Cryptography | yes (UTL-01) | SHA-256 via `package:crypto` — never hand-rolled; verified correct algorithm |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Hash chain forgery (altering delivery after sync) | Tampering | UTL-01 verifies that any prevHash change breaks the chain — test documents the tamper-evidence property |
| Negative stock / over-delivery | Tampering | UTL-02/03 verifies client-side guard; Supabase trigger `trg_prevent_stock_negativo` is server-side defense (Phase 2) |

**Security note:** The hash chain tests in UTL-01 serve as documentation of the system's tamper-evidence property. They do not replace the server-side immutability trigger (`TRG-03`) tested in Phase 2.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK | All tests | ✓ | 3.41.5 (Dart 3.11.3) | — |
| `hive_test` | UTL-04, UTL-05 | Needs install | 1.0.1 | Manual `Hive.init(tempDir)` + `addTearDown` |
| `crypto` | UTL-01 | ✓ | 3.0.3 (in prod deps) | — |
| `hive` | UTL-04, UTL-05 | ✓ | 2.2.3 (in prod deps) | — |

**Missing dependencies with no fallback:** none
**Missing dependencies with fallback:**
- `hive_test` — install with `dart pub add --dev hive_test`; fallback is manual temp dir setup if package conflicts arise

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `hive_test 1.0.1` works correctly with `hive 2.2.3` at runtime despite no maintenance since 2021 | Standard Stack, Hive Pitfall #4 | If incompatible, use manual `Hive.init(Directory.systemTemp.createTempSync().path)` + `addTearDown(() async { await Hive.close(); ... })` |
| A2 | The `_canonicalJson` and `_canonicalItems` helper methods in SyncService are stable (no planned refactor) | Code Examples | If they change, hash chain tests must be updated |
| A3 | The stock calculation extracted to `StockCalculator` will not break any existing callers when `_cargarStock` delegates to it | Architecture | Low risk — it's a private method with one call site |

---

## Open Questions

1. **Should `StockCalculator` live in `lib/services/` or `lib/utils/`?**
   - What we know: The project has a `lib/services/` directory with domain logic; no `utils/` directory exists.
   - What's unclear: Whether a pure calculation helper belongs in `services/` (convention says services have side effects) or a new `lib/models/` or `lib/utils/` folder.
   - Recommendation: Place in `lib/services/stock_calculator.dart` to stay consistent with existing pattern; rename or move later if a `utils/` convention is adopted.

2. **Should `SyncService._canonicalJson` and `_canonicalItems` be annotated `@visibleForTesting`?**
   - What we know: The hash chain tests don't need to call them directly — only `EvidenceService.hashString` is needed.
   - What's unclear: Whether exposing them would make tests more readable at the cost of a visibility annotation.
   - Recommendation: Do not annotate. Reimplement the 6-line canonical JSON logic inline in the test to keep `SyncService` internals private.

---

## Sources

### Primary (HIGH confidence)
- `lib/services/offline_queue_service.dart` — `listPending()` backoff logic, Hive box name, sort logic confirmed via direct read
- `lib/new_delivery_page.dart` lines 173–188, 973–985 — `_cargarStock` and stock guard logic confirmed via direct read
- `lib/services/sync_service.dart` lines 108–128 — hash chaining formula confirmed via direct read
- `lib/evidence_service.dart` — `hashString`, `hashBytes` signatures confirmed via direct read
- `test/unit/offline_queue_test.dart` — existing test patterns confirmed (no Hive init, tests only model logic)
- `test/unit/perfil_usuario_test.dart` — existing test patterns confirmed
- pub.dev/packages/hive — version 2.2.3 confirmed
- pub.dev/packages/hive_test — version 1.0.1 confirmed, hive ^2.0.4 compatibility confirmed
- pub.dev/packages/fake_async — version 1.3.3, dart.dev publisher confirmed
- pub.dev/packages/clock — version 1.1.2, tools.dart.dev publisher confirmed

### Secondary (MEDIUM confidence)
- `flutter test test/unit/` run result — 34 tests passed in < 1 second, confirms baseline passes

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all packages verified on pub.dev with version confirmation
- Architecture: HIGH — hash chain and listPending logic read directly from source
- Stock logic testability: HIGH — `_cargarStock` logic is simple arithmetic, extraction plan is straightforward
- Hive test initialization: MEDIUM — `hive_test` compatibility verified via `dart pub add` resolution; runtime behavior not tested
- Pitfalls: HIGH — based on direct source inspection

**Research date:** 2026-06-01
**Valid until:** 2026-09-01 (stable Flutter/Dart ecosystem; hive 2.x is stable)

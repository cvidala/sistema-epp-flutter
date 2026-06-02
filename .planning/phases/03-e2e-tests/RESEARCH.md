# Phase 3: E2E Tests — Research

**Researched:** 2026-06-01
**Domain:** Flutter integration testing, offline-first E2E flows, dual-entry-point apps
**Confidence:** HIGH for testing framework decisions; MEDIUM for offline simulation patterns; LOW for E2E-05 web dashboard approach

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| E2E-01 | Login flow → obras → trabajadores loads without console errors | `integration_test` + `testWidgets` with real Supabase; pump LoginPage → authenticate → verify ObrasPage |
| E2E-02 | EPP delivery online — item selection, signature, confirmation | `testWidgets` drive NewDeliveryPage flow; mock camera/GPS plugins; assert Supabase insert via real DB |
| E2E-03 | Offline sync — delivery saved in Hive, syncs on connectivity restore | Hive-backed state + override `_testConnectivity` via injectable; assert queue PENDING → SENT transition |
| E2E-04 | Kiosko attendance — RUT input, photo capture, successful record | Separate test file pumping `AsistenciaApp` from `main_asistencia.dart`; drive `RutInputScreen` |
| E2E-05 | Dashboard shows updated stock after delivery | Out-of-scope for Flutter `integration_test`; web dashboard at trazapp.cl is HTML/JS, not Flutter — recommend Dart HTTP assertion or manual verification |
</phase_requirements>

---

## Summary

Phase 3 needs E2E coverage for five critical flows. Four of them (E2E-01 through E2E-04) live entirely in Flutter and can be exercised with `integration_test` + `testWidgets`, using `pumpWidget()` to launch the correct app root widget for each entry point. E2E-05 targets the external web dashboard at trazapp.cl, which is a separate HTML/JS application — it cannot be driven by Flutter's `integration_test` and should instead be validated with a Dart HTTP assertion that queries Supabase directly after a delivery.

The key architectural constraint is that this project has **two independent Flutter entry points**: `main.dart` (EPP app, email-authenticated users) and `main_asistencia.dart` (kiosk, anon key). Integration tests handle this by having two test files — `integration_test/epp_app_test.dart` and `integration_test/kiosko_test.dart` — each pumping its own root widget (`MyApp` vs `AsistenciaApp`) without touching the `main()` function.

Offline simulation (E2E-03) is the hardest requirement. `ConnectivityService._testConnectivity()` probes Supabase directly — there is no OS-level network toggle in Flutter integration tests. The recommended approach is to introduce a `connectivityOverride` injectable parameter or extract the connectivity probe into a testable method so tests can force `false` (offline) then `true` (online) states without actually cutting the network.

All four Flutter E2E tests can run on macOS desktop via `flutter test integration_test/ -d macos` — no emulator required. They hit the real Supabase production backend (consistent with Phase 2's decision to test against the real DB).

**Primary recommendation:** Use `integration_test` (SDK package) + `testWidgets` with real Supabase backend. Implement thin seam in `ConnectivityService` for offline simulation. Treat E2E-05 as a Dart HTTP assertion, not a UI test.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| E2E-01: Login flow | Flutter UI (LoginPage) | Supabase Auth | LoginPage calls Supabase.auth; test drives UI, asserts navigation to ObrasPage |
| E2E-02: EPP delivery | Flutter UI (NewDeliveryPage) | Supabase DB + Storage | UI drives form; Supabase receives insert; test mocks camera/GPS plugins, uses real DB |
| E2E-03: Offline sync | Service layer (ConnectivityService + SyncService) | Hive persistence | No UI interaction needed; service-layer integration test with injectable connectivity probe |
| E2E-04: Kiosk attendance | Flutter UI (RutInputScreen) | AsistenciaHiveService + Supabase | Different root widget; drives RUT entry; camera plugin must be mocked |
| E2E-05: Dashboard stock | External web (trazapp.cl) | Supabase DB (read) | HTML/JS app, not Flutter; validate via Dart Supabase query, not UI automation |

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `integration_test` | SDK (bundled with Flutter 3.x) | Flutter E2E test harness | Official SDK package; replaced deprecated `flutter_driver`; uses same `testWidgets` API as widget tests [CITED: docs.flutter.dev/testing/integration-tests] |
| `flutter_test` | SDK (bundled) | Test assertions, `WidgetTester`, `find.*` | Already in pubspec; same API surface used in Phases 1 and 2 [VERIFIED: pubspec.yaml] |
| `hive_test` | 1.0.1 | In-memory Hive for integration tests (setUpTestHive / tearDownTestHive) | Already in dev_dependencies; used in Phase 1 unit tests [VERIFIED: pubspec.yaml] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `mockito` | ^5.4.x [ASSUMED] | Mock SupabaseClient, camera, GPS for isolated flows | E2E-02, E2E-04 where camera/GPS plugins cannot run in test environment |
| `build_runner` | ^2.x [ASSUMED] | Code generation for Mockito `@GenerateMocks` | Required alongside mockito for null-safe Dart mock generation |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `integration_test` (SDK) | `patrol` (LeanCode) | patrol adds native platform UI interaction (permission dialogs, notifications) — not needed here since we only test app-layer flows; adds dependency on third-party package |
| Real Supabase backend | Local Supabase via CLI | Consistent with Phase 2 decision to test against real DB; local Supabase requires Docker + additional setup |
| Dart HTTP assertion for E2E-05 | Selenium/Playwright for trazapp.cl | Full browser automation adds heavy CI dependency for a single stock check; Dart assertion via Supabase client is sufficient to verify the data surface |

**Installation (additions to pubspec.yaml dev_dependencies):**
```yaml
dev_dependencies:
  integration_test:
    sdk: flutter
  flutter_test:
    sdk: flutter      # already present
  hive_test: ^1.0.1   # already present
  mockito: ^5.4.4     # add
  build_runner: ^2.4.9 # add
```

**Version verification:** `integration_test` and `flutter_test` are SDK packages — no separate pub version. `hive_test: ^1.0.1` is already in pubspec.lock. `mockito` and `build_runner` versions are [ASSUMED] from training knowledge — verify with `dart pub outdated` before adding.

---

## Package Legitimacy Audit

> slopcheck was not available in this environment. All non-SDK packages are tagged [ASSUMED].

| Package | Registry | Notes | slopcheck | Disposition |
|---------|----------|-------|-----------|-------------|
| `integration_test` | Flutter SDK | Part of Flutter SDK, no separate registry entry | N/A — SDK package | Approved |
| `flutter_test` | Flutter SDK | Part of Flutter SDK | N/A — SDK package | Approved |
| `hive_test` | pub.dev | Already in pubspec.lock from Phase 1 | N/A — pre-existing | Approved |
| `mockito` | pub.dev | Google-authored, widely used in Flutter ecosystem | [ASSUMED] — verify | Flagged — confirm identity before install |
| `build_runner` | pub.dev | Google-authored, standard Dart tooling | [ASSUMED] — verify | Flagged — confirm identity before install |

**Packages flagged as [ASSUMED]:** `mockito`, `build_runner` — planner must add a verification step before `flutter pub add` for these two packages.

**Note:** If mockito integration is complex, Phase 3 can avoid codegen entirely by using manual fake classes (Dart `implements`). The offline sync test (E2E-03) and login test (E2E-01) do not require mockito at all — they can use real Supabase. Only E2E-02 and E2E-04 need camera/GPS mocking.

---

## Architecture Patterns

### System Architecture Diagram

```
E2E Test File (integration_test/)
         │
         │ tester.pumpWidget(MyApp())         ← for E2E-01, E2E-02, E2E-03
         │ tester.pumpWidget(AsistenciaApp()) ← for E2E-04
         │
         ▼
Flutter Widget Tree (UI Layer)
  LoginPage → ObrasPage → WorkersPage → NewDeliveryPage
  RutInputScreen → CameraCaptureScreen
         │
         │ service calls (direct, not mocked)
         ▼
Service Layer
  AuthService.instance | OfflineQueueService (Hive) | ConnectivityService
  SyncService | AsistenciaHiveService | AsistenciaSyncService
         │
         │ real network calls (except E2E-03 where connectivity is overridden)
         ▼
Supabase (production DB — same as Phase 2)
  Auth | entregas_epp | asistencias | obras | trabajadores
```

### Recommended Project Structure

```
integration_test/
├── epp_app_test.dart          # E2E-01 (login), E2E-02 (delivery), E2E-03 (offline sync)
├── kiosko_test.dart           # E2E-04 (kiosk attendance)
└── helpers/
    ├── test_setup.dart        # initSupabase(), seedTestData(), cleanupTestData()
    └── connectivity_fake.dart # ConnectivityFake implementing testability seam
test/
├── integration/supabase/      # Phase 2 — untouched
└── unit/                      # Phase 1 — untouched
```

### Pattern 1: Dual Entry Point Testing

**What:** Each Flutter entry point has its own root widget. Integration tests call `tester.pumpWidget()` with the specific root widget — NOT `main()`.

**When to use:** Any test that targets a specific app variant (EPP app vs kiosk app).

**Example:**
```dart
// integration_test/epp_app_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:epp_app/main.dart' show MyApp; // ← EPP root widget

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _initServices(); // Hive.initFlutter(), OfflineQueueService.init(), Supabase.initialize()
  });

  testWidgets('E2E-01: login → obras → trabajadores carga sin errores', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    // expect LoginPage visible
  });
}
```

```dart
// integration_test/kiosko_test.dart
import 'package:epp_app/main_asistencia.dart' show AsistenciaApp; // ← Kiosk root widget

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('E2E-04: kiosko — ingreso RUT, registro exitoso', (tester) async {
    await tester.pumpWidget(const AsistenciaApp());
    await tester.pumpAndSettle();
    // RutInputScreen is now loaded
  });
}
```

**Critical note:** The `main()` functions in both entry points call `runApp()`, which cannot be used in tests. Import only the widget class, not `main()`. Source the service initialization in test `setUpAll()` instead.

### Pattern 2: Service Initialization in Tests

**What:** Replicate what `main()` does (Hive init, Supabase init, service init) inside `setUpAll()`.

**When to use:** Every integration test file that exercises service-dependent widgets.

**Example:**
```dart
Future<void> _initServicesEpp() async {
  await Hive.initFlutter();
  await OfflineQueueService.init();
  await CacheService.init();
  await DeviceIdService.init();
  await OfflineCacheService.init();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );
}
```

**Pitfall:** Calling `Supabase.initialize()` a second time after a previous test run throws `AssertionError`. Guard with a check:
```dart
if (Supabase.instance.client == null) {
  await Supabase.initialize(...);
}
// OR use a static bool flag:
bool _initialized = false;
if (!_initialized) { ... _initialized = true; }
```

### Pattern 3: Offline Simulation Seam

**What:** `ConnectivityService._testConnectivity()` does a real Supabase probe — it cannot be blocked via OS firewall in a test. The solution is a thin dependency injection seam.

**When to use:** E2E-03 (offline sync test).

**Implementation options (choose one):**

**Option A — `connectivityProbe` injectable (preferred):**
Add an optional parameter to `ConnectivityService.start()`:
```dart
void start({
  int intervalSeconds = 10,
  VoidCallback? onSyncComplete,
  VoidCallback? onStatusChange,
  // Test seam: override real Supabase probe
  Future<bool> Function()? connectivityProbe,
}) {
  _probe = connectivityProbe ?? _testConnectivity;
  ...
}
Future<bool> Function() _probe = _testConnectivity;
```

Test usage:
```dart
int probeCallCount = 0;
bool simulateOnline = false;

ConnectivityService.instance.start(
  connectivityProbe: () async {
    probeCallCount++;
    return simulateOnline;
  },
);

// Delivery queued offline
await OfflineQueueService.enqueue(testEntrega);
expect(OfflineQueueService.listPending(), hasLength(1));

// Simulate coming back online
simulateOnline = true;
await Future.delayed(const Duration(seconds: 1)); // let timer fire
// assert SENT
```

**Option B — Direct SyncService call (simpler, bypasses timer):**
For E2E-03, skip ConnectivityService entirely. Enqueue a delivery, then call `SyncService.syncOnce()` directly with a real Supabase client. Assert the delivery reaches Supabase. This tests the sync path without needing to simulate connectivity detection.

**Recommendation: Option B for Phase 3.** It's simpler, avoids modifying production code, and directly validates the sync path that matters. The ConnectivityService detection logic is thin and already tested implicitly by the timer poll calling `_testConnectivity()` + `_runSync()`.

### Pattern 4: Camera and GPS in Integration Tests

**What:** `NewDeliveryPage` and `RutInputScreen` invoke camera plugin and geolocator. These hardware plugins fail in test environments.

**When to use:** E2E-02, E2E-04 — any test that drives screens requiring camera.

**Approach:** Use `testWidgets` to navigate to the screen but skip the actual camera capture step. Instead:
1. Provide pre-built image bytes for `evidenciaBytes` via a `ValueKey`-tagged bypass button, OR
2. Use `tester.tap()` to trigger the camera capture route but immediately `await tester.pumpAndSettle()` — the plugin will throw a `MissingPluginException` or return empty; catch it and continue the test flow.
3. Preferred: Abstract camera capture behind a service interface (`CaptureService`) and inject a fake in tests that returns fixture bytes.

**Note:** `google_mlkit_face_detection` is on-device and will not run in the macOS test host environment (it's an Android/iOS native plugin). E2E-04 must either mock the ML Kit result or skip face detection assertion and only verify RUT entry + Hive record creation.

### Anti-Patterns to Avoid

- **Calling `main()` from test files:** `runApp()` conflicts with `tester.pumpWidget()`. Always import only the root widget class.
- **Sharing Hive state across tests:** Use `setUpTestHive()` / `tearDownTestHive()` (from `hive_test`) or fresh temporary directories between test groups.
- **Asserting on raw Supabase rows without test isolation:** Use test-prefixed IDs (e.g., `'test_e2e_${uuid}'`) and clean up in `tearDown`/`tearDownAll` — consistent with Phase 2's `kTestPrefix = 'test_qa_'` pattern.
- **Waiting with `Future.delayed()` instead of `tester.pumpAndSettle()`:** `pumpAndSettle()` drives the Flutter event loop; raw delays are flaky in test environments.
- **Asserting against `Supabase.instance.client` in tests:** Phase 2 established the pattern of creating isolated `SupabaseClient(url, key)` instances. E2E tests that verify DB state should use a service-role client from `test_client.dart`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Integration test harness | Custom test runner | `integration_test` (SDK) | SDK package handles binding initialization, `pumpWidget`, `pumpAndSettle`, device-level execution |
| In-memory Hive for tests | Custom Hive mock | `hive_test` (`setUpTestHive`/`tearDownTestHive`) | Already in pubspec; Phase 1 uses it successfully; provides isolated temp directory per test run |
| Supabase test clients | Custom auth wrapper | `test/integration/supabase/helpers/test_client.dart` (Phase 2) | Already built with `clientForRole()`, `serviceClient()`, `anonClient()` — reuse directly |
| Test data cleanup | Ad-hoc delete loops | `test_data.dart` `TestDataHelper` (Phase 2) | Already built; use `kTestPrefix` for row identification |
| Fake connectivity | OS-level firewall | Injectable probe seam OR direct `SyncService.syncOnce()` call | OS firewall toggling is not possible in Flutter integration tests; seam is the correct approach |

**Key insight:** Phases 1 and 2 already built most of the test infrastructure. Phase 3 reuses `test_client.dart`, `test_data.dart`, `hive_test`, and the `kTestPrefix` convention — it does not rebuild them.

---

## Common Pitfalls

### Pitfall 1: Supabase Already Initialized

**What goes wrong:** `Supabase.initialize()` called in `setUpAll()` throws `AssertionError: Supabase has already been initialized` on the second test run or when two test files run in the same process.

**Why it happens:** `Supabase.initialize()` is a singleton initializer. Integration test files may share a process.

**How to avoid:** Wrap with a try-catch or check `Supabase.instance` before initializing:
```dart
try {
  await Supabase.initialize(url: ..., anonKey: ...);
} catch (_) {
  // Already initialized in a previous test group — safe to continue
}
```

**Warning signs:** `AssertionError` or `StateError: Supabase has already been initialized` in first line of setUpAll.

### Pitfall 2: `pumpAndSettle()` Timeout on Async Network Calls

**What goes wrong:** `tester.pumpAndSettle()` times out (default 100ms per pump, max 10 seconds total) when the widget is waiting for a Supabase query that takes 500ms–2000ms.

**Why it happens:** Real network calls take longer than the `pumpAndSettle` default settling threshold.

**How to avoid:** Use a longer timeout:
```dart
await tester.pumpAndSettle(const Duration(seconds: 5));
// Or pump manually:
await tester.pump(const Duration(seconds: 3));
await tester.pumpAndSettle();
```

**Warning signs:** `FlutterError: Settled but there is still pending activity` or timeout failures in tests that hit real Supabase.

### Pitfall 3: MissingPluginException for Camera/GPS/MLKit

**What goes wrong:** `NewDeliveryPage` or `RutInputScreen` attempt to call the `camera`, `geolocator`, or `google_mlkit_face_detection` plugins. In macOS desktop integration tests, these plugins are not registered.

**Why it happens:** These are mobile platform plugins (Android/iOS). The macOS test host does not have the corresponding platform implementations.

**How to avoid:** 
- Add `@Skip('requires Android/iOS device')` to camera-dependent subtests
- OR abstract camera/GPS behind a service interface with a fake implementation for tests
- For E2E-04: test RUT validation logic and `AsistenciaHiveService.guardar()` directly; skip camera capture step

**Warning signs:** `MissingPluginException(No implementation found for method...)` in test output.

### Pitfall 4: ML Kit Face Detection on macOS Test Host

**What goes wrong:** `google_mlkit_face_detection` is an Android/iOS native plugin. It has no macOS implementation.

**Why it happens:** `camera_capture_screen.dart` calls ML Kit to validate face presence. Calling this on macOS desktop throws.

**How to avoid:** For E2E-04, the test should stop at `RutInputScreen` level (enter RUT, tap "Siguiente"), then assert a `AsistenciaPendiente` was queued in Hive — bypassing the camera screen entirely OR using a fake `CameraCaptureScreen` in the test that returns fixture data.

**Warning signs:** Build error or `MissingPluginException` mentioning `google_mlkit_face_detection`.

### Pitfall 5: entregas_epp Rows Created in E2E-02 Are Permanent

**What goes wrong:** Phase 2 established that `trg_entregas_epp_immutable` + `BEFORE DELETE` trigger blocks ALL deletes from `entregas_epp`, including service_role. E2E test deliveries inserted into the real DB are permanent.

**Why it happens:** Intentional immutability constraint for legal compliance (documented in SECURITY-FINDINGS.md as SF-02).

**How to avoid:** Use a unique `local_event_id` prefix (e.g., `'test_e2e_'`) so test rows are identifiable. Accept they are permanent. Do not write cleanup logic that will always fail. For E2E-02, optionally keep the delivery in PENDING status in Hive without syncing to Supabase — test the Hive enqueue path, then separately test the sync path with direct `SyncService.syncOnce()` and accept the permanent row.

**Warning signs:** `tearDownAll` throwing `PostgrestException: Eliminación de entregas no permitida`.

### Pitfall 6: Hive Box Already Open Error

**What goes wrong:** `OfflineQueueService.init()` calls `Hive.openBox('outbox_entregas')`. If `setUpAll()` runs twice (two test groups in same file), the second `init()` throws because the box is already open.

**Why it happens:** Hive does not re-open an already-open box gracefully in all versions.

**How to avoid:** Guard with:
```dart
if (!Hive.isBoxOpen('outbox_entregas')) {
  await OfflineQueueService.init();
}
```
Or use `hive_test`'s `setUpTestHive()` which creates a fresh temporary directory for each test group, preventing shared state.

---

## Code Examples

### E2E-01: Login Flow

```dart
// integration_test/epp_app_test.dart
// Source: docs.flutter.dev/testing/integration-tests

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:epp_app/main.dart' show MyApp, LoginPage;
import 'package:epp_app/obras_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => _initServices());

  group('E2E-01: Login flow', () {
    testWidgets('login exitoso navega a ObrasPage sin errores de consola', (tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Should start on LoginPage (no cached session)
      expect(find.byType(LoginPage), findsOneWidget);

      // Enter credentials
      await tester.enterText(find.byKey(const ValueKey('email_field')),
          const String.fromEnvironment('TEST_ADMIN_EMAIL', defaultValue: 'test_admin@trazapp.cl'));
      await tester.enterText(find.byKey(const ValueKey('password_field')),
          const String.fromEnvironment('TEST_ADMIN_PASSWORD', defaultValue: 'TestAdmin2026!'));

      await tester.tap(find.text('Ingresar'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Verify navigation to ObrasPage
      expect(find.byType(ObrasPage), findsOneWidget);
    });
  });
}
```

**Note:** LoginPage widgets need `ValueKey` identifiers added to the `TextField` widgets. This is a source change that the planner must schedule.

### E2E-03: Offline Sync (Option B — Direct SyncService)

```dart
// Source: pattern derived from ConnectivityService._runSync() in lib/services/connectivity_service.dart

group('E2E-03: Offline sync', () {
  setUp(() async {
    await setUpTestHive();
    await OfflineQueueService.init();
  });

  tearDown(() async {
    await tearDownTestHive();
  });

  test('entrega guardada en Hive aparece como PENDING y hace sync a Supabase', () async {
    // 1. Enqueue a delivery while "offline" (no ConnectivityService running)
    final testId = 'test_e2e_${const Uuid().v4()}';
    await OfflineQueueService.enqueue(OfflineEntrega(
      localEventId: testId,
      createdAtClientIso: DateTime.now().toIso8601String(),
      scope: 'EPP',
      obraId: testObraId,          // seeded in setUpAll
      trabajadorId: testTrabId,
      bodegaId: testBodegaId,
      items: [{'epp_id': testEppId, 'cantidad': 1}],
      evidenciaLocalPath: 'test_fixtures/foto.jpg',
      evidenciaHash: 'testhash',
    ));

    // 2. Verify PENDING in queue
    final pending = OfflineQueueService.listPending();
    expect(pending.any((e) => e.localEventId == testId), isTrue);
    expect(pending.first.status, equals('PENDING'));

    // 3. "Come back online" — call SyncService directly
    final supabase = SupabaseClient(SupabaseConfig.url, SupabaseConfig.anonKey);
    await supabase.auth.signInWithPassword(email: testAdminEmail, password: testAdminPass);
    final sync = SyncService(supabase: supabase, deviceId: 'test-device');
    await sync.syncOnce();

    // 4. Verify SENT in queue
    final all = OfflineQueueService.listAll();
    final synced = all.firstWhere((e) => e.localEventId == testId);
    expect(synced.status, equals('SENT'));
  });
});
```

### E2E-04: Kiosk Entry Point

```dart
// integration_test/kiosko_test.dart
import 'package:epp_app/main_asistencia.dart' show AsistenciaApp;
import 'package:epp_app/asistencia/screens/rut_input_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => _initServicesAsistencia()); // Hive + AsistenciaHiveService + Supabase

  group('E2E-04: Kiosko asistencia', () {
    testWidgets('RutInputScreen visible al iniciar AsistenciaApp', (tester) async {
      await tester.pumpWidget(const AsistenciaApp());
      await tester.pumpAndSettle();

      expect(find.byType(RutInputScreen), findsOneWidget);
    });

    testWidgets('ingreso RUT válido habilita botón Siguiente', (tester) async {
      await tester.pumpWidget(const AsistenciaApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('rut_field')), '12.345.678-9');
      await tester.pumpAndSettle();

      // Siguiente button should be enabled (or RUT validation visible)
      expect(find.text('Siguiente'), findsOneWidget);
      // Note: camera capture step skipped — MissingPluginException on macOS
    });
  });
}
```

---

## E2E-05: Web Dashboard — Special Case

**The trazapp.cl dashboard is NOT a Flutter app.** It is served from `dashboard/` as static HTML/JS. `integration_test` cannot drive it.

**Recommended approach for E2E-05:** Write a Dart integration test that:
1. Performs a delivery (or uses a seeded one from E2E-02)
2. Queries the Supabase DB for the resulting stock movement via a `service_role` client
3. Asserts the stock balance changed as expected

This validates the data that the dashboard reads, without automating the dashboard UI itself.

```dart
// integration_test/epp_app_test.dart — E2E-05 section

test('E2E-05: stock atualizado en DB despues de entrega (dashboard refleja esto)', () async {
  // Query stock before
  final stockBefore = await serviceClient()
    .from('stock_movimientos')
    .select()
    .eq('bodega_id', testBodegaId)
    .eq('epp_id', testEppId);

  // (Delivery performed in E2E-02 or a fresh one here)

  // Query stock after
  final stockAfter = await serviceClient()
    .from('stock_movimientos')
    .select()
    .eq('bodega_id', testBodegaId)
    .eq('epp_id', testEppId);

  expect(stockAfter.length, greaterThan(stockBefore.length));
});
```

**Note:** If the dashboard must be visually tested, that requires a separate tool (Playwright, Cypress, or manual verification) and is out of scope for Phase 3 per the project's "no visual screenshot testing" constraint.

---

## Runtime State Inventory

> This is not a rename/refactor phase. Section omitted.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `flutter_driver` (legacy) | `integration_test` (SDK) | Flutter 2.5+ (2021) | Simpler API, same `testWidgets` surface, better CI support [CITED: docs.flutter.dev/testing/integration-tests/migration] |
| `flutter drive --target` for all devices | `flutter test integration_test/` for desktop | Flutter 3.x | macOS/Linux/Windows can run integration tests without emulator [CITED: docs.flutter.dev/testing/integration-tests] |

**Deprecated/outdated:**
- `flutter_driver`: Officially deprecated in favor of `integration_test`. Do not add `flutter_driver` to pubspec.
- `test_driver/main.dart` pattern: Replaced by direct `flutter test integration_test/` — no driver file needed for desktop tests.

---

## Open Questions (RESOLVED)

1. **ValueKey coverage on LoginPage text fields**
   - What we know: LoginPage uses `TextField` with `emailCtrl`/`passCtrl` but no `ValueKey` identifiers on the widgets
   - What's unclear: Whether `find.byType(TextField).first/.last` is stable enough for E2E-01, or if `ValueKey` must be added
   - Recommendation: Add `key: const ValueKey('email_field')` and `key: const ValueKey('password_field')` to `LoginPage` TextFields — small production code change required

2. **RutInputScreen ValueKey for RUT text field**
   - What we know: `_RutFormatter` is applied to a `TextFormField` in `RutInputScreen`; no `ValueKey` observed in first 80 lines
   - What's unclear: Whether `find.byType(TextFormField)` is sufficient in E2E-04
   - Recommendation: Add `key: const ValueKey('rut_field')` to the RUT input widget

3. **Test credentials for integration tests**
   - What we know: Phase 2 uses `test_admin@trazapp.cl` / `TestAdmin2026!` via `test_client.dart`
   - What's unclear: Whether the same test users have sufficient obra/trabajador/EPP seed data for E2E-02 delivery flow
   - Recommendation: Verify test_admin has at least one obra with one trabajador and one EPP with stock before finalizing E2E-02

4. **SyncService evidencia file path in test environment**
   - What we know: `SyncService.syncOnce()` calls `EvidenceService.readEvidenceOffline(e.evidenciaLocalPath)` which reads from disk
   - What's unclear: Whether a fixture image file at `test_fixtures/foto.jpg` can be referenced in integration tests
   - Recommendation: Include a small test fixture image in `test/fixtures/` and use `flutter test --dart-define=TEST_EVIDENCE_PATH=...` or path_provider temp directory

5. **E2E-05 scope alignment**
   - What we know: Success criterion 5 in ROADMAP.md says "dashboard shows updated stock" — but the dashboard is HTML/JS at trazapp.cl
   - What's unclear: Whether the acceptance criterion is satisfied by a Dart DB assertion (verifying data) vs. visual browser verification
   - Recommendation: Treat as data assertion (Dart Supabase query confirms stock movement record exists); note limitation in PLAN.md

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| macOS desktop target | `flutter test -d macos` | Likely ✓ | Darwin 25.5.0 confirmed | Use emulator if macOS flutter support disabled |
| Supabase production DB | All E2E tests | ✓ | `ppltpmmtdnprgauwnytf` (Phase 2 confirmed working) | None — project policy is real DB |
| Flutter SDK | All tests | Assumed ✓ [ASSUMED] | 3.x | N/A |
| `hive_test` | E2E-03 Hive setup | ✓ | 1.0.1 (in pubspec.lock) | None needed |
| Camera hardware | E2E-02, E2E-04 | ✗ (not available on macOS test host) | N/A | Mock/skip camera step in tests |
| `google_mlkit_face_detection` | E2E-04 face validation | ✗ (iOS/Android only) | N/A | Skip face detection assertion; test only RUT + Hive record |
| GPS / `geolocator` | E2E-02 forensic capture | ✗ (not available on macOS test host) | N/A | Forensic data optional (null GPS fields acceptable per ARCHITECTURE.md) |

**Missing dependencies with no fallback:** None that block Phase 3 entirely.

**Missing dependencies with fallback (camera/GPS/MLKit):** Test design must skip hardware-dependent steps. Documented in Pitfalls 3 and 4.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `flutter_test` (SDK) + `integration_test` (SDK) |
| Config file | none — `flutter test` auto-discovers `integration_test/` directory |
| Quick run command | `flutter test integration_test/epp_app_test.dart -d macos` |
| Full suite command | `flutter test integration_test/ -d macos` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| E2E-01 | Login → ObrasPage loads without unhandled exceptions | integration (widget-level) | `flutter test integration_test/epp_app_test.dart -d macos` | ❌ Wave 0 |
| E2E-02 | EPP delivery enqueued online, reaches Supabase | integration (service+UI) | `flutter test integration_test/epp_app_test.dart -d macos` | ❌ Wave 0 |
| E2E-03 | Hive PENDING → SyncService → Supabase SENT transition | integration (service-layer) | `flutter test integration_test/epp_app_test.dart -d macos` | ❌ Wave 0 |
| E2E-04 | AsistenciaApp pumps RutInputScreen; RUT entry works | integration (widget-level) | `flutter test integration_test/kiosko_test.dart -d macos` | ❌ Wave 0 |
| E2E-05 | Stock movement record exists in DB after delivery | integration (DB assertion) | `flutter test integration_test/epp_app_test.dart -d macos` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `flutter analyze` (fast, no device needed)
- **Per wave merge:** `flutter test integration_test/ -d macos`
- **Phase gate:** Full suite green + `flutter test test/unit/ test/integration/supabase/` (Phases 1+2 regression check)

### Wave 0 Gaps

- [ ] `integration_test/epp_app_test.dart` — covers E2E-01, E2E-02, E2E-03, E2E-05
- [ ] `integration_test/kiosko_test.dart` — covers E2E-04
- [ ] `integration_test/helpers/test_setup.dart` — service initialization helpers
- [ ] Add `integration_test: { sdk: flutter }` to `pubspec.yaml` dev_dependencies
- [ ] Add `ValueKey` identifiers to `LoginPage` TextFields (source change)
- [ ] Add `ValueKey` identifier to `RutInputScreen` RUT TextField (source change)

---

## Security Domain

> `security_enforcement: true` in `.planning/config.json`. ASVS Level 1 applies.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | Yes | Test credentials use email/password via Supabase Auth; tests use same test accounts as Phase 2 (`test_admin@trazapp.cl`) |
| V3 Session Management | Partial | Integration tests create isolated `SupabaseClient` instances (Phase 2 pattern) — no session contamination |
| V4 Access Control | No | RLS tested in Phase 2; E2E tests use admin account and do not re-test RLS |
| V5 Input Validation | Yes | E2E-04 drives `_RutFormatter` — test validates RUT format constraint |
| V6 Cryptography | No | Hash chain tested in Phase 1 unit tests; E2E-02 sync will exercise it end-to-end implicitly |

### Known Threat Patterns for This Phase

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Test credentials in source code | Information Disclosure | Phase 2 pattern: `Platform.environment` lookup with fallback to hardcoded test-only accounts; test credentials have no access to real worker/client data |
| Permanent test rows in `entregas_epp` | Tampering (test pollution) | Use `kTestPrefix` (`test_e2e_`) for `local_event_id`; accept permanence per SF-02; do not attempt cleanup |
| Integration tests hitting production DB | Availability | Phase 2 established this is acceptable; test users are scoped to test obras with no real workers |

---

## Project Constraints (from CLAUDE.md)

| Directive | Source | Impact on Phase 3 |
|-----------|--------|-------------------|
| Tests against real Supabase DB (no mocks) | PROJECT.md Key Decisions | E2E tests use production Supabase — consistent with Phase 2; no local mock DB |
| No screenshot/pixel-perfect visual testing | PROJECT.md Out of Scope | E2E-05 dashboard cannot use visual browser automation — use Dart DB assertion instead |
| `StatefulWidget + State` pattern (no Provider/Bloc/Riverpod) | CLAUDE.md Conventions | No special state management setup needed in tests; `pumpWidget` + `setState` is sufficient |
| Naming: `_test.dart` suffix, camelCase methods | CLAUDE.md Conventions | Test files: `epp_app_test.dart`, `kiosko_test.dart`; test methods: `testWidgets('login exitoso...', ...)` |
| `debugPrint` with service prefix for logging | CLAUDE.md Conventions | Test helpers should follow: `debugPrint('[E2ESetup] Initialized services')` |
| `import` using relative paths | CLAUDE.md Conventions | `import 'package:epp_app/main.dart'` (package-relative) for integration tests |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `flutter test integration_test/ -d macos` works on this macOS 25.5.0 machine without installing additional SDKs | Environment Availability | Integration tests may need `flutter config --enable-macos-desktop` first; runner must verify |
| A2 | `mockito: ^5.4.4` and `build_runner: ^2.4.9` are correct current versions | Standard Stack | Wrong version in pubspec could fail `flutter pub get`; verify with `dart pub outdated` |
| A3 | Phase 2 test users (`test_admin@trazapp.cl`) have seed data sufficient for E2E-02 (at least one obra, one trabajador, one EPP with stock) | Open Questions #3 | E2E-02 delivery test will fail at data setup step if no valid obra/trabajador/EPP combo exists |
| A4 | E2E-05 acceptance criterion is satisfied by a Supabase DB assertion (not visual browser verification) | E2E-05 Special Case | If stakeholder requires visual dashboard verification, Playwright or manual testing needed |
| A5 | `main_asistencia.dart` can be imported in integration tests by importing only `AsistenciaApp` class | Pattern 1 | If `main_asistencia.dart` has top-level side effects outside `main()`, importing it may break; inspect file (already read — clean) |

---

## Sources

### Primary (HIGH confidence)
- `docs.flutter.dev/testing/integration-tests` — integration_test setup, `testWidgets`, `pumpWidget`, `pumpAndSettle`, desktop execution [CITED]
- `docs.flutter.dev/testing/integration-tests/migration` — flutter_driver → integration_test migration guide, confirms integration_test is current standard [CITED]
- `lib/services/connectivity_service.dart` — source-confirmed: `_testConnectivity()` probes Supabase directly, no OS-level hook [VERIFIED: codebase]
- `lib/services/offline_queue_service.dart` — source-confirmed: Hive box name `'outbox_entregas'`, `listPending()` filter logic [VERIFIED: codebase]
- `lib/main_asistencia.dart` — source-confirmed: `AsistenciaApp` is the root widget, `main()` only calls `runApp()` after Hive+Supabase init [VERIFIED: codebase]
- `pubspec.yaml` — source-confirmed: `hive_test: ^1.0.1` already in dev_dependencies; `integration_test` not yet added [VERIFIED: codebase]
- `test/integration/supabase/helpers/test_client.dart` — Phase 2 helper confirmed: `clientForRole()`, `serviceClient()`, `anonClient()` patterns reusable [VERIFIED: codebase]
- `.planning/phases/02-supabase-tests/02-01-SUMMARY.md` — confirmed: `entregas_epp` BEFORE DELETE trigger blocks all deletes including service_role (SF-02) [VERIFIED: codebase]

### Secondary (MEDIUM confidence)
- `docs.flutter.dev/cookbook/testing/unit/mocking` — Mockito usage pattern for Flutter null-safe Dart [CITED]
- `docs.flutter.dev/testing/integration-tests` — macOS desktop: `flutter test integration_test/` works on host machine [CITED]

### Tertiary (LOW confidence)
- Offline simulation via injectable probe (Option A) — derived from analysis of `ConnectivityService` source; no official Flutter docs confirm this specific pattern [ASSUMED]

---

## Metadata

**Confidence breakdown:**
- Standard stack (integration_test, flutter_test, hive_test): HIGH — SDK packages confirmed in official docs; hive_test confirmed in pubspec
- Architecture (dual entry point, pumpWidget pattern): HIGH — confirmed from source reading of main.dart and main_asistencia.dart
- Offline simulation approach: MEDIUM — derived from connectivity_service.dart source analysis; Option B (direct SyncService call) is well-grounded; Option A requires production code modification
- E2E-05 web dashboard: HIGH (scope decision) — confirmed from project files that trazapp.cl is not Flutter
- mockito/build_runner versions: LOW — training knowledge only; must verify

**Research date:** 2026-06-01
**Valid until:** 2026-07-01 (stable framework — integration_test API is not fast-moving)

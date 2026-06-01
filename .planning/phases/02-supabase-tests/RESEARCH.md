# Phase 2: Supabase Tests — Research

**Researched:** 2026-06-01
**Domain:** Supabase RLS testing, PostgreSQL triggers, RPCs, Dart/Flutter integration tests
**Confidence:** HIGH (stack confirmed via codebase inspection; patterns verified via official Supabase docs)

---

## Summary

Phase 2 must test 13 requirements against the **live Supabase production database** (`ppltpmmtdnprgauwnytf`). The project already established this as a locked decision in PROJECT.md: "Tests Supabase contra DB real (no mocks) — hubo incidentes por divergencia mock/prod; el RLS y triggers solo se validan en real."

Two viable approaches exist: **(A) Dart client tests** using `supabase_flutter` with per-role JWT tokens, and **(B) SQL pgTAP tests** using `supabase test db` with the `basejump-supabase_test_helpers` library. This research recommends **a hybrid**: pgTAP for RLS and trigger behavior (correct layer, fast, self-documenting SQL), and Dart client tests for RPC calls (since `evaluar_entrega_v2` is called from Dart, and the return shape is Dart-typed). The Dart tests authenticate by signing in as real test users (email/password via `signInWithPassword`) rather than constructing synthetic JWTs, which avoids the JWT secret exposure problem and matches how the real app works.

Test data isolation on a no-DELETE database is solved by: (1) using unique sentinel values (e.g., `test_` prefix on `local_event_id`) and (2) wrapping pgTAP tests in `BEGIN`/`ROLLBACK` transactions. Dart tests use service_role cleanup via a separate cleanup client, calling `service_role` key bypass for `DELETE` at the end of each test group.

**Primary recommendation:** pgTAP + `supabase test db` for RLS and trigger tests; Dart `flutter_test` with real user sign-in for RPC tests. Both test layers share the same live production database and test user accounts pre-created by the setup script.

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| RLS-01 | ADMIN ve todos los trabajadores de todas las obras | `select_trabajadores` policy: `rol = 'ADMIN'` branch — test via service_role-created ADMIN user |
| RLS-02 | SUPERVISOR solo ve trabajadores de sus obras (obra_usuarios) | `select_trabajadores` JOIN `obra_usuarios` branch — create supervisor assigned to one obra only |
| RLS-03 | READONLY no puede insertar entregas EPP | `insert_own_entregas` WITH CHECK: `entregado_por = auth.uid()` — READONLY user attempts INSERT |
| RLS-04 | Anon puede insertar asistencias pero no leer | `insert_anon_asistencias TO anon` + no SELECT anon policy — anon key test |
| RLS-05 | Nadie puede eliminar registros de entregas_epp | `no_delete_entregas USING (false)` — all roles attempt DELETE |
| RLS-06 | Nadie puede eliminar registros de asistencias | `no_delete_asistencias USING (false)` — all roles attempt DELETE |
| TRG-01 | `trg_prevent_stock_negativo` bloquea SALIDA con stock < 0 | BEFORE INSERT trigger on stock_movimientos; test with stock=0 then SALIDA |
| TRG-02 | `trg_prevent_stock_negativo` permite SALIDA con stock suficiente | same trigger; ENTRADA 10, SALIDA 5 = stock 5, should succeed |
| TRG-03 | `trg_entregas_epp_immutable` bloquea UPDATE de campos críticos | BEFORE UPDATE trigger on entregas_epp; test UPDATE on items, trabajador_id, obra_id |
| TRG-04 | `trg_audit_entregas_epp` registra INSERT en audit_log | AFTER INSERT trigger; verify audit_log row created with tabla='entregas_epp' |
| TRG-05 | RPC `evaluar_entrega_v2` estado correcto para trabajador con EPP completo | Dart RPC call; need working test data: trabajador + obra + entrega |
| TRG-06 | RPC `evaluar_entrega_v2` estado CRITICO para trabajador sin EPP | Dart RPC call; need trabajador with NO previous entregas |
| TRG-07 | RPC `get_vencimientos_proximos` retorna EPP próximo a vencer | Dart RPC call; needs entrega with `vida_util_dias` such that current_date is close to expiry |
</phase_requirements>

---

## Project Constraints (from CLAUDE.md)

- All workflow changes must go through GSD commands (`/gsd-execute-phase`)
- Code style: 2-space indent, camelCase methods, `_privateMethod` prefix, PascalCase classes
- Services use singleton pattern with static `instance` getter
- Logging: `debugPrint('[ServiceName] message')` with emoji status markers
- Null safety enforced (Dart 3.x)
- No Provider/Bloc/Riverpod — StatefulWidget + State pattern throughout
- Import style: relative paths (e.g., `import 'services/auth_service.dart'`)

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| RLS policy enforcement | Database (PostgreSQL) | — | RLS lives entirely in the DB; only testable against real Postgres |
| Trigger execution | Database (PostgreSQL) | — | BEFORE/AFTER triggers are DB-layer behavior |
| RPC call + return shape | API (Supabase REST) | Client (Dart) | RPCs executed server-side, but return shape validated in Dart |
| Test JWT generation | Client (Dart test) | DB (pgTAP set_config) | Two approaches per test type |
| Test data setup/teardown | Service Role (bypass RLS) | — | Only service_role can DELETE in no-DELETE schema |
| Anon role simulation | Client (anon key) | DB (pgTAP `clear_authentication`) | Anon key must be used for kiosk tests |

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `flutter_test` | SDK bundled | Dart test runner, assertions | Already in pubspec.yaml; used in Phase 1 [VERIFIED: pubspec.yaml] |
| `supabase_flutter` | 2.12.0 (installed) | Supabase client for Dart | Already in project; supports `accessToken` callback [VERIFIED: pubspec.lock] |
| `dart_jsonwebtoken` | 3.4.1 | Sign custom JWTs for per-role test clients | 891K downloads/month, 359 likes, MIT license, active GitHub `jonasroussel/dart_jsonwebtoken` [VERIFIED: pub.dev] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `supabase test db` CLI | Supabase CLI 2.75.0 (installed) | Run pgTAP SQL tests | RLS and trigger tests in SQL layer [VERIFIED: supabase --version] |
| `basejump-supabase_test_helpers` | via dbdev | pgTAP helper functions for auth simulation | Inside pgTAP tests only — provides `tests.authenticate_as()`, `tests.create_supabase_user()` [CITED: github.com/usebasejump/supabase-test-helpers] |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `dart_jsonwebtoken` for custom JWTs | Real `signInWithPassword` auth | Real auth is simpler, no JWT secret needed; custom JWT needed only if test users can't be pre-created |
| pgTAP for RLS | Dart HTTP client with raw REST calls | pgTAP runs server-side (no network overhead, transactional rollback); Dart REST calls require managing auth tokens per test |
| pgTAP `BEGIN`/`ROLLBACK` isolation | Pre/post test cleanup via service_role | `ROLLBACK` is cleaner; service_role DELETE is the fallback for Dart tests |

### Installation
```bash
# dev_dependencies to add to pubspec.yaml
dart pub add --dev dart_jsonwebtoken
```

Note: `flutter_test` is already present. The `http` package (1.6.0) is already a transitive dep of `supabase_flutter` — no extra install needed for REST calls.

---

## Package Legitimacy Audit

> Note: `slopcheck` is Python-focused and flagged `dart_jsonwebtoken` as SLOP when queried against PyPI (correct — it is a Dart package, not a Python package). The correct registry is pub.dev.

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| `dart_jsonwebtoken` | pub.dev | ~4 yrs (created ~2021) | 891K/month (30d) | github.com/jonasroussel/dart_jsonwebtoken | [OK — pub.dev verified] | Approved |
| `flutter_test` | Dart SDK | N/A (SDK bundle) | N/A | dart.dev/flutter | N/A | Approved (bundled) |
| `supabase_flutter` | pub.dev | ~4 yrs | Very high | github.com/supabase/supabase-flutter | N/A | Approved (already installed) |

**Packages removed due to slopcheck [SLOP] verdict:** none (slopcheck's PyPI verdict for `dart_jsonwebtoken` is a false positive — wrong registry; pub.dev confirms package is legitimate)

**Packages flagged as suspicious [SUS]:** none

---

## Architecture Patterns

### System Architecture Diagram

```
Test Suite
    │
    ├── [Dart] test/integration/supabase/
    │       │
    │       ├── setup_test_users.dart      ← service_role creates 4 test users in auth.users
    │       │                                (test_admin@trazapp.test, test_supervisor@trazapp.test,
    │       │                                 test_readonly@trazapp.test, anon = no user)
    │       │
    │       ├── rls_test.dart              ← Each test: signInWithPassword → get JWT → SupabaseClient
    │       │   (RLS-01..06)                  → query/insert/delete → assert error or result
    │       │
    │       └── rpc_test.dart              ← signInWithPassword as ADMIN → rpc('evaluar_entrega_v2')
    │           (TRG-05..07)                  → assert EvaluacionEntrega.estado
    │
    └── [SQL pgTAP] supabase/tests/database/
            │
            ├── rls_policies.test.sql      ← BEGIN; authenticate_as(x); SELECT/INSERT/DELETE;
            │   (RLS-01..06)                  assert ok/error; ROLLBACK;
            │
            └── triggers.test.sql          ← BEGIN; service_role INSERT; verify trigger fires;
                (TRG-01..04)                  ROLLBACK; (all data cleaned automatically)

    Both test layers → Supabase Production DB (ppltpmmtdnprgauwnytf)
    Test data inserted inside ROLLBACK transactions (pgTAP) or cleaned by service_role (Dart)
```

### Recommended Project Structure
```
test/
├── unit/                         # Phase 1 (already exists)
│   ├── hash_chain_test.dart
│   ├── stock_calculator_test.dart
│   └── ...
└── integration/
    └── supabase/
        ├── helpers/
        │   ├── test_client.dart   # Factory: SupabaseClient per role
        │   └── test_data.dart     # Seed + cleanup helpers (service_role)
        ├── rls_test.dart          # RLS-01..06
        └── rpc_test.dart          # TRG-05..07

supabase/
└── tests/
    └── database/
        ├── rls_policies.test.sql  # RLS via pgTAP (alternative/complementary)
        └── triggers.test.sql      # TRG-01..04 via pgTAP
```

### Pattern 1: Per-Role Dart Client via signInWithPassword

**What:** Create a separate `SupabaseClient` for each role by signing in with a pre-created test user. The session JWT is automatically used for all subsequent requests. This is the most straightforward approach: no JWT secret needed, works exactly like the real app.

**When to use:** RLS tests (RLS-01..06) and RPC tests (TRG-05..07).

**Example:**
```dart
// Source: supabase_flutter 2.12.0 API + project patterns
// test/integration/supabase/helpers/test_client.dart

Future<SupabaseClient> clientForRole(String email, String password) async {
  // Use a fresh SupabaseClient (not Supabase.instance.client) to avoid 
  // polluting the global session
  final client = SupabaseClient(
    SupabaseConfig.url,
    SupabaseConfig.anonKey,
  );
  await client.auth.signInWithPassword(email: email, password: password);
  return client;
}

// In test setup:
// ADMIN: await clientForRole('test_admin@trazapp.test', 'TestAdmin123!')
// SUPERVISOR: await clientForRole('test_supervisor@trazapp.test', 'TestSupervisor123!')
// READONLY: await clientForRole('test_readonly@trazapp.test', 'TestReadonly123!')
// ANON: new SupabaseClient(url, anonKey)  // no sign-in
```

### Pattern 2: Per-Role JWT via SupabaseClient.accessToken (for tests that need no real user)

**What:** Construct a signed JWT token with the Supabase JWT secret and pass it via the `accessToken` callback in `SupabaseClient`. The `role` claim must be `authenticated` (for authenticated users) or `anon`. The `sub` claim must be a valid UUID in `auth.users` for RLS policies that check `auth.uid()`. This approach requires the JWT secret from Supabase → Settings → API.

**When to use:** Only if signInWithPassword approach proves impractical (e.g., test environment cannot create auth users). The `signInWithPassword` approach is preferred.

**Example:**
```dart
// Source: [ASSUMED] — SupabaseClient accessToken API confirmed from GitHub source
// This requires SUPABASE_JWT_SECRET env var — handle carefully
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

SupabaseClient clientWithJwt(String userId, String appRole) {
  return SupabaseClient(
    SupabaseConfig.url,
    SupabaseConfig.anonKey,
    accessToken: () async {
      final jwt = JWT(
        {
          'iss': 'supabase',
          'ref': 'ppltpmmtdnprgauwnytf',
          'role': 'authenticated',
          'sub': userId,
          'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'exp': (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 3600,
          'app_metadata': {'app_role': appRole},
        },
      );
      return jwt.sign(SecretKey(const String.fromEnvironment('SUPABASE_JWT_SECRET')));
    },
  );
}
```

**Critical warning:** Supabase reads app-level roles (ADMIN/SUPERVISOR/READONLY) from the `perfiles` table via `auth.uid()`, NOT from JWT claims. The JWT `sub` must match a real `auth.users.id` that has a corresponding `perfiles` row with the correct `rol`. JWT-based approach still requires real users in the DB.

### Pattern 3: pgTAP Tests with `supabase test db`

**What:** SQL tests inside `BEGIN`/`ROLLBACK` using pgTAP assertions. Authentication is simulated via `set_config` calls that set `request.jwt.claims`:

```sql
-- Source: [CITED: supabase/discussions/14576] — official Supabase recommendation
-- Simulating authenticated user with specific auth.uid():
set local role authenticated;
set local request.jwt.claims to 
  '{"role": "authenticated", "sub": "<real-uuid-from-auth.users>"}';

-- Running as anon:
set local role anon;
-- (no jwt claims needed for anon)

-- Back to postgres (service role):
set local role postgres;
```

The `basejump-supabase_test_helpers` library wraps this in convenient functions:
```sql
-- After installing basejump-supabase_test_helpers via dbdev:
SELECT tests.authenticate_as('test_admin');  -- sets role + jwt claims
SELECT tests.clear_authentication();          -- resets to anon
SELECT tests.authenticate_as_service_role();  -- sets role to service_role
```

**When to use:** RLS tests (RLS-01..06) and trigger tests (TRG-01..04). pgTAP runs inside `BEGIN`/`ROLLBACK` so NO cleanup needed — all data inserted in tests is automatically rolled back.

**Example pgTAP test (RLS-05: no-delete policy):**
```sql
-- Source: [CITED: supabase.com/docs/guides/database/testing]
-- supabase/tests/database/rls_policies.test.sql

BEGIN;
SELECT plan(2);

-- Insert test entrega as service role
SELECT tests.authenticate_as_service_role();
INSERT INTO entregas_epp (event_id, trabajador_id, obra_id, entregado_por, items, hash)
  VALUES (gen_random_uuid(), '<test-trabajador-id>', '<test-obra-id>',
          tests.get_supabase_uid('test_admin'),
          '[]'::jsonb, 'testhash');

-- Now test that admin cannot delete
SELECT tests.authenticate_as('test_admin');
SELECT throws_ok(
  $$ DELETE FROM entregas_epp WHERE hash = 'testhash' $$,
  'new row violates row-level security policy for table "entregas_epp"',
  'RLS-05: ADMIN cannot delete entregas_epp'
);

SELECT * FROM finish();
ROLLBACK;
```

### Pattern 4: Test Data Isolation for No-DELETE Tables

**Problem:** `entregas_epp`, `asistencias`, and `stock_movimientos` have `USING (false)` DELETE policies. Tests cannot clean up data with normal DELETE. [VERIFIED: security_hardening.sql, asistencias.sql]

**Three-layer isolation strategy:**

1. **pgTAP (preferred for SQL tests):** Wrap entire test in `BEGIN`/`ROLLBACK`. All inserts are rolled back automatically. Zero cleanup needed. [CITED: supabase.com/docs/guides/database/testing]

2. **Dart tests with service_role cleanup client:** Create a cleanup `SupabaseClient` using the service_role key (bypasses RLS entirely). Call delete at the end of each test group using a sentinel `local_event_id` prefix:
```dart
// Service role client bypasses all RLS policies
final serviceClient = SupabaseClient(
  SupabaseConfig.url,
  serviceRoleKey,  // from env var, NOT from SupabaseConfig
);
// Cleanup after test group
await serviceClient.from('entregas_epp')
  .delete()
  .like('local_event_id', 'test_%');
```

3. **Sentinel prefix pattern:** All test data uses a unique prefix (`test_` on `local_event_id`, RUT `TEST-001`, etc.) so cleanup queries are surgical and cannot accidentally delete real data.

### Anti-Patterns to Avoid

- **Using `Supabase.instance.client` in integration tests:** Global singleton carries auth state between tests. Use `SupabaseClient(url, key)` directly to get isolated instances per test.
- **Constructing JWTs without real `auth.users` entries:** Supabase RLS policies that call `auth.uid()` and then look up the `perfiles` table need the UUID to exist in BOTH `auth.users` AND `perfiles`. JWT claim alone is not enough.
- **Calling `supabase.rpc()` before `Supabase.initialize()`:** RPC calls require the Supabase singleton. In Dart tests, call `await Supabase.initialize(url: ..., anonKey: ...)` in `setUpAll()` and `Supabase.instance.client` — OR use `SupabaseClient(url, key)` directly to bypass the singleton.
- **Depending on `evaluar_entrega_v2` SQL definition being in the repo:** This function is NOT in any local `.sql` file — it lives only in the production database. Tests must call it via RPC and verify return shape; they cannot inspect the SQL source.
- **Leaving pgTAP tests without `ROLLBACK`:** All test data must be wrapped in a transaction that rolls back. A test that exits without `ROLLBACK` will permanently insert test records.
- **Testing anon policies using the authenticated anon key + a logged-in session:** Anon behavior requires using the anon key with NO active session. Use a `SupabaseClient` initialized with `anonKey` and **do not** call `signIn`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Per-role test auth | Custom JWT construction | `signInWithPassword` with test users | Real auth matches production behavior; JWT secret not needed |
| RLS assertion | Raw boolean checks | pgTAP `throws_ok` / `lives_ok` | pgTAP handles error message matching correctly |
| Test data cleanup on no-DELETE tables | Complex state tracking | `BEGIN`/`ROLLBACK` in pgTAP | Transactional rollback is atomic and infallible |
| Test user creation | Manual dashboard setup | Service_role INSERT into `auth.users` | Reproducible; can be scripted and versioned |
| Auth context simulation in SQL | Custom `set_config` helper | `basejump-supabase_test_helpers` | Library tested, documented, encapsulates the `request.jwt.claims` pattern |

**Key insight:** The hardest problem in Supabase testing is simulating specific auth contexts. Both pgTAP (via `set_config`/test helpers) and Dart (via `signInWithPassword`) solve this correctly. Do not attempt to simulate auth by inserting fake rows into `auth.users` directly with SQL — Supabase Auth manages password hashing and user metadata separately.

---

## Runtime State Inventory

> Not applicable — this is a greenfield test phase. No rename/refactor/migration involved.

---

## Common Pitfalls

### Pitfall 1: `evaluar_entrega_v2` SQL definition not in repo
**What goes wrong:** Tests reference or try to recreate the RPC SQL, but the function lives only in the production database. No `.sql` file defines it in `supabase/`.
**Why it happens:** The function was created directly in Supabase SQL Editor, not via a migration file.
**How to avoid:** Test via `client.rpc('evaluar_entrega_v2', params: {...})` only. Do not try to inspect or redefine the function. Confirm function exists by making a test RPC call in the setup phase.
**Warning signs:** `PostgrestException: Could not find the function public.evaluar_entrega_v2` — means function does not exist or signature mismatch.

### Pitfall 2: RLS INSERT policy checks `entregado_por = auth.uid()` — READONLY users can insert if they set entregado_por to their own UUID
**What goes wrong:** A READONLY user CAN insert into `entregas_epp` if they set `entregado_por = auth.uid()`. The `insert_own_entregas` policy only checks that `auth.uid() IS NOT NULL AND entregado_por = auth.uid()`. There is no role-based restriction on INSERT. [VERIFIED: security_hardening.sql line 117-123]
**Why it matters:** RLS-03 requirement says "READONLY no puede insertar entregas EPP" — but the current RLS implementation does NOT block READONLY from inserting. Test RLS-03 must verify the actual policy behavior (not an assumed restriction).
**How to avoid:** Test what actually happens. Document whether this is a known gap or intentional design.
**Warning signs:** READONLY user inserts successfully → test should assert this behavior (and flag it as a potential security gap for human review).

### Pitfall 3: Test users share the same `org_id` — ADMIN "sees all" really means "sees all in org"
**What goes wrong:** RLS-01 says "ADMIN ve todos los trabajadores de todas las obras" but the `select_trabajadores` policy checks `rol = 'ADMIN'` from the `perfiles` table. If test users are in different orgs, the ADMIN policy lets ADMIN see ALL workers regardless of org. But if the test ADMIN user has no `perfiles` row, the policy will fail entirely.
**How to avoid:** All test users must have rows in `perfiles` with the same `org_id`. The test setup script must insert these rows after creating the `auth.users` entries.

### Pitfall 4: pgTAP's `throws_ok` expects exact error message string
**What goes wrong:** Trigger exceptions like `RAISE EXCEPTION 'Campo inmutable: items'` have exact text. If the message format changes, the test fails with a cryptic "expected exception message X, got Y".
**How to avoid:** Use `throws_ok($$ SQL $$, NULL, 'description')` (NULL for message) to check that ANY exception is thrown, or capture the exact message from the trigger SQL file.
**Warning signs:** Test was passing, then fails after a trigger message string change.

### Pitfall 5: `supabase test db` requires Supabase CLI v1.11.4+ AND local Supabase stack OR connected remote
**What goes wrong:** `supabase test db` by default runs against the local Supabase stack (Docker). Against the live production DB, you need to use `supabase db query` (requires CLI 2.79.0+, we have 2.75.0) or connect via psql directly.
**How to avoid:** For production DB pgTAP tests, use `psql` with the connection string from Supabase Dashboard → Settings → Database → Connection string. The `supabase test db` command is for local Docker stack.
**Connection pattern:**
```bash
# Get connection string from Supabase Dashboard
# Settings → Database → Connection string → URI
psql "postgresql://postgres:[PASSWORD]@db.ppltpmmtdnprgauwnytf.supabase.co:5432/postgres" \
  -f supabase/tests/database/triggers.test.sql
```

### Pitfall 6: `trg_prevent_stock_negativo` checks stock BEFORE the current INSERT is counted
**What goes wrong:** The trigger calculates existing stock from `stock_movimientos` and checks `(v_stock_actual - NEW.cantidad) < 0`. It does NOT count the in-flight INSERT. This means testing TRG-02 requires inserting an ENTRADA first, then attempting a valid SALIDA — not just checking that stock > 0 in the DB.
**How to avoid:** Test data setup must: (1) INSERT ENTRADA with quantity N, (2) attempt SALIDA ≤ N (should succeed), (3) attempt SALIDA > N (should fail).
**Warning signs:** TRG-02 passes even with no ENTRADA in DB — means test is checking the wrong thing.

### Pitfall 7: `get_vencimientos_proximos` uses `SECURITY DEFINER` — requires service_role to call in tests
**What goes wrong:** `get_vencimientos_proximos` has `GRANT EXECUTE ... TO service_role` only. Calling it as an authenticated user will fail with a permission error. [VERIFIED: notificaciones_vencimiento.sql line 98]
**How to avoid:** TRG-07 test must use the service_role client (not an authenticated user client) to call this RPC. However, looking at the grant — `GRANT EXECUTE ON FUNCTION public.get_vencimientos_proximos() TO service_role` — this suggests only service_role can call it. Verify actual behavior in a test call first.
**Warning signs:** `permission denied for function get_vencimientos_proximos` when calling as authenticated user.

### Pitfall 8: `Supabase.initialize()` cannot be called multiple times in tests
**What goes wrong:** Calling `Supabase.initialize()` more than once throws an exception in `supabase_flutter`. Using `Supabase.instance.client` before initialization throws a different exception.
**How to avoid:** Call `await Supabase.initialize(...)` once in `setUpAll()` at the top level. For tests needing different roles, create `SupabaseClient(url, key)` instances directly (bypasses the singleton). Sign in to these instances separately.

---

## Code Examples

### Creating a per-role test client (Dart)
```dart
// Source: supabase_flutter docs + SupabaseClient constructor API
// test/integration/supabase/helpers/test_client.dart

import 'package:supabase_flutter/supabase_flutter.dart';

const _testUsers = {
  'admin':      ('test_admin@trazapp.test',      'TestAdmin123!'),
  'supervisor': ('test_supervisor@trazapp.test', 'TestSupervisor123!'),
  'readonly':   ('test_readonly@trazapp.test',   'TestReadonly123!'),
};

/// Returns a SupabaseClient authenticated as the given role.
/// Role must be 'admin', 'supervisor', or 'readonly'.
Future<SupabaseClient> signedInAs(String role) async {
  final (email, password) = _testUsers[role]!;
  final client = SupabaseClient(
    'https://ppltpmmtdnprgauwnytf.supabase.co',
    '<anon-key>',  // read from env or SupabaseConfig
  );
  await client.auth.signInWithPassword(email: email, password: password);
  return client;
}

/// Returns a SupabaseClient using service_role key (bypasses all RLS).
SupabaseClient serviceRoleClient(String serviceRoleKey) {
  return SupabaseClient(
    'https://ppltpmmtdnprgauwnytf.supabase.co',
    serviceRoleKey,
  );
}

/// Returns a SupabaseClient as anon (no sign-in).
SupabaseClient anonClient() {
  return SupabaseClient(
    'https://ppltpmmtdnprgauwnytf.supabase.co',
    '<anon-key>',
  );
}
```

### Testing RLS DELETE block (Dart)
```dart
// RLS-05: Nadie puede eliminar registros de entregas_epp
test('RLS-05: ADMIN no puede eliminar entregas_epp', () async {
  final admin = await signedInAs('admin');
  
  // Attempt to delete a known test record
  expect(
    () async => await admin.from('entregas_epp')
        .delete()
        .eq('local_event_id', 'test_rls05_sentinel'),
    // Supabase returns empty array (0 rows deleted) rather than throwing
    // when RLS USING(false) policy is active — zero rows returned, no exception
    // Verify by checking count of deleted rows:
    returnsNormally,  // no exception thrown
  );
  // Then assert the record still exists via service role
  final svc = serviceRoleClient(serviceRoleKey);
  final remaining = await svc.from('entregas_epp')
      .select('id')
      .eq('local_event_id', 'test_rls05_sentinel');
  expect(remaining, isNotEmpty, reason: 'Record must still exist after ADMIN delete attempt');
  await admin.auth.signOut();
});
```

### pgTAP trigger test (SQL)
```sql
-- Source: [CITED: supabase.com/docs/guides/database/testing + supabase discussions/14576]
-- supabase/tests/database/triggers.test.sql

BEGIN;
SELECT plan(3);

-- TRG-01: Stock negativo bloqueado
-- Setup: ENTRADA de 5 unidades
INSERT INTO stock_movimientos (bodega_id, epp_id, tipo, cantidad, created_by)
VALUES ('<test-bodega-id>', '<test-epp-id>', 'ENTRADA', 5, '<test-user-id>');

-- SALIDA válida (5 <= 5): debe pasar
SELECT lives_ok(
  $$ INSERT INTO stock_movimientos (bodega_id, epp_id, tipo, cantidad, created_by)
     VALUES ('<test-bodega-id>', '<test-epp-id>', 'SALIDA', 5, '<test-user-id>') $$,
  'TRG-02: SALIDA con stock suficiente no lanza excepción'
);

-- TRG-01: SALIDA que deja stock < 0 (total es 0 después del paso anterior)
SELECT throws_ok(
  $$ INSERT INTO stock_movimientos (bodega_id, epp_id, tipo, cantidad, created_by)
     VALUES ('<test-bodega-id>', '<test-epp-id>', 'SALIDA', 1, '<test-user-id>') $$,
  'Stock insuficiente',
  'TRG-01: SALIDA con stock=0 lanza excepción'
);

-- TRG-03: Inmutabilidad de entregas_epp
INSERT INTO entregas_epp (event_id, trabajador_id, obra_id, entregado_por, items, hash, local_event_id)
  VALUES (gen_random_uuid(), '<test-trabajador-id>', '<test-obra-id>',
          '<test-user-id>', '[]'::jsonb, 'hash_test_trg03', 'test_trg03');

SELECT throws_ok(
  $$ UPDATE entregas_epp SET items = '[{"epp_id":"x"}]'::jsonb 
     WHERE local_event_id = 'test_trg03' $$,
  'Campo inmutable: items',
  'TRG-03: UPDATE de items lanza excepción'
);

SELECT * FROM finish();
ROLLBACK;
```

### RPC test (Dart)
```dart
// TRG-05, TRG-06: evaluar_entrega_v2 
test('TRG-06: trabajador sin EPP retorna estado CRITICO', () async {
  final admin = await signedInAs('admin');
  
  final response = await admin.rpc('evaluar_entrega_v2', params: {
    'p_trabajador_id': testTrabajadorSinEpp,
    'p_obra_id': testObraId,
    'p_items': [
      {'epp_id': requiredEppId, 'cantidad': 1, 'criticidad': 'CRITICO'},
    ],
  });
  
  // EvaluacionEntrega.fromJson shape: {estado: String, detalle: Map}
  expect(response['estado'], equals('CRITICO'));
  await admin.auth.signOut();
});
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual RLS testing via Supabase Dashboard | `supabase test db` with pgTAP | Supabase CLI v1.11.4 | Automated, version-controlled SQL tests |
| JWT construction with `service_role` secret | `signInWithPassword` with test users | supabase_flutter 2.x | No secret exposure; matches real app auth |
| `auth.role()` in RLS policies | `TO authenticated` clause on policies | Supabase ~2023 | `auth.role()` is deprecated [CITED: SKILL.md] |

**Deprecated/outdated:**
- `auth.role()` in RLS policies: deprecated, use `TO authenticated` in policy definition
- Direct `set session role` without `set local`: use `set local` inside transactions (scoped to transaction, safer for pgTAP)

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | READONLY users cannot insert `entregas_epp` — but current RLS policy (`insert_own_entregas`) only checks `entregado_por = auth.uid()`, NOT role. READONLY may be able to insert. | Pitfall 2 | RLS-03 test may need to be written as "verify actual behavior" not "verify block" |
| A2 | `evaluar_entrega_v2` accepts `{p_trabajador_id, p_obra_id, p_items}` and returns `{estado, detalle}` — inferred from Dart call sites, SQL definition not in repo | Standard Stack / Code Examples | If signature differs, RPC tests will fail with signature mismatch |
| A3 | `get_vencimientos_proximos` is callable by authenticated users for TRG-07 — the GRANT says `TO service_role` but function may also have implicit authenticated access | Pitfall 7 | TRG-07 test may need service_role client, not authenticated client |
| A4 | `basejump-supabase_test_helpers` installs correctly on production Supabase via dbdev — not tested locally yet | Standard Stack | If dbdev is unavailable, fall back to manual `set local role / set local request.jwt.claims` pattern |
| A5 | `obra_usuarios` table exists and is used by SUPERVISOR RLS check for `trabajadores` — inferred from `security_hardening.sql` JOIN, but `obra_usuarios` table itself not inspected | RLS-02 test data | If table name differs or FK structure is different, test data setup will fail |

---

## Open Questions (RESOLVED)

1. **What is the SQL definition of `evaluar_entrega_v2`?**
   - What we know: It accepts `p_trabajador_id`, `p_obra_id`, `p_items` (inferred from Dart call sites). Returns `{estado: String, detalle: Map}`.
   - What's unclear: What logic determines CRITICO vs OK? Does it check `catalogo_epp.criticidad`? Does it check existing `entregas_epp` records?
   - Recommendation: In Wave 0, make a test RPC call via service_role and inspect the return to understand the return structure before writing assertion tests.

2. **Can READONLY users insert `entregas_epp`?**
   - What we know: The INSERT policy `insert_own_entregas` only checks `entregado_por = auth.uid()`. There is no role check. [VERIFIED: security_hardening.sql]
   - What's unclear: Whether this is intentional (READONLY can still deliver EPP) or a gap.
   - Recommendation: Test actual behavior. If READONLY can insert, document RLS-03 as "READONLY CAN insert (no role restriction on INSERT)" and flag for security review.

3. **Is `supabase test db` usable against the production DB (not local Docker)?**
   - What we know: `supabase test db` defaults to local stack. CLI 2.75.0 is installed (below the 2.79.0 threshold for `supabase db query`).
   - What's unclear: Whether there is a `--db-url` flag or equivalent for directing pgTAP tests to the remote DB.
   - Recommendation: Use `psql` with the production connection string as the pgTAP runner. Command: `psql "<connection-string>" -f test.sql`.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK | All Dart tests | ✓ | SDK bundled with project | — |
| `supabase_flutter` | Dart client tests | ✓ | 2.12.0 (pubspec.lock) | — |
| Supabase CLI | `supabase test db` | ✓ | 2.75.0 | Use `psql` directly |
| `dart_jsonwebtoken` | Optional JWT approach | ✗ (not yet in pubspec) | 3.4.1 on pub.dev | `signInWithPassword` (preferred) |
| `psql` | pgTAP via CLI | [ASSUMED] | — | Install via Homebrew: `brew install libpq` |
| Production DB access | All tests | ✓ | Supabase project ppltpmmtdnprgauwnytf linked | — |
| `SUPABASE_SERVICE_ROLE_KEY` | Test cleanup client | [ASSUMED] available as env var | — | Must be set before running tests |

**Missing dependencies with no fallback:**
- `SUPABASE_SERVICE_ROLE_KEY` environment variable — must be set for test cleanup (service_role DELETE) and test user setup. Plans must include a step verifying this is available.

**Missing dependencies with fallback:**
- `dart_jsonwebtoken` — only needed for synthetic JWT approach; `signInWithPassword` is the preferred alternative
- Supabase CLI 2.79.0+ for `supabase db query` — `psql` is the fallback for running pgTAP SQL tests

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `flutter_test` (Dart) + pgTAP (SQL) |
| Config file | none (flutter_test uses pubspec.yaml) |
| Quick run command | `flutter test test/integration/supabase/ --reporter=compact` |
| Full suite command | `flutter test test/ --reporter=expanded` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| RLS-01 | ADMIN reads all trabajadores | integration (Dart) | `flutter test test/integration/supabase/rls_test.dart -n RLS-01` | ❌ Wave 0 |
| RLS-02 | SUPERVISOR reads only own-obra trabajadores | integration (Dart) | `flutter test test/integration/supabase/rls_test.dart -n RLS-02` | ❌ Wave 0 |
| RLS-03 | READONLY insert behavior on entregas_epp | integration (Dart) | `flutter test test/integration/supabase/rls_test.dart -n RLS-03` | ❌ Wave 0 |
| RLS-04 | Anon INSERT asistencias, no SELECT | integration (Dart) | `flutter test test/integration/supabase/rls_test.dart -n RLS-04` | ❌ Wave 0 |
| RLS-05 | No-delete entregas_epp (all roles) | integration (Dart) | `flutter test test/integration/supabase/rls_test.dart -n RLS-05` | ❌ Wave 0 |
| RLS-06 | No-delete asistencias (all roles) | integration (Dart) | `flutter test test/integration/supabase/rls_test.dart -n RLS-06` | ❌ Wave 0 |
| TRG-01 | trg_prevent_stock_negativo blocks | integration (SQL pgTAP or Dart) | `flutter test test/integration/supabase/trigger_test.dart -n TRG-01` | ❌ Wave 0 |
| TRG-02 | trg_prevent_stock_negativo allows | integration (SQL pgTAP or Dart) | `flutter test test/integration/supabase/trigger_test.dart -n TRG-02` | ❌ Wave 0 |
| TRG-03 | trg_entregas_epp_immutable blocks UPDATE | integration (Dart) | `flutter test test/integration/supabase/trigger_test.dart -n TRG-03` | ❌ Wave 0 |
| TRG-04 | trg_audit_entregas_epp INSERT → audit_log | integration (Dart) | `flutter test test/integration/supabase/trigger_test.dart -n TRG-04` | ❌ Wave 0 |
| TRG-05 | evaluar_entrega_v2 OK estado | integration (Dart RPC) | `flutter test test/integration/supabase/rpc_test.dart -n TRG-05` | ❌ Wave 0 |
| TRG-06 | evaluar_entrega_v2 CRITICO estado | integration (Dart RPC) | `flutter test test/integration/supabase/rpc_test.dart -n TRG-06` | ❌ Wave 0 |
| TRG-07 | get_vencimientos_proximos returns results | integration (Dart RPC) | `flutter test test/integration/supabase/rpc_test.dart -n TRG-07` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `flutter test test/integration/supabase/ --reporter=compact`
- **Per wave merge:** `flutter test test/ --reporter=expanded`
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `test/integration/supabase/helpers/test_client.dart` — per-role client factory
- [ ] `test/integration/supabase/helpers/test_data.dart` — seed data + service_role cleanup
- [ ] `test/integration/supabase/rls_test.dart` — covers RLS-01..06
- [ ] `test/integration/supabase/trigger_test.dart` — covers TRG-01..04
- [ ] `test/integration/supabase/rpc_test.dart` — covers TRG-05..07
- [ ] Test user accounts in production Supabase Auth (setup script required)
- [ ] `perfiles` rows for each test user (same `org_id`, correct `rol` values)
- [ ] `dart pub add --dev dart_jsonwebtoken` (only if JWT approach is needed)

---

## Security Domain

> `security_enforcement: true`, `security_asvs_level: 1` per `.planning/config.json`.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes — test users need real auth | `signInWithPassword` only; never store test passwords in git (use env vars) |
| V3 Session Management | yes | Use separate `SupabaseClient` instances per test to prevent session cross-contamination |
| V4 Access Control | yes — this is the core of Phase 2 | RLS policies verified per role |
| V5 Input Validation | no — tests don't add new input paths | — |
| V6 Cryptography | partial — `dart_jsonwebtoken` for JWT | Use HS256 with `SUPABASE_JWT_SECRET` via env var; NEVER hardcode secret |

### Known Threat Patterns for Test Infrastructure

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Hardcoded service_role key in test files | Information Disclosure | Load from `String.fromEnvironment('SUPABASE_SERVICE_ROLE_KEY')` or `.env` file not committed to git |
| Test data leaking to production tables | Tampering | All test data uses `test_` prefix; service_role cleanup runs in `tearDownAll()` |
| JWT secret exposure | Information Disclosure | Only use synthetic JWT approach if absolutely required; prefer `signInWithPassword` |
| Test user with ADMIN role in production | Elevation of Privilege | Test ADMIN user has `org_id` of a test/demo org, not real customer org |

---

## Sources

### Primary (HIGH confidence)
- `supabase/security_hardening.sql` — actual RLS policy implementations (RLS-01..06)
- `supabase/asistencias.sql` — anon INSERT + no-delete policies
- `supabase/audit_log.sql` — trigger and audit_log table structure
- `supabase/stock_negativo_prevention.sql` — `fn_prevent_stock_negativo` trigger logic
- `supabase/notificaciones_vencimiento.sql` — `get_vencimientos_proximos` RPC signature and grant
- `lib/services/auth_service.dart` — roles ADMIN/SUPERVISOR/READONLY and `perfiles` table structure
- `lib/services/entrega_service.dart` — `evaluar_entrega_v2` call signature
- `pubspec.lock` — exact versions of installed packages
- `.planning/config.json` — `nyquist_validation: true`, `security_enforcement: true`

### Secondary (MEDIUM confidence)
- [CITED: supabase.com/docs/guides/database/testing] — pgTAP test approach, `BEGIN`/`ROLLBACK` pattern
- [CITED: github.com/supabase/discussions/14576] — `set local role authenticated; set local request.jwt.claims to ...` pattern
- [CITED: github.com/usebasejump/supabase-test-helpers] — `tests.authenticate_as()`, `tests.create_supabase_user()` API
- [CITED: github.com/supabase/supabase-flutter] — `SupabaseClient(url, key, accessToken: ...)` constructor API
- [CITED: pub.dev/packages/dart_jsonwebtoken] — 3.4.1, 891K downloads/month, `jwt.sign(SecretKey(secret))` API

### Tertiary (LOW confidence)
- A2 (Assumptions Log): `evaluar_entrega_v2` signature inferred from Dart call sites, not from SQL definition
- A3 (Assumptions Log): `get_vencimientos_proximos` callability for authenticated users

---

## Metadata

**Confidence breakdown:**
- Standard Stack: HIGH — packages verified on pub.dev; `supabase_flutter` confirmed in pubspec.lock
- Architecture: HIGH — RLS policies and trigger logic read directly from SQL source files
- Pitfalls: HIGH for Pitfalls 1-6 (derived from reading actual SQL); MEDIUM for Pitfalls 7-8 (verified via SDK docs)
- RPC test data requirements: MEDIUM — `evaluar_entrega_v2` signature inferred, not verified from SQL

**Research date:** 2026-06-01
**Valid until:** 2026-07-01 (supabase_flutter releases frequently; recheck if upgrading past 2.12.x)

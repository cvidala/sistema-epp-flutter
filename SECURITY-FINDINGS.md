# Security Findings — TrazApp QA Phase 2

**Phase:** 02-supabase-tests
**Date:** 2026-06-02
**Discovered by:** Integration test suite (rls_test.dart)

---

## SF-01: READONLY role can insert into entregas_epp

**Severity:** Medium
**Discovered:** Phase 2 Supabase integration tests (RLS-03)
**Status:** Documented, not fixed (out of scope for Phase 2)

### Description

The `insert_own_entregas` RLS policy on `entregas_epp` only checks:

```sql
auth.uid() IS NOT NULL AND entregado_por = auth.uid()
```

There is NO role-based restriction. A READONLY user who sets
`entregado_por = auth.uid()` CAN successfully insert an entrega.

### Requirement Context

REQUIREMENTS.md RLS-03 states: "READONLY no puede insertar entregas EPP".
The current RLS implementation does NOT enforce this restriction.

### Verified Behavior

Integration test `RLS-03: READONLY insert behavior (security gap)` in
`test/integration/supabase/rls_test.dart` confirms READONLY users
CAN insert when setting `entregado_por = their own uid`.

The test asserts `insertError == null` (i.e., insert succeeds) and
includes the inline comment:

```dart
// SECURITY-GAP (RLS-03): READONLY can insert entregas_epp.
// Policy insert_own_entregas only checks entregado_por = auth.uid(), NOT role.
// See SECURITY-FINDINGS.md for full analysis.
```

### Recommended Fix (future phase)

Add a role check to the INSERT policy in `security_hardening.sql`:

```sql
DROP POLICY IF EXISTS "insert_own_entregas" ON entregas_epp;
CREATE POLICY "insert_own_entregas"
  ON entregas_epp FOR INSERT
  WITH CHECK (
    auth.uid() IS NOT NULL
    AND entregado_por = auth.uid()
    AND EXISTS (
      SELECT 1 FROM perfiles
      WHERE user_id = auth.uid()
        AND rol IN ('ADMIN', 'SUPERVISOR')
    )
  );
```

### Risk Assessment

| Factor | Assessment |
|--------|------------|
| Exploitability | Medium — requires a valid READONLY user session |
| Impact | A READONLY user can create EPP delivery records attributed to themselves |
| Immutability | Records are immutable once created (trigger protects against tampering) |
| Audit trail | `audit_log` captures all inserts — traceability is maintained |
| Primary risk | Fraudulent delivery records created by READONLY users |
| Pre-production | System currently pre-production; no real customer data at risk |

### Additional Notes

- The immutability trigger (`trg_entregas_epp_immutable`) still protects records
  after creation — a READONLY user cannot modify records they inserted.
- The audit trigger (`trg_audit_entregas_epp`) captures every insert including
  those from READONLY users — forensic traceability is intact.
- The SELECT policy for `entregas_epp` still correctly limits what READONLY users
  can read (only their own records via `entregado_por = auth.uid()`).

---

## Additional Findings

### SF-02: entregas_epp BEFORE DELETE trigger blocks service_role

**Severity:** Informational (by design)
**Discovered:** Phase 2 test infrastructure (TestDataHelper)

The database has a `BEFORE DELETE` trigger on `entregas_epp` that raises
`"Eliminación de entregas no permitida. Registro inmutable."` for ALL users,
including service_role. This goes beyond the RLS `USING(false)` policy — it
is a database-level constraint enforced via trigger.

**Consequence for tests:** Test rows inserted into `entregas_epp` during
integration tests are permanent. They use event_id with prefix `test_qa_` for
identification and do not interfere with production data.

**Assessment:** This is intentional design — EPP delivery records are forensic
evidence and must be permanently immutable. The behavior is correct.

---

*Last updated: 2026-06-02 — Phase 2 integration test execution*

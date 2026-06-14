# Phase 5: Load/Stress Tests - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-13
**Phase:** 05-load-stress-tests
**Areas discussed:** CI step placement

---

## CI Step Placement

| Option | Description | Selected |
|--------|-------------|----------|
| Step in existing `test` job | Add `flutter test test/stress/ --tags stress` after unit tests, before integration tests. No extra Flutter setup overhead. | ✓ |
| Separate `stress-test` job | New parallel job with its own Flutter setup. Better isolation but adds ~90s overhead. | |

**User's choice:** Step in existing `test` job (Recommended)
**Notes:** No per-file `@Timeout` annotation — CI job-level `timeout-minutes: 15` is sufficient.

---

## Claude's Discretion

- Test timeout strategy: rely on CI job timeout (no per-file `@Timeout`)
- Test data exact timestamp spacing in STR-01 and STR-03
- Whether to group tests per requirement or use flat `test()` structure
- STR-03 data distribution (30 PENDING + 15 ERROR-future + 5 ERROR-past)
- Deterministic IDs (`'evt-$i'`) vs UUID for bulk enqueue tests

## Deferred Ideas

None — discussion stayed within phase scope.

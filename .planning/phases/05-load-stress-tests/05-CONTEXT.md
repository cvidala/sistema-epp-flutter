# Phase 5: Load/Stress Tests - Context

**Gathered:** 2026-06-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Stress-test the `OfflineQueueService` Hive queue against volume (200+ items), concurrent writes (20 simultaneous), and backoff filtering under load (50+ items). All tests run in Dart with no network dependencies, in under 60 seconds, and integrate into the existing GitHub Actions CI job.

**Not in scope:** Network performance, Supabase load testing, Edge Function load, UI rendering under load.

</domain>

<decisions>
## Implementation Decisions

### CI Integration (STR-04)
- **D-01:** Stress tests run as a new step in the **existing `test` job** in `.github/workflows/test.yml`, placed after "Unit & Widget Tests" and before "Integration Tests". No separate job — avoids redundant Flutter setup overhead for a 4-test suite.
- **D-02:** No per-file `@Timeout` annotation. Rely on the existing `timeout-minutes: 15` at the CI job level. The 60s requirement is a success criterion, not a runtime assertion.

### Test Organization
- **D-03:** Tests live in `test/stress/` directory (new directory). All 4 stress tests in one file: `test/stress/offline_queue_stress_test.dart`.
- **D-04:** File declares `@Tags(['stress'])` at top level so the CI step can run `flutter test test/stress/ --tags stress`.
- **D-05:** Follows the `hive_test` pattern established in Phase 1: `setUpTestHive()` / `tearDownTestHive()` in each `group`'s setUp/tearDown.

### Test Data
- **D-06:** STR-01 (volume): Use deterministic IDs `'evt-$i'` for 200 enqueues — no UUID calls, faster, predictable. Verify with `listAll().length == 200`.
- **D-07:** STR-02 (concurrency): `Future.wait(List.generate(20, (i) => OfflineQueueService.enqueue(...)))`. Verify `listAll().length == 20` and no `localEventId` duplicates.
- **D-08:** STR-03 (backoff filter): Enqueue 30 PENDING + 15 ERROR-with-future-nextRetryAt + 5 ERROR-with-past-nextRetryAt = 50 items. `listPending()` must return exactly 35 (30 PENDING + 5 eligible ERRORs) in chronological order.

### Claude's Discretion
- Exact `createdAtClientIso` timestamp spacing in STR-01 and STR-03 (use sequential increments)
- Whether to split the file into `group()` blocks per requirement or use top-level `test()` calls

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Service Under Test
- `lib/services/offline_queue_service.dart` — Full implementation of `OfflineQueueService` and `OfflineEntrega`. Key methods: `enqueue()`, `listPending()`, `listAll()`, `init()`. Box name: `outbox_entregas`.

### Existing Test Pattern (extend, don't replace)
- `test/unit/offline_queue_test.dart` — Phase 1 tests for `listPending()` backoff and ordering. The `_entrega()` factory helper and `hive_test` lifecycle pattern MUST be reused or extended in the stress test file.

### CI Workflow (modify for D-01)
- `.github/workflows/test.yml` — Add "Stress Tests" step after "Unit & Widget Tests" step: `flutter test test/stress/ --tags stress`. No env vars needed (no network deps).

### Requirements
- `.planning/REQUIREMENTS.md` §STR — STR-01 through STR-04 (exact success conditions for each test)
- `.planning/ROADMAP.md` §Phase 5 — Success Criteria (authoritative 60s limit, exact method names)

### Dependencies
- `pubspec.yaml` — Confirm `hive_test: ^1.0.1` is already present (added in Phase 1). No new packages.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `_entrega()` factory helper in `test/unit/offline_queue_test.dart` — Copy or import this into the stress test file to build `OfflineEntrega` instances quickly with named overrides.
- `OfflineQueueService.listAll()` — Already implemented in `lib/services/offline_queue_service.dart`. Returns all items including SENT/FAILED, sorted chronologically. Used for volume verification (STR-01, STR-02).
- `OfflineQueueService.listPending()` — Existing implementation excludes SENT/FAILED and ERROR items in backoff. Used for STR-03.

### Established Patterns
- **`hive_test` lifecycle:** `await setUpTestHive()` in `setUp`, `await tearDownTestHive()` in `tearDown` — mandatory for Hive isolation between test groups. Each `group()` in the stress file needs its own setUp/tearDown.
- **Dart `@Tags`:** Declare `@Tags(['stress'])` at the top of the file (above `void main()`) to enable tag filtering via `flutter test --tags stress`.
- **`Future.wait` concurrency:** Dart is single-isolate, so `Future.wait` on async Hive writes schedules them on the same event loop (not OS-level threads). STR-02 tests that sequential async writes don't corrupt state or produce duplicates — this is the relevant invariant for the Hive queue.

### Integration Points
- `test/stress/` is a new directory — no existing files to conflict with.
- The CI step inserts between two existing steps in `test.yml`; the job-level `timeout-minutes: 15` already covers the 60s stress test requirement.

</code_context>

<specifics>
## Specific Ideas

- STR-01: `listAll().length` must equal exactly 200 and every `localEventId` must be unique (no duplicates from Hive key collision). Use `Set<String>` to verify uniqueness.
- STR-02: After `Future.wait`, verify `listAll().length == 20` AND `listAll().map((e) => e.localEventId).toSet().length == 20` (no duplicate IDs).
- STR-03: Verify `listPending().length == 35` AND first/last elements match expected chronological order.
- STR-04: The CI step must NOT have any `env:` block (no secrets) — confirms zero network dependency.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 5-load-stress-tests*
*Context gathered: 2026-06-13*

---
phase: 01-unit-tests
plan: 01
subsystem: testing
tags: [flutter, dart, hive, hive_test, crypto, sha256, unit-test, stock-validation, hash-chain, offline-queue]

# Dependency graph
requires: []
provides:
  - StockCalculator static service (computeStock, validateCart) extracted from NewDeliveryPage
  - UTL-01: hash chain integrity tests (4 tests)
  - UTL-02: stock computeStock unit tests (4 tests)
  - UTL-03: stock validateCart unit tests (4 tests)
  - UTL-04: OfflineQueueService.listPending backoff filter tests (3 tests)
  - UTL-05: OfflineQueueService.listPending chronological ordering test (1 test)
affects: [02-widget-tests, 03-integration-tests, ci-setup]

# Tech tracking
tech-stack:
  added: [hive_test 1.0.1 (dev)]
  patterns:
    - Pure static service class extracted from StatefulWidget state for testability
    - Inline canonical JSON reimplementation in test file to avoid exposing private service internals
    - Hive-backed tests using setUpTestHive/tearDownTestHive per group for isolation

key-files:
  created:
    - lib/services/stock_calculator.dart
    - test/unit/hash_chain_test.dart
    - test/unit/stock_calculator_test.dart
  modified:
    - lib/new_delivery_page.dart
    - test/unit/offline_queue_test.dart
    - pubspec.yaml

key-decisions:
  - "StockCalculator placed in lib/services/ (not lib/utils/) to match existing project conventions; no utils/ directory exists"
  - "Hash chain tests reimplement _canonicalJson inline rather than exposing SyncService internals via @visibleForTesting"
  - "hive_test 1.0.1 used for Hive initialization in listPending tests; confirmed compatible with hive 2.2.3"
  - "validateCart returns failing epp_id (not error string) — UI error formatting remains in new_delivery_page.dart"

patterns-established:
  - "Pattern: Extract pure logic from State classes to static service methods before writing unit tests"
  - "Pattern: Each Hive-backed test group gets its own setUp/tearDown with setUpTestHive/tearDownTestHive"
  - "Pattern: Test data for backoff uses DateTime.now() ± Duration offsets (no clock mocking needed)"

requirements-completed: [UTL-01, UTL-02, UTL-03, UTL-04, UTL-05]

# Metrics
duration: 2min
completed: 2026-06-01
---

# Phase 1 Plan 01: Unit Tests — StockCalculator extraction + 5 UTL requirements covered by 16 new tests

**Pure static StockCalculator extracted from NewDeliveryPage, plus 16 new unit tests covering hash chain integrity (UTL-01), stock arithmetic (UTL-02/03), and Hive-backed queue filtering/ordering (UTL-04/05)**

## Performance

- **Duration:** 2 min
- **Started:** 2026-06-01T19:24:28Z
- **Completed:** 2026-06-01T19:27:16Z
- **Tasks:** 4
- **Files modified:** 6

## Accomplishments
- Created `StockCalculator` pure static class with `computeStock` and `validateCart`, delegated from `NewDeliveryPage`
- Added 8 tests for hash chain integrity and stock calculation/validation (UTL-01, UTL-02, UTL-03)
- Extended `offline_queue_test.dart` with 4 Hive-backed tests via `hive_test` package (UTL-04, UTL-05)
- Full suite of 50 tests passes in 2 seconds with no network calls, no HiveError, no SocketException
- `flutter analyze` reports no issues on all modified files

## Task Commits

Each task was committed atomically:

1. **Task 1: Extract StockCalculator and add hive_test dependency** - `c6a20db` (feat)
2. **Task 2: Write unit tests — hash chain (UTL-01) and stock calculator (UTL-02, UTL-03)** - `62acdeb` (feat)
3. **Task 3: Extend offline_queue_test with Hive-backed listPending tests (UTL-04, UTL-05)** - `b3002bb` (feat)

## Files Created/Modified
- `lib/services/stock_calculator.dart` - New pure static class with `computeStock` and `validateCart` methods
- `lib/new_delivery_page.dart` - Added `stock_calculator.dart` import; `_cargarStock` and stock guard delegate to StockCalculator
- `pubspec.yaml` / `pubspec.lock` - Added `hive_test: 1.0.1` to dev_dependencies
- `test/unit/hash_chain_test.dart` - New: 4 tests covering UTL-01 hash chain integrity
- `test/unit/stock_calculator_test.dart` - New: 8 tests covering UTL-02 (computeStock) and UTL-03 (validateCart)
- `test/unit/offline_queue_test.dart` - Extended: added `localEventId`/`createdAt` params to `_entrega()` factory, 2 new groups with 4 tests for UTL-04 and UTL-05

## Decisions Made
- `StockCalculator` placed in `lib/services/` to stay consistent with project conventions (no `utils/` directory exists in the project)
- Hash chain test reimplements `_canonicalJson` inline (5 lines) rather than importing `SyncService` to keep its internals private
- `validateCart` returns the failing `epp_id` as a `String?` rather than constructing the UI error string — the name-lookup and error formatting remain in `new_delivery_page.dart`, making the pure logic fully testable without widget dependencies
- `hive_test` package used for Hive lifecycle; each test group has its own `setUp`/`tearDown` pair for isolation

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None. `hive_test 1.0.1` resolved and ran without issues against `hive 2.2.3`. No fallback to manual `Hive.init(tempDir)` was needed.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All 5 UTL requirements (UTL-01 through UTL-05) verified green
- `StockCalculator` service is available for widget tests and integration tests in Phase 2
- Test infrastructure with `hive_test` is established and reusable for future queue-related tests
- No blockers

---
*Phase: 01-unit-tests*
*Completed: 2026-06-01*

---
phase: 05-load-stress-tests
reviewed: 2026-06-14T00:00:00Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - test/stress/offline_queue_stress_test.dart
  - .github/workflows/test.yml
findings:
  critical: 2
  warning: 4
  info: 1
  total: 7
status: issues_found
---

# Phase 05: Code Review Report

**Reviewed:** 2026-06-14
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

Two files were reviewed: the stress test suite for `OfflineQueueService` and the GitHub Actions CI workflow. Cross-referencing the tests against the actual service implementation (`lib/services/offline_queue_service.dart` and `lib/services/sync_service.dart`) revealed two critical defects: (1) a logic gap in `listPending()` that allows permanently-exhausted ERROR items to be retried indefinitely, which the stress tests fail to catch; and (2) a tautological ordering assertion in STR-03 that provides no regression protection. The CI workflow has an unconditional integration-test step that will block the entire pipeline on fork PRs where secrets are unavailable.

---

## Critical Issues

### CR-01: `listPending()` does not exclude ERROR items that have exhausted `maxAttempts`

**File:** `lib/services/offline_queue_service.dart:154`
**Issue:** `listPending()` only filters out items with `status == 'SENT'` or `status == 'FAILED'`. An `OfflineEntrega` in `ERROR` state with `attempts >= maxAttempts` satisfies `isPermanentlyFailed == true` but is still returned by `listPending()` because the method never consults that property. In `SyncService._handleError`, items are transitioned to `'FAILED'` only when `attempts >= maxAttempts` at error time; however, if a crash occurs after `attempts` is incremented but before `_handleError` marks the item `FAILED`, the item remains `ERROR` with `attempts == maxAttempts` and will be picked up and retried on every subsequent sync cycle — potentially forever.

None of the stress tests create this boundary scenario (attempts == maxAttempts, status == 'ERROR'), so the regression goes undetected.

**Fix:**
```dart
// In listPending(), replace the current filter block with:
if (e.status == 'SENT' || e.status == 'FAILED') continue;
if (e.attempts >= e.maxAttempts) continue; // exhausted — must be marked FAILED but guard anyway

if (e.status == 'ERROR' && e.nextRetryAt != null) {
  final retryTime = DateTime.tryParse(e.nextRetryAt!);
  if (retryTime != null && retryTime.isAfter(now)) continue;
}
```

Add a corresponding stress test in `offline_queue_stress_test.dart`:
```dart
test('ERROR item with attempts == maxAttempts is excluded from listPending', () async {
  await OfflineQueueService.enqueue(
    _entrega(
      localEventId: 'evt-exhausted',
      status: 'ERROR',
      attempts: 5,
      maxAttempts: 5,
      nextRetryAt: DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
    ),
  );
  final pending = OfflineQueueService.listPending();
  expect(pending.where((e) => e.localEventId == 'evt-exhausted').isEmpty, isTrue);
});
```

---

### CR-02: STR-03 ordering assertion is tautological — provides zero regression protection

**File:** `test/stress/offline_queue_stress_test.dart:167-172`
**Issue:** `listPending()` always calls `out.sort(...)` before returning (service line 165). The test then re-sorts the same returned list and asserts equality. Because the test input is the same as the function's own output, this assertion is always true regardless of whether the sort was correct, present, or in the right direction. A developer could remove or reverse the sort in `listPending()` and this test would still pass.

```dart
// Current — tautological:
final sorted = [...pending]
  ..sort((a, b) => a.createdAtClientIso.compareTo(b.createdAtClientIso));
expect(
  pending.map((e) => e.localEventId).toList(),
  equals(sorted.map((e) => e.localEventId).toList()),
);
```

**Fix:** Assert against a hardcoded expected sequence derived from the known insertion order:
```dart
// Assert exact chronological order (PENDING items 0..29 appear before ERROR-past 45..49)
expect(pending.first.localEventId, equals('evt-pending-0'));
expect(pending[29].localEventId, equals('evt-pending-29'));
expect(pending[30].localEventId, equals('evt-err-past-0'));
expect(pending.last.localEventId, equals('evt-err-past-4'));
```

---

## Warnings

### WR-01: CI Integration Tests step runs unconditionally — blocks workflow on fork PRs

**File:** `.github/workflows/test.yml:41-53`
**Issue:** The "Integration Tests" step has no `if:` condition and no `continue-on-error: true`. On fork pull requests, GitHub Actions does not provide repository secrets; all secret references resolve to empty strings. When `SUPABASE_URL` and `SUPABASE_ANON_KEY` are empty, the integration tests will fail at connection time, blocking the entire CI run. This means external contributors (or CI runs in a fresh repo without secrets configured) cannot get a green build even if their code change is correct.

**Fix:**
```yaml
- name: Integration Tests
  if: >
    secrets.SUPABASE_URL != '' &&
    github.event_name != 'pull_request' ||
    github.event.pull_request.head.repo.full_name == github.repository
  run: flutter test test/integration/supabase/ test/integration/e2e/ --tags integration
  env:
    SUPABASE_URL: ${{ secrets.SUPABASE_URL }}
    # ... rest of env vars
```

Alternatively, add `continue-on-error: true` to prevent it from blocking the full pipeline, and make integration tests an advisory check rather than a gating check.

---

### WR-02: `backoffDelay` getter returns zero delay for `attempts == 0` — dead code with wrong formula

**File:** `lib/services/offline_queue_service.dart:117-120`
**Issue:** The `backoffDelay` getter computes `min(pow(2, attempts - 1).toInt(), 60)`. When `attempts == 0`, `pow(2, -1) == 0.5`, which truncates to `0` via `toInt()`, yielding `Duration(minutes: 0)` — an immediate retry with no delay. The formula in `SyncService._handleError` (line 266) uses the same expression but is called only after `attempts` has already been incremented, so the effective minimum delay there is 1 minute. The `backoffDelay` getter is never called anywhere in the codebase (grep confirms zero call sites), making it dead code with a latent arithmetic bug that would fire if someone used it.

**Fix:** Either delete the dead getter, or fix the formula and add a call-site test:
```dart
// Correct formula (consistent with _handleError):
Duration get backoffDelay {
  if (attempts == 0) return Duration.zero;
  final minutes = min(pow(2, attempts - 1).toInt(), 60);
  return Duration(minutes: minutes);
}
```

---

### WR-03: STR-02 "concurrency" test cannot detect actual concurrency bugs

**File:** `test/stress/offline_queue_stress_test.dart:65-95`
**Issue:** The test description claims "20 enqueues simultáneos" but Dart's event loop is single-threaded. `Future.wait` schedules all futures cooperatively; Hive's `box.put()` operations execute sequentially on the event loop and cannot interleave. This test cannot expose race conditions in the storage layer — it only verifies that 20 sequential async writes produce 20 records, which is already covered by STR-01 at larger scale. The test provides no additional safety guarantee while its misleading description creates false confidence about thread safety.

**Fix:** Either rename the test to accurately describe what it tests ("20 async enqueues via Future.wait produce 20 records"), or replace it with a test that uses `Isolate.spawn` to exercise genuine concurrent Hive access. If the intent is to document that Dart's cooperative model prevents data races by design, add a comment stating that explicitly.

---

### WR-04: GitHub Actions workflow pins actions by mutable tag, not SHA — supply-chain risk

**File:** `.github/workflows/test.yml:18,21,57`
**Issue:** All three `uses:` directives reference mutable version tags (`actions/checkout@v4`, `subosito/flutter-action@v2`, `actions/upload-artifact@v4`). If any of these repositories is compromised or the tag is force-pushed, the workflow will silently run malicious code with access to all repository secrets, including `SUPABASE_SERVICE_ROLE_KEY`.

**Fix:** Pin each action to its full commit SHA:
```yaml
- uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
- uses: subosito/flutter-action@e938fdf56512cc96ef2f93601a5a40a0f9f07f7  # v2.18.0
- uses: actions/upload-artifact@65c4c4a1ddee5b72f698fdd19549f0f0fb45cf08  # v4.6.2
```

Verify current SHAs at https://github.com/actions/checkout/tags before updating.

---

## Info

### IN-01: STR-03 test name mentions "backoff" but does not test `backoffDelay`

**File:** `test/stress/offline_queue_stress_test.dart:97`
**Issue:** The group is named `'STR-03 — filtro backoff bajo carga'` and the test exercises backoff filtering correctly through `listPending()`. However, the actual `backoffDelay` getter on `OfflineEntrega` is never exercised anywhere in the test suite. The group name is slightly misleading — it tests the filter, not the delay computation. Given WR-02 (the getter has a latent bug and is dead code), adding a unit test for the getter would catch the formula error.

**Fix:** Add a unit test for `backoffDelay` in the existing unit test directory, or extend STR-03:
```dart
test('backoffDelay returns correct durations', () {
  expect(_entrega(attempts: 1).backoffDelay, equals(const Duration(minutes: 1)));
  expect(_entrega(attempts: 2).backoffDelay, equals(const Duration(minutes: 2)));
  expect(_entrega(attempts: 6).backoffDelay, equals(const Duration(minutes: 16)));
  expect(_entrega(attempts: 10).backoffDelay, equals(const Duration(minutes: 60)));
});
```

---

_Reviewed: 2026-06-14_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

---
phase: 05-load-stress-tests
plan: "01"
subsystem: offline-queue
tags: [stress-tests, hive, offline-queue, dart, ci]
dependency_graph:
  requires: []
  provides: [test/stress/offline_queue_stress_test.dart]
  affects: [.github/workflows/test.yml]
tech_stack:
  added: []
  patterns: [hive_test lifecycle isolation per group, @Tags stress filtering, Future.wait concurrency test]
key_files:
  created:
    - test/stress/offline_queue_stress_test.dart
  modified:
    - .github/workflows/test.yml
decisions:
  - "Use sequential deterministic IDs (evt-$i) for STR-01/STR-02 instead of UUIDs — faster and predictable"
  - "Each group has isolated setUpTestHive/tearDownTestHive for box isolation between test groups"
  - "Add explicit library directive for @Tags annotation to satisfy library_annotations lint rule"
  - "CI step inserted between Unit & Widget Tests and Integration Tests in existing test job (D-01)"
metrics:
  duration: "~10 minutes"
  completed: "2026-06-14T23:16:35Z"
  tasks_completed: 2
  files_created: 1
  files_modified: 1
---

# Phase 05 Plan 01: Stress Tests OfflineQueueService Summary

Suite de 3 stress tests Dart sobre `OfflineQueueService` que validan integridad de la cola Hive bajo volumen (200 items), concurrencia (20 enqueues simultaneos via `Future.wait`) y filtrado de backoff bajo carga (50 items, exactamente 35 en `listPending()`), sin dependencias de red ni Supabase.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Suite STR-01 y STR-02 (volumen y concurrencia) | 34d6140 | test/stress/offline_queue_stress_test.dart |
| 2 | Test STR-03 (filtro backoff bajo carga) | 34d6140 | test/stress/offline_queue_stress_test.dart |

Nota: Las tareas 1 y 2 se implementaron en un unico archivo en un solo commit, ya que el plan indica un unico archivo de destino y los tests 1 y 2 comparten el mismo factory helper `_entrega()`.

## Verification Results

- `flutter test test/stress/ --tags stress` -> 3/3 tests pasan
- `flutter analyze --no-fatal-infos test/stress/` -> No issues found
- Primera linea del archivo: `@Tags(['stress'])` con directiva `library;`
- Cero dependencias de red, secrets ni clientes Supabase
- `grep -c "setUpTestHive" test/stress/offline_queue_stress_test.dart` -> 3 (>= 2 requerido)

## Success Criteria Verification

- [x] STR-01: 200 enqueues -> `listAll().length == 200`, 200 IDs unicos via Set
- [x] STR-02: `Future.wait` con 20 generates -> `listAll().length == 20`, 20 IDs unicos
- [x] STR-03: 50 items (30 PENDING + 15 ERROR-future + 5 ERROR-past) -> `listPending().length == 35`, orden cronologico verificado
- [x] Tests corren con `--tags stress` sin red ni secrets
- [x] CI step "Stress Tests" agregado a `.github/workflows/test.yml` (sin env block)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Correccion de lint library_annotations**
- **Found during:** Verificacion post-Task 1 con `flutter analyze --no-fatal-infos`
- **Issue:** La anotacion `@Tags(['stress'])` en la primera linea generaba un `info` del analyzer: "This annotation should be attached to a library directive". Aunque el plan usa `--no-fatal-infos` y este es solo un `info`, la correcta ubicacion del @Tags en Dart requiere la directiva `library` explicita.
- **Fix:** Se agrego `library;` despues de `@Tags(['stress'])` en la segunda linea del archivo.
- **Files modified:** test/stress/offline_queue_stress_test.dart
- **Commit:** 34d6140

## Known Stubs

None. Los tests usan datos deterministas, no datos de placeholder ni mocks parciales.

## Threat Flags

No security-relevant surface introduced. El archivo es un test puro sin endpoints ni acceso a red.

## Self-Check: PASSED

- [x] test/stress/offline_queue_stress_test.dart existe (174 lineas)
- [x] .github/workflows/test.yml modificado con step "Stress Tests"
- [x] Commit 34d6140 existe en el log del worktree
- [x] Primera linea del archivo es `@Tags(['stress'])`
- [x] 3 ocurrencias de `setUpTestHive` (una por group)

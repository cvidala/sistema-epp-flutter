---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: milestone
status: executing
last_updated: "2026-08-22T14:03:06.725Z"
last_activity: 2026-08-22 -- Completed quick task 260822-dyl: Suspender módulo Portal DT (seguridad)
progress:
  total_phases: 7
  completed_phases: 1
  total_plans: 4
  completed_plans: 6
  percent: 14
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-13)

**Core value:** Detectar regresiones antes de que lleguen a producción y tener visibilidad en tiempo real del estado del sistema en campo.
**Current focus:** Phase 06 — edge-function-tests

## Current Position

Phase: 06 (edge-function-tests) — EXECUTING
Plan: 1 of 2
Status: Executing Phase 06
Last activity: 2026-06-15 -- Phase 06 execution started

Progress: ░░░░░░░░░░ 0% (0/3 phases complete)

## Milestone v1.0 Summary

**27/27 requirements satisfied** | **68 tests pasando** | **CI/CD verde**

| Phase | Resultado | Tests |
|-------|-----------|-------|
| Phase 1: Unit Tests | Complete | 50 unit tests (hash chain, stock, offline queue) |
| Phase 2: Supabase Tests | Complete | 14 integration tests (RLS, triggers, RPCs) |
| Phase 3: E2E Tests | Complete | 3 service-layer E2E + integration_test/ ready |
| Phase 4: CI/CD Pipeline | Complete | GitHub Actions verde, 11 secrets configurados |

## Milestone v2.0 Scope

**13 requirements** across 3 phases | **0/3 phases complete**

| Phase | Requirements | Key Constraint |
|-------|-------------|----------------|
| Phase 5: Load/Stress Tests | STR-01..04 | Zero new deps, extends hive_test pattern, < 60 s in CI |
| Phase 6: Edge Function Tests | EFN-01..05 | DRY_RUN guard required before any test; separate Deno CI job |
| Phase 7: Golden File Tests | VIS-01..05 | Highest effort: alchemist, flutter_test_config.dart, Linux-only baseline generation |

## Performance Metrics

**By Phase (v1.0):**

| Phase | Plans | Duration |
|-------|-------|----------|
| 01-unit-tests | 1 | ~2 min |
| 02-supabase-tests | 1 | ~90 min |
| 03-e2e-tests | 1 | ~45 min |
| 04-cicd-pipeline | 1 | ~15 min |

**Total v1.0 execution:** ~2.5 horas

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Init: Tests Supabase contra DB real (no mocks) — hubo incidentes por divergencia mock/prod
- Init: QA dentro del mismo repo sistema-epp-flutter — comparte contexto de código
- Phase 1 Plan 01: StockCalculator placed in lib/services/ (not lib/utils/) — no utils/ directory exists in project
- Phase 1 Plan 01: Hash chain tests reimplement _canonicalJson inline to avoid exposing SyncService internals
- Phase 1 Plan 01: validateCart returns failing epp_id (not error string) — UI formatting stays in new_delivery_page.dart
- Phase 1 Plan 01: hive_test 1.0.1 used for Hive lifecycle; each test group gets own setUp/tearDown for isolation
- Phase 2 Plan 01: evaluar_entrega_v2 returns 'accion' (not 'estado') with values OK/WARNING/BLOQUEO — verified against live DB
- Phase 2 Plan 01: anon INSERT requires Prefer:return=minimal — return=representation triggers SELECT that fails for anon role
- Phase 2 Plan 01: entregas_epp BEFORE DELETE trigger blocks service_role — test rows permanent; idempotency via event_id existence check
- Phase 2 Plan 01: TRG-04 audit_log queried by datos_nuevos->>event_id since entregas_epp has no 'id' column (PK is event_id TEXT)
- v2.0 Roadmap: Phase 5 and Phase 6 are technically independent (different toolchains) — can be worked in parallel if desired, but sequential ordering minimizes CI complexity debt at each step
- v2.0 Roadmap: Golden baselines MUST be generated on Linux (CI), never macOS — CoreText vs FreeType font rendering differ pixel-by-pixel
- v2.0 Roadmap: DRY_RUN guard must be added to notif-vencimiento/index.ts BEFORE writing any EFN test — prevents real emails to real users on every CI run
- v2.0 Roadmap: alchemist ^0.14.0 chosen over raw matchesGoldenFile — CI/local dual-mode with obscureText:true solves macOS/Linux font drift

### Pending Todos

- Phase 6 (plan time): Read supabase/functions/notif-vencimiento/index.ts to determine exact pure function extraction boundaries before writing tasks
- Phase 7 (plan time): Inspect ObrasPage, WorkersPage, NewDeliveryPage to determine minimal refactor needed for test-friendly constructors

### Blockers/Concerns

None. v1.0 blockers all resolved. v2.0 ready to start.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260822-dyl | Suspender módulo Portal de Fiscalización DT (cerrar CRITICAL v_asistencias_dt) | 2026-08-22 | 422be7f | [260822-dyl-suspender-modulo-portal-fiscalizacion-dt](./quick/260822-dyl-suspender-modulo-portal-fiscalizacion-dt/) |

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| v3 | Tests de integración completa de notif-vencimiento contra Supabase real | Deferred | 2026-06-13 |
| v3 | Golden tests de pantallas del módulo asistencia (RutInputScreen, CameraCaptureScreen) | Deferred | 2026-06-13 |
| v3 | Tests de otras Edge Functions (no notif-vencimiento) | Deferred | 2026-06-13 |
| v3 | Golden tests dark mode (solo cuando se añada dark theme) | Deferred | 2026-06-13 |
| v3 | Golden tests tablet/large screen (solo cuando se target iPad) | Deferred | 2026-06-13 |

## Session Continuity

Last session: 2026-06-14T01:13:29.004Z
Status: Roadmap v2.0 created — ready to plan Phase 5
Next step: `/gsd-plan-phase 5`

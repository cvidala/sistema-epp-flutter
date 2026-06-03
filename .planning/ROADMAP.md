# Roadmap: TrazApp QA & Quality System

## Overview

Cuatro capas de calidad construidas incrementalmente: unit tests de lógica de negocio crítica (hash chain, stock, offline queue), tests de Supabase contra la DB real (RLS por rol, triggers de inmutabilidad, RPCs), flujos E2E de los caminos críticos del sistema, y finalmente un pipeline CI/CD que bloquea regresiones en cada PR. Cada fase entrega cobertura verificable antes de avanzar a la siguiente.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Unit Tests** - Lógica de negocio crítica cubierta con tests unitarios rápidos (hash chain, stock, offline queue) (completed 2026-06-02)
- [x] **Phase 2: Supabase Tests** - RLS por rol, triggers de inmutabilidad y audit log, y RPCs críticas verificados contra la DB real (completed 2026-06-02)
- [x] **Phase 3: E2E Tests** - Flujos críticos del usuario (entrega EPP, asistencia, sync offline) cubiertos end-to-end (completed 2026-06-02)
- [x] **Phase 4: CI/CD Pipeline** - GitHub Actions ejecuta toda la suite en cada PR y bloquea merges con regresiones (completed 2026-06-02)

## Phase Details

### Phase 1: Unit Tests

**Goal**: La lógica de negocio crítica (hash chain, stock, offline queue) tiene cobertura unitaria que corre en segundos sin dependencias externas
**Depends on**: Nothing (first phase)
**Requirements**: UTL-01, UTL-02, UTL-03, UTL-04, UTL-05
**Success Criteria** (what must be TRUE):

  1. `flutter test test/unit/` pasa los 5 tests en menos de 30 segundos sin Supabase ni red
  2. Una entrega con prev_hash incorrecto hace fallar el test de hash chain
  3. El cálculo de stock disponible (ENTRADA - SALIDA) es correcto para el caso base y el caso de bloqueo por cantidad insuficiente
  4. `OfflineQueueService.listPending` excluye entregas en backoff (nextRetryAt futuro) y devuelve las restantes ordenadas cronológicamente

**Plans**: 1 plan
Plans:

- [ ] 01-01-PLAN.md — Extract StockCalculator, write hash chain / stock / offline queue unit tests (UTL-01 through UTL-05)

### Phase 2: Supabase Tests

**Goal**: RLS por rol, triggers de inmutabilidad/audit y RPCs críticas están verificados contra la base de datos real de Supabase, detectando cualquier cambio de seguridad o comportamiento
**Depends on**: Phase 1
**Requirements**: RLS-01, RLS-02, RLS-03, RLS-04, RLS-05, RLS-06, TRG-01, TRG-02, TRG-03, TRG-04, TRG-05, TRG-06, TRG-07
**Success Criteria** (what must be TRUE):

  1. Un usuario ADMIN puede leer trabajadores de cualquier obra; un SUPERVISOR solo ve las suyas (obra_usuarios)
  2. Un usuario READONLY recibe error al intentar insertar en `entregas_epp`; un usuario anon puede insertar asistencias pero no leerlas
  3. Ningún rol puede ejecutar DELETE en `entregas_epp` ni en `asistencias` (las políticas no_delete bloquean)
  4. El trigger `trg_prevent_stock_negativo` bloquea la salida que deja stock negativo y permite la que tiene stock suficiente
  5. El trigger `trg_entregas_epp_immutable` bloquea UPDATE de campos críticos; `trg_audit_entregas_epp` registra INSERT en audit_log
  6. Las RPCs `evaluar_entrega_v2` y `get_vencimientos_proximos` devuelven el estado correcto para trabajador con EPP completo, sin EPP, y EPP próximo a vencer

**Plans**: 1 plan
Plans:

- [ ] 02-01-PLAN.md — Test infrastructure helpers, RLS tests (RLS-01..06), trigger tests (TRG-01..04), RPC tests (TRG-05..07), and SECURITY-FINDINGS.md

### Phase 3: E2E Tests

**Goal**: Los cinco flujos críticos del sistema (login→obras, entrega EPP online, sync offline, kiosko asistencia, dashboard stock) pasan end-to-end sin errores de consola ni fallos de navegación
**Depends on**: Phase 2
**Requirements**: E2E-01, E2E-02, E2E-03, E2E-04, E2E-05
**Success Criteria** (what must be TRUE):

  1. El flujo login → obras → trabajadores carga sin errores de consola ni excepciones no manejadas
  2. Una entrega EPP completa (selección de items, firma, confirmación) se registra exitosamente en modo online
  3. Una entrega guardada en Hive mientras offline aparece como PENDING y se sincroniza a Supabase al recuperar conexión
  4. El flujo del kiosko de asistencia (ingreso RUT, captura foto, registro) completa sin errores
  5. El dashboard muestra el stock actualizado inmediatamente después de confirmar una entrega EPP

**Plans**: 1 plan
Plans:

- [x] 03-01-PLAN.md — ValueKey identifiers, integration_test setup, E2E-01 through E2E-05 test files

### Phase 4: CI/CD Pipeline

**Goal**: GitHub Actions ejecuta `flutter test` y `flutter analyze` en cada PR y push a main, bloquea merges con tests rojos, y genera reporte de cobertura accesible desde el PR
**Depends on**: Phase 3
**Requirements**: CI-01, CI-02, CI-03, CI-04
**Success Criteria** (what must be TRUE):

  1. Un PR con un test roto no puede mergearse — el check de CI aparece en rojo y bloquea el merge
  2. Un PR sin tests rotos muestra CI verde con `flutter test` y `flutter analyze` pasando
  3. El reporte de cobertura (lcov/html) está disponible como artefacto o comentario en cada PR
  4. El pipeline completo (analyze + test + coverage) termina en menos de 5 minutos en GitHub Actions

**Plans**: 1 plan
Plans:

- [x] 04-01-PLAN.md — GitHub Actions workflow (analyze + unit/widget + integration + coverage upload), .gitignore update, CLAUDE.md CI/CD section

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Unit Tests | 1/1 | Complete | 2026-06-02 |
| 2. Supabase Tests | 1/1 | Complete | 2026-06-02 |
| 3. E2E Tests | 1/1 | Complete | 2026-06-02 |
| 4. CI/CD Pipeline | 1/1 | Complete | 2026-06-02 |

# Roadmap: TrazApp QA & Quality System

## Overview

Cuatro capas de calidad construidas incrementalmente: unit tests de lógica de negocio crítica (hash chain, stock, offline queue), tests de Supabase contra la DB real (RLS por rol, triggers de inmutabilidad, RPCs), flujos E2E de los caminos críticos del sistema, y finalmente un pipeline CI/CD que bloquea regresiones en cada PR. Cada fase entrega cobertura verificable antes de avanzar a la siguiente.

El milestone v2.0 añade tres capas de testing diferidas: stress de la cola offline Hive, tests unitarios Deno de la Edge Function `notif-vencimiento`, y golden file tests de las pantallas Flutter críticas.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Unit Tests** - Lógica de negocio crítica cubierta con tests unitarios rápidos (hash chain, stock, offline queue) (completed 2026-06-02)
- [x] **Phase 2: Supabase Tests** - RLS por rol, triggers de inmutabilidad y audit log, y RPCs críticas verificados contra la DB real (completed 2026-06-02)
- [x] **Phase 3: E2E Tests** - Flujos críticos del usuario (entrega EPP, asistencia, sync offline) cubiertos end-to-end (completed 2026-06-02)
- [x] **Phase 4: CI/CD Pipeline** - GitHub Actions ejecuta toda la suite en cada PR y bloquea merges con regresiones (completed 2026-06-02)
- [x] **Phase 5: Load/Stress Tests** - La cola offline Hive aguanta volumen alto, concurrencia y filtrado de backoff con 200+ items sin corrupciones (completed 2026-06-14)
- [ ] **Phase 6: Edge Function Tests** - `notif-vencimiento` tiene guardia DRY_RUN, lógica pura extraída, y tests Deno que verifican HTML, payload Resend y condiciones límite de fechas
- [ ] **Phase 7: Golden File Tests** - Las tres pantallas críticas (`ObrasPage`, `WorkersPage`, `NewDeliveryPage`) tienen goldens Linux generados por CI que detectan regresiones visuales en cada PR

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

### Phase 5: Load/Stress Tests

**Goal**: La cola offline Hive aguanta volumen alto, concurrencia y filtrado de backoff con 200+ items sin corrupciones de estado ni pérdida de registros, y los tests corren en CI sin dependencias de red
**Depends on**: Phase 4
**Requirements**: STR-01, STR-02, STR-03, STR-04
**Success Criteria** (what must be TRUE):

  1. `flutter test test/stress/ --tags stress` pasa en menos de 60 segundos sin conexión a Supabase ni red
  2. Encolar 200 entregas y llamar `listAll()` devuelve exactamente 200 registros, sin duplicados ni pérdidas
  3. 20 enqueues simultáneos via `Future.wait()` resultan en exactamente 20 registros en el box (sin corrupción de estado)
  4. Con 50+ items en la cola, los items con `nextRetryAt` futuro quedan fuera de `listPending()` y los elegibles se devuelven en orden cronológico

**Plans**: 2 plansPlans:
**Wave 1**

- [x] 05-01-PLAN.md — Crear test/stress/offline_queue_stress_test.dart con los 3 stress tests: volumen 200 (STR-01), concurrencia 20 (STR-02), filtro backoff 50→35 (STR-03)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 05-02-PLAN.md — Agregar paso "Stress Tests" al job test de CI con --tags stress, sin env block (STR-04)

### Phase 6: Edge Function Tests

**Goal**: `notif-vencimiento/index.ts` tiene guardia DRY_RUN que bloquea emails en entornos de test, la lógica de negocio está extraída en funciones puras, y los tests Deno verifican HTML, payload Resend y manejo de errores sin enviar emails reales ni necesitar Supabase
**Depends on**: Phase 4
**Requirements**: EFN-01, EFN-02, EFN-03, EFN-04, EFN-05
**Success Criteria** (what must be TRUE):

  1. `notif-vencimiento/index.ts` lee `Deno.env.get('DRY_RUN')` y retorna inmediatamente sin llamar a Resend cuando la variable está presente
  2. `buildEmailHtml()` es una función pura exportada que acepta datos de trabajadores y devuelve HTML verificable sin importar Supabase ni Resend
  3. `deno test supabase/functions/tests/` pasa completamente sin variables de entorno de producción ni conexión a Supabase
  4. El test que stubea `globalThis.fetch` captura el payload enviado a Resend (URL, destinatario, asunto, HTML) y verifica su estructura
  5. El CI ejecuta `deno test supabase/functions/tests/` en un job separado con `denoland/setup-deno@v2` que pasa en verde

**Plans**: 2 plans
Plans:
**Wave 1**

- [ ] 06-01-PLAN.md — Refactor de index.ts (DRY_RUN guard, exports puros, import.meta.main, sendResendEmail) + tests Deno (HTML, payload Resend) + deno.json (EFN-01..04)

**Wave 2** *(blocked on Wave 1 completion)*

- [ ] 06-02-PLAN.md — Job deno-test separado en CI con denoland/setup-deno@v2 y DRY_RUN=1, sin secrets, + doc en CLAUDE.md (EFN-05)

### Phase 7: Golden File Tests

**Goal**: Las tres pantallas críticas (`ObrasPage`, `WorkersPage`, `NewDeliveryPage`) tienen goldens PNG generados en Linux CI que detectan diferencias visuales en cada PR, con un workflow documentado para regenerar baselines sin usar macOS
**Depends on**: Phase 5
**Requirements**: VIS-01, VIS-02, VIS-03, VIS-04, VIS-05
**Success Criteria** (what must be TRUE):

  1. `flutter test test/golden/ --tags golden` pasa en CI (ubuntu-latest) con los tres goldens sin fallos de font rendering ("Ahem" squares)
  2. Modificar el layout de `ObrasPage`, `WorkersPage` o `NewDeliveryPage` hace fallar el test golden correspondiente en CI
  3. Los widgets de test de las tres pantallas renderizan con datos inyectados sin llamar a Supabase ni `initState` con side effects reales
  4. Los goldens PNG de referencia están committed en el repo, generados en Linux, y `.gitattributes` los marca como binarios
  5. Regenerar los goldens se hace via `workflow_dispatch` en CI con `--update-goldens`, y el resultado se commitea desde el runner de Linux

**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7

Note: Phase 5 and Phase 6 are technically independent (different toolchains). Phase 7 depends on Phase 5 (CI infrastructure for new test tags).

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Unit Tests | 1/1 | Complete | 2026-06-02 |
| 2. Supabase Tests | 1/1 | Complete | 2026-06-02 |
| 3. E2E Tests | 1/1 | Complete | 2026-06-02 |
| 4. CI/CD Pipeline | 1/1 | Complete | 2026-06-02 |
| 5. Load/Stress Tests | 2/2 | Complete   | 2026-06-14 |
| 6. Edge Function Tests | 0/2 | Not started | - |
| 7. Golden File Tests | 0/TBD | Not started | - |

# Requirements — TrazApp QA & Quality System

> Scope: v1 completo — unit tests, Supabase, E2E, CI/CD
> Structure: Vertical MVP — cada fase entrega cobertura funcional de un área

---

## v1 Requirements

### Unit Tests (UTL)

- [x] **UTL-01**: Tests de hash chain — verificar que `prev_hash` se encadena correctamente entre entregas consecutivas
- [x] **UTL-02**: Tests de validación de stock — `_cargarStock` calcula correctamente ENTRADA - SALIDA por bodega+EPP
- [x] **UTL-03**: Tests de validación de stock — bloqueo cuando cantidad > disponible
- [x] **UTL-04**: Tests de `OfflineQueueService.listPending` — filtrado por backoff (ERROR con nextRetryAt futuro excluido)
- [x] **UTL-05**: Tests de `OfflineQueueService.listPending` — ordenado cronológico por createdAt

### Tests Supabase — RLS (RLS)

- [x] **RLS-01**: ADMIN ve todos los trabajadores de todas las obras
- [x] **RLS-02**: SUPERVISOR solo ve trabajadores de sus obras asignadas (obra_usuarios)
- [x] **RLS-03**: READONLY no puede insertar entregas EPP — SECURITY GAP: puede insertar (SF-01 en SECURITY-FINDINGS.md)
- [x] **RLS-04**: Usuario anon (kiosko) puede insertar asistencias pero no leer
- [x] **RLS-05**: Nadie puede eliminar registros de `entregas_epp` (política no_delete + BEFORE DELETE trigger)
- [x] **RLS-06**: Nadie puede eliminar registros de `asistencias` (política no_delete)

### Tests Supabase — Triggers y RPCs (TRG)

- [x] **TRG-01**: `trg_prevent_stock_negativo` bloquea SALIDA que deja stock < 0
- [x] **TRG-02**: `trg_prevent_stock_negativo` permite SALIDA cuando stock suficiente
- [x] **TRG-03**: `trg_entregas_epp_immutable` bloquea UPDATE de campos críticos (items, trabajador_id, obra_id)
- [x] **TRG-04**: `trg_audit_entregas_epp` registra INSERT en audit_log automáticamente
- [x] **TRG-05**: RPC `evaluar_entrega_v2` retorna estado correcto para trabajador con EPP completo
- [x] **TRG-06**: RPC `evaluar_entrega_v2` retorna estado CRITICO (BLOQUEO) para trabajador sin EPP
- [x] **TRG-07**: RPC `get_vencimientos_proximos` retorna EPP próximos a vencer

### Tests E2E (E2E)

- [x] **E2E-01**: Flujo login → obras → trabajadores carga sin errores de consola
- [x] **E2E-02**: Flujo entrega EPP — selección de items, firma, confirmación (modo online)
- [x] **E2E-03**: Flujo sync offline — entrega guardada en Hive, sync al recuperar conexión
- [x] **E2E-04**: Flujo kiosko asistencia — ingreso RUT, captura foto, registro exitoso
- [x] **E2E-05**: Dashboard muestra stock actualizado después de una entrega

### CI/CD (CI)

- [x] **CI-01**: GitHub Actions ejecuta `flutter test` en cada PR y push a main
- [x] **CI-02**: Pipeline falla si algún test falla (bloquea merge)
- [x] **CI-03**: `flutter analyze` corre en CI sin warnings
- [x] **CI-04**: Reporte de cobertura generado y accesible en PR

---

## v2 Requirements — Milestone v2.0: Tests Avanzados

### STR — Load/Stress Tests (Cola Offline)

- [x] **STR-01**: El developer puede ejecutar stress tests que encoluen 200 entregas y verifican que `listPending()` devuelve todas sin duplicados
- [x] **STR-02**: El sistema verifica que 20 enqueues simultáneos (`Future.wait`) no corrompen el estado del box ni pierden registros
- [x] **STR-03**: El sistema verifica que entregas con `nextRetryAt` futuro quedan excluidas de `listPending()` incluso con 50+ items en la cola
- [x] **STR-04**: El CI ejecuta los stress tests con tag `--tags stress` en menos de 60 segundos sin dependencias de red

### EFN — Edge Function Tests (notif-vencimiento)

- [ ] **EFN-01**: El código de `notif-vencimiento/index.ts` tiene una guardia `DRY_RUN` que bloquea el envío de emails en entornos de test
- [ ] **EFN-02**: La lógica de agrupación y filtrado de trabajadores por vencimiento EPP está extraída en una función pura testeable sin Supabase ni Resend
- [ ] **EFN-03**: El developer puede ejecutar unit tests Deno que verifican que `buildEmailHtml()` genera HTML correcto para trabajadores con EPP próximo a vencer
- [ ] **EFN-04**: Los tests Deno verifican que el stub de `globalThis.fetch` captura el payload enviado a Resend (destinatario, asunto, HTML) sin enviar emails reales
- [ ] **EFN-05**: El CI ejecuta `deno test supabase/functions/tests/` en un job separado con `denoland/setup-deno@v2`

### VIS — Golden File Tests (Pantallas Flutter)

- [ ] **VIS-01**: Las tres pantallas críticas (`ObrasPage`, `WorkersPage`, `NewDeliveryPage`) tienen constructores o helpers de test que inyectan datos sin llamadas a Supabase en `initState`
- [ ] **VIS-02**: `flutter_test_config.dart` carga las fonts del proyecto para que los goldens muestren texto real en lugar de "Ahem" squares
- [ ] **VIS-03**: El developer puede generar golden files en Linux (CI) que representan el estado visual correcto de las tres pantallas con datos inyectados
- [ ] **VIS-04**: El CI ejecuta `flutter test test/golden/ --tags golden` y falla si cualquier pantalla difiere del golden de referencia
- [ ] **VIS-05**: La actualización de goldens se hace via un job CI con `workflow_dispatch` + `--update-goldens`, no manualmente desde macOS

---

## Future Requirements (fuera de v2.0)

- Tests de integración completa de `notif-vencimiento` contra Supabase real (`supabase functions serve`)
- Golden tests de pantallas del módulo asistencia (`RutInputScreen`, `CameraCaptureScreen`)
- Tests de otras Edge Functions

## Out of Scope

- Screenshot testing pixel-perfect (muy frágil en mobile)
- Tests de rendimiento de la BD (no es prioridad)
- Tests de otras Edge Functions además de `notif-vencimiento`
- Golden tests generados en macOS (siempre en Linux)

---

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| UTL-01 | Phase 1: Unit Tests | Complete |
| UTL-02 | Phase 1: Unit Tests | Complete |
| UTL-03 | Phase 1: Unit Tests | Complete |
| UTL-04 | Phase 1: Unit Tests | Complete |
| UTL-05 | Phase 1: Unit Tests | Complete |
| RLS-01 | Phase 2: Supabase Tests | Complete |
| RLS-02 | Phase 2: Supabase Tests | Complete |
| RLS-03 | Phase 2: Supabase Tests | Complete (security gap documented — SF-01) |
| RLS-04 | Phase 2: Supabase Tests | Complete |
| RLS-05 | Phase 2: Supabase Tests | Complete |
| RLS-06 | Phase 2: Supabase Tests | Complete |
| TRG-01 | Phase 2: Supabase Tests | Complete |
| TRG-02 | Phase 2: Supabase Tests | Complete |
| TRG-03 | Phase 2: Supabase Tests | Complete |
| TRG-04 | Phase 2: Supabase Tests | Complete |
| TRG-05 | Phase 2: Supabase Tests | Complete |
| TRG-06 | Phase 2: Supabase Tests | Complete |
| TRG-07 | Phase 2: Supabase Tests | Complete |
| E2E-01 | Phase 3: E2E Tests | Complete |
| E2E-02 | Phase 3: E2E Tests | Complete |
| E2E-03 | Phase 3: E2E Tests | Complete |
| E2E-04 | Phase 3: E2E Tests | Complete |
| E2E-05 | Phase 3: E2E Tests | Complete |
| CI-01 | Phase 4: CI/CD Pipeline | Complete |
| CI-02 | Phase 4: CI/CD Pipeline | Complete |
| CI-03 | Phase 4: CI/CD Pipeline | Complete |
| CI-04 | Phase 4: CI/CD Pipeline | Complete |
| STR-01 | Phase 5: Load/Stress Tests | Complete |
| STR-02 | Phase 5: Load/Stress Tests | Complete |
| STR-03 | Phase 5: Load/Stress Tests | Complete |
| STR-04 | Phase 5: Load/Stress Tests | Complete |
| EFN-01 | Phase 6: Edge Function Tests | Pending |
| EFN-02 | Phase 6: Edge Function Tests | Pending |
| EFN-03 | Phase 6: Edge Function Tests | Pending |
| EFN-04 | Phase 6: Edge Function Tests | Pending |
| EFN-05 | Phase 6: Edge Function Tests | Pending |
| VIS-01 | Phase 7: Golden File Tests | Pending |
| VIS-02 | Phase 7: Golden File Tests | Pending |
| VIS-03 | Phase 7: Golden File Tests | Pending |
| VIS-04 | Phase 7: Golden File Tests | Pending |
| VIS-05 | Phase 7: Golden File Tests | Pending |

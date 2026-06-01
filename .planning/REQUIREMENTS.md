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

- [ ] **RLS-01**: ADMIN ve todos los trabajadores de todas las obras
- [ ] **RLS-02**: SUPERVISOR solo ve trabajadores de sus obras asignadas (obra_usuarios)
- [ ] **RLS-03**: READONLY no puede insertar entregas EPP
- [ ] **RLS-04**: Usuario anon (kiosko) puede insertar asistencias pero no leer
- [ ] **RLS-05**: Nadie puede eliminar registros de `entregas_epp` (política no_delete)
- [ ] **RLS-06**: Nadie puede eliminar registros de `asistencias` (política no_delete)

### Tests Supabase — Triggers y RPCs (TRG)

- [ ] **TRG-01**: `trg_prevent_stock_negativo` bloquea SALIDA que deja stock < 0
- [ ] **TRG-02**: `trg_prevent_stock_negativo` permite SALIDA cuando stock suficiente
- [ ] **TRG-03**: `trg_entregas_epp_immutable` bloquea UPDATE de campos críticos (items, trabajador_id, obra_id)
- [ ] **TRG-04**: `trg_audit_entregas_epp` registra INSERT en audit_log automáticamente
- [ ] **TRG-05**: RPC `evaluar_entrega_v2` retorna estado correcto para trabajador con EPP completo
- [ ] **TRG-06**: RPC `evaluar_entrega_v2` retorna estado CRITICO para trabajador sin EPP
- [ ] **TRG-07**: RPC `get_vencimientos_proximos` retorna EPP próximos a vencer

### Tests E2E (E2E)

- [ ] **E2E-01**: Flujo login → obras → trabajadores carga sin errores de consola
- [ ] **E2E-02**: Flujo entrega EPP — selección de items, firma, confirmación (modo online)
- [ ] **E2E-03**: Flujo sync offline — entrega guardada en Hive, sync al recuperar conexión
- [ ] **E2E-04**: Flujo kiosko asistencia — ingreso RUT, captura foto, registro exitoso
- [ ] **E2E-05**: Dashboard muestra stock actualizado después de una entrega

### CI/CD (CI)

- [ ] **CI-01**: GitHub Actions ejecuta `flutter test` en cada PR y push a main
- [ ] **CI-02**: Pipeline falla si algún test falla (bloquea merge)
- [ ] **CI-03**: `flutter analyze` corre en CI sin warnings
- [ ] **CI-04**: Reporte de cobertura generado y accesible en PR

---

## v2 Requirements (deferred)

- Tests de carga / stress sobre la cola offline con cientos de entregas simultáneas
- Tests de Edge Functions (notif-vencimiento)
- Tests de geofencing
- Snapshot tests visuales de pantallas Flutter

---

## Out of Scope

- Screenshot testing pixel-perfect (muy frágil en mobile)
- Tests de rendimiento de la BD (no es prioridad)
- Tests de Edge Functions en Supabase (validados via RPCs)

---

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| UTL-01 | Phase 1: Unit Tests | Complete |
| UTL-02 | Phase 1: Unit Tests | Complete |
| UTL-03 | Phase 1: Unit Tests | Complete |
| UTL-04 | Phase 1: Unit Tests | Complete |
| UTL-05 | Phase 1: Unit Tests | Complete |
| RLS-01 | Phase 2: Supabase Tests | Pending |
| RLS-02 | Phase 2: Supabase Tests | Pending |
| RLS-03 | Phase 2: Supabase Tests | Pending |
| RLS-04 | Phase 2: Supabase Tests | Pending |
| RLS-05 | Phase 2: Supabase Tests | Pending |
| RLS-06 | Phase 2: Supabase Tests | Pending |
| TRG-01 | Phase 2: Supabase Tests | Pending |
| TRG-02 | Phase 2: Supabase Tests | Pending |
| TRG-03 | Phase 2: Supabase Tests | Pending |
| TRG-04 | Phase 2: Supabase Tests | Pending |
| TRG-05 | Phase 2: Supabase Tests | Pending |
| TRG-06 | Phase 2: Supabase Tests | Pending |
| TRG-07 | Phase 2: Supabase Tests | Pending |
| E2E-01 | Phase 3: E2E Tests | Pending |
| E2E-02 | Phase 3: E2E Tests | Pending |
| E2E-03 | Phase 3: E2E Tests | Pending |
| E2E-04 | Phase 3: E2E Tests | Pending |
| E2E-05 | Phase 3: E2E Tests | Pending |
| CI-01 | Phase 4: CI/CD Pipeline | Pending |
| CI-02 | Phase 4: CI/CD Pipeline | Pending |
| CI-03 | Phase 4: CI/CD Pipeline | Pending |
| CI-04 | Phase 4: CI/CD Pipeline | Pending |

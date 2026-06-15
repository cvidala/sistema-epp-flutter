---
phase: 06-edge-function-tests
plan: "01"
subsystem: edge-functions
tags: [deno, testing, edge-functions, refactor, dry-run]
dependency_graph:
  requires: []
  provides:
    - notif-vencimiento/index.ts exports puros (buildEmailHtml, formatFecha, sendResendEmail, Vencimiento, Destinatario)
    - supabase/functions/tests/notif-vencimiento-test.ts (6 tests Deno)
    - supabase/functions/tests/deno.json
  affects:
    - supabase/functions/notif-vencimiento/index.ts
tech_stack:
  added: []
  patterns:
    - import.meta.main guard para aislamiento de entry point Deno
    - DRY_RUN environment variable guard para test safety
    - globalThis.fetch spy con jsr:@std/testing/mock para captura de payload HTTP
    - Exports puros de funciones de presentación sin I/O
key_files:
  created:
    - supabase/functions/tests/notif-vencimiento-test.ts
    - supabase/functions/tests/deno.json
  modified:
    - supabase/functions/notif-vencimiento/index.ts
decisions:
  - Usar especificadores jsr: directos en el test file (no alias de deno.json) para evitar el problema de resolución de subpaths con @std/testing/mock
  - Mover SUPABASE_URL, SUPABASE_SERVICE_KEY y RESEND_API_KEY dentro de if (import.meta.main) para que importar el módulo no dispare null-assertions
  - FROM_EMAIL y DASHBOARD_URL permanecen en nivel de módulo (los necesitan sendResendEmail y buildEmailHtml al importarse)
  - Test 6 (DRY_RUN) verifica semántica de la guardia; cobertura end-to-end del handler delegada a CI Wave 2 (Plan 06-02)
metrics:
  duration: "4 minutes"
  completed: "2026-06-14"
  tasks_completed: 2
  tasks_total: 2
  files_created: 2
  files_modified: 1
---

# Phase 06 Plan 01: Refactor notif-vencimiento y Tests Deno Summary

**One-liner:** Refactorización de `notif-vencimiento/index.ts` con exports puros, guardia DRY_RUN e `import.meta.main`, más 6 tests Deno que cubren HTML, payload Resend y semántica DRY_RUN usando `jsr:@std/testing/mock` sin Supabase ni red real.

## Tareas Completadas

| Tarea | Nombre | Commit | Archivos |
|-------|--------|--------|----------|
| 1 | Refactorizar index.ts — exports puros, DRY_RUN guard, import.meta.main, sendResendEmail | 2f40655 | supabase/functions/notif-vencimiento/index.ts |
| 2 | Crear tests Deno (HTML, DRY_RUN, payload Resend) y deno.json | 464261e | supabase/functions/tests/notif-vencimiento-test.ts, supabase/functions/tests/deno.json |

## Decisiones Técnicas

**1. Especificadores `jsr:` directos para @std/testing/mock**

El import usa `jsr:@std/testing/mock@1` directamente en lugar de confiar en el mapeo de `deno.json`. La razón: un mapeo `"@std/testing": "jsr:@std/testing@1"` en deno.json NO resuelve el subpath `/mock` en runtime. El especificador directo elimina esta dependencia frágil. El `deno.json` se crea de igual forma con las tres entradas (incluyendo `"@std/testing/mock"`) para silenciar warnings de Deno 2.x.

**2. Estructura de `import.meta.main`**

Los secrets con null-assertion (`!`) se movieron dentro del guard. `FROM_EMAIL` y `DASHBOARD_URL` permanecen a nivel de módulo porque los necesitan `sendResendEmail` y `buildEmailHtml` respectivamente al importarse desde el test file.

**3. Test DRY_RUN (Test 6) — semántica vs. integración**

El handler real de `Deno.serve` no es importable (vive dentro de `import.meta.main`). El test 6 verifica la SEMÁNTICA: con `DRY_RUN` activo, la rama de envío no ejecuta y `assertSpyCalls(mockFetch, 0)` pasa. La cobertura end-to-end del handler real se completa en el job `deno-test` del Plan 06-02 (Wave 2), que corre con `DRY_RUN: "1"`.

## Verificación Estática (sin Deno local)

```
grep -c "export function buildEmailHtml|export async function sendResendEmail" index.ts  # 2 (OK)
grep -q "if (import.meta.main)" index.ts                                                  # exit 0 (OK)
grep -q "Deno.env.get('DRY_RUN')" index.ts                                               # exit 0 (OK)
grep -q "jsr:@std/testing/mock@1" notif-vencimiento-test.ts                              # exit 0 (OK)
grep -c "Deno.test(" notif-vencimiento-test.ts                                            # 6 (OK, >= 5)
```

## Verificación Delegada a CI Wave 2

Deno no está instalado localmente. La ejecución de `deno test supabase/functions/tests/ --allow-env --allow-read` se delega al job `deno-test` del Plan 06-02. Ese job usa `denoland/setup-deno@v2` con `deno-version: v2.x` y corre con `DRY_RUN: "1"`. El job verificará que los 6 tests pasen en verde sin variables de producción, sin red y sin Supabase.

## Deviaciones del Plan

Ninguna — el plan se ejecutó exactamente como estaba escrito.

## Threat Flags

Ninguno — no se introdujeron nuevas superficies de red, autenticación o acceso a archivos más allá de lo especificado en el threat model del plan.

## Known Stubs

Ninguno — todos los tests usan datos de fixture concretos y las funciones exportadas son funciones puras reales.

## Self-Check: PASSED

- `supabase/functions/notif-vencimiento/index.ts` existe y contiene exports: FOUND
- `supabase/functions/tests/notif-vencimiento-test.ts` existe: FOUND
- `supabase/functions/tests/deno.json` existe: FOUND
- Commit 2f40655 existe: FOUND
- Commit 464261e existe: FOUND

---
phase: 06-edge-function-tests
plan: "02"
subsystem: ci-cd
tags: [deno, ci, github-actions, edge-functions, documentation]
dependency_graph:
  requires:
    - 06-01 (tests Deno existentes en supabase/functions/tests/)
  provides:
    - .github/workflows/test.yml job deno-test (EFN-05)
    - Documentacion del comando deno test en CLAUDE.md seccion CI/CD
  affects:
    - .github/workflows/test.yml
    - CLAUDE.md
tech_stack:
  added:
    - denoland/setup-deno@v2 (GitHub Action para instalar Deno en CI)
  patterns:
    - Job CI paralelo sin needs: (independencia entre Flutter y Deno)
    - DRY_RUN como unica variable de entorno del job Deno (sin secrets de produccion)
    - Permisos Deno minimos: --allow-env --allow-read (sin --allow-net)
key_files:
  created: []
  modified:
    - .github/workflows/test.yml
    - CLAUDE.md
decisions:
  - Job deno-test sin needs: — corre en paralelo al job Flutter (EFN-05 requiere job separado e independiente)
  - Solo DRY_RUN en env del job Deno — sin secrets de Supabase ni Resend (T-06-04)
  - --allow-env --allow-read sin --allow-net — fetch stubbeado en tests; restriccion de red a nivel runtime (T-06-05)
  - timeout-minutes 5 — corta el job si hay cuelgue de red (T-06-05)
metrics:
  duration: "3 minutes"
  completed: "2026-06-15"
  tasks_completed: 2
  tasks_total: 2
  files_created: 0
  files_modified: 2
---

# Phase 06 Plan 02: Job Deno-Test en CI y Documentacion CLAUDE.md Summary

**One-liner:** Job `deno-test` separado en GitHub Actions usando `denoland/setup-deno@v2`, corriendo `deno test supabase/functions/tests/ --allow-env --allow-read` con `DRY_RUN: "1"` en paralelo al job Flutter, sin secrets de produccion.

## Tareas Completadas

| Tarea | Nombre | Commit | Archivos |
|-------|--------|--------|----------|
| 1 | Agregar job deno-test separado a test.yml | f2f87dd | .github/workflows/test.yml |
| 2 | Documentar comando deno test en CLAUDE.md | a538c8e | CLAUDE.md |

## Decisiones Tecnicas

**1. Paralelismo sin needs:**

El job `deno-test` no declara `needs: [test]`. Los dos jobs (Flutter y Deno) corren en paralelo en CI. Una falla en Deno no bloquea el job Flutter ni viceversa (T-06-06 mitigado). EFN-05 requiere explicitamente un job separado, no un step adicional dentro del job Flutter.

**2. Aislamiento de secrets:**

El bloque `env:` del job `deno-test` contiene unicamente `DRY_RUN: "1"`. No se declara ningun `secrets.SUPABASE_*` ni `secrets.RESEND_*`. Los tests usan `jsr:@std/testing/mock` para stubbear `globalThis.fetch` — no se necesita red real ni credenciales (T-06-04 mitigado).

**3. Permisos Deno minimos:**

`--allow-env --allow-read` en lugar de `--allow-all`. La ausencia de `--allow-net` agrega una capa de proteccion: si un test fallara en stubbear fetch, Deno bloquearia la conexion de red a nivel de runtime antes de que llegue a `api.resend.com` (T-06-05 mitigado junto con `timeout-minutes: 5`).

**4. Sincronizacion del worktree:**

El worktree fue creado antes de que el step `Stress Tests` se mergeara a main (Phase 05). La escritura del archivo `test.yml` incluyo ese step para evitar regresion al mergear.

## Verificacion Estatica

```
grep -q "deno-test:" .github/workflows/test.yml          # exit 0 (OK)
grep -q "denoland/setup-deno@v2" .github/workflows/test.yml  # exit 0 (OK)
grep -q "deno-version: v2.x" .github/workflows/test.yml   # exit 0 (OK)
grep -q "deno test supabase/functions/tests/ --allow-env --allow-read" .github/workflows/test.yml  # exit 0 (OK)
grep -q 'DRY_RUN: "1"' .github/workflows/test.yml        # exit 0 (OK)
grep -q "needs:" .github/workflows/test.yml               # exit 1 (no needs — OK)
grep -q "deno test supabase/functions/tests/" CLAUDE.md   # exit 0 (OK)
grep -q "brew install deno" CLAUDE.md                     # exit 0 (OK)
```

## Verificacion Funcional (requiere push/PR)

Al abrir un PR a `main`, el check `deno-test` debe aparecer en verde en paralelo al check `test` (Flutter). Los 6 tests de `supabase/functions/tests/notif-vencimiento-test.ts` creados en Plan 06-01 deben pasar con `DRY_RUN=1`.

## Deviaciones del Plan

**1. [Regla 3 - Auto-fix] Sincronizacion del step Stress Tests**

- **Encontrado en:** Tarea 1 (al leer test.yml del worktree)
- **Problema:** El worktree fue creado antes de que el commit del job Stress Tests (Phase 05) se mergeara a main. El archivo `test.yml` del worktree le faltaba ese step, lo que hubiera causado una regresion al mergear.
- **Fix:** Se incluyo el step `Stress Tests` en la escritura del archivo junto con el nuevo job `deno-test`.
- **Archivos modificados:** `.github/workflows/test.yml`
- **Commit:** f2f87dd

## Threat Flags

Ninguno — no se introdujeron nuevas superficies de red, autenticacion o acceso a archivos. El job `deno-test` es el inverso: restringe la superficie (sin secrets, sin --allow-net).

## Known Stubs

Ninguno.

## Self-Check: PASSED

- `.github/workflows/test.yml` contiene job deno-test: FOUND
- `.github/workflows/test.yml` contiene denoland/setup-deno@v2: FOUND
- `CLAUDE.md` contiene deno test supabase/functions/tests/: FOUND
- `CLAUDE.md` contiene brew install deno: FOUND
- Commit f2f87dd existe: FOUND
- Commit a538c8e existe: FOUND

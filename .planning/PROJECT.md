# TrazApp — QA & Quality System

## What This Is

Suite de calidad integral para TrazApp, integrada dentro del mismo repo `sistema-epp-flutter`. Cubre cuatro capas de testing y monitoreo para garantizar la confiabilidad de un sistema de cumplimiento normativo EPP en obras de construcción.

**Core Value:** Detectar regresiones antes de que lleguen a producción y tener visibilidad en tiempo real del estado del sistema en campo.

## Context

**Sistema bajo test:** TrazApp — app Flutter para gestión de Equipos de Protección Personal (EPP) y control de asistencia en obras de construcción.

**Stack:** Flutter/Dart, Supabase (PostgreSQL + Auth + Storage + Edge Functions), Hive (offline), Google ML Kit (face detection).

**Dos entry points:** `main.dart` (app EPP, usuarios autenticados) y `main_asistencia.dart` (kiosko de asistencia, anon key).

**Criticidad:** Sistema de cumplimiento normativo — errores en entrega EPP o cadena de hashes tienen consecuencias legales. El sistema incluye lógica de inmutabilidad y auditoría que debe verificarse.

## Problem

- TrazApp tiene ~13.500 líneas de Dart + SQL complejo (triggers, RLS, RPCs) sin tests automatizados
- La lógica offline (cola Hive, backoff, sync) es difícil de verificar manualmente
- La cadena de hashes e inmutabilidad de `entregas_epp` son críticas y no tienen cobertura
- El RLS de Supabase (seguridad por rol) no tiene tests de regresión

## Who It's For

- **Desarrollador (tú):** Detectar regresiones rápido antes de cada deploy
- **Sistema:** CI/CD automático que bloquea merges que rompan lógica crítica

## What Done Looks Like

- Un `flutter test` corre y da feedback en < 2 minutos sobre lógica de negocio crítica
- Los tests de Supabase verifican RLS, triggers e inmutabilidad contra la DB real
- Los flujos E2E críticos (entrega EPP, asistencia, sync offline) están cubiertos
- Un dashboard o reporte simple muestra el estado de salud del sistema

## Current Milestone: v2.0 Tests Avanzados

**Goal:** Cubrir las tres capas de testing diferidas en v1.0 — stress de la cola offline, Edge Functions de notificaciones, y regresión visual de pantallas Flutter.

**Target features:**
- Load/stress tests cola offline (Hive queue: concurrencia, volumen, backoff bajo carga)
- Tests Edge Functions `notif-vencimiento` (invocación, emails Resend, fechas límite)
- Snapshot tests visuales Flutter (golden file tests de pantallas críticas)

## Requirements

### Validated (existente en TrazApp)

- ✓ Auth con roles ADMIN/SUPERVISOR/READONLY — existente
- ✓ Entrega EPP con cadena de hashes (prev_hash/hash) — existente
- ✓ Cola offline (Hive) con backoff exponencial y sync automático — existente
- ✓ Datos forenses (GPS + device info) en cada firma — existente
- ✓ Trigger de inmutabilidad en `entregas_epp` — existente
- ✓ Audit log automático en 7 tablas críticas — existente
- ✓ RLS en todas las tablas principales — existente
- ✓ Kiosko de asistencia con detección facial — existente
- ✓ Notificaciones de vencimiento EPP via cron + Resend — existente

### Active (v2.0 — a construir)

- [ ] Load/stress tests cola offline (Hive): concurrencia, volumen alto, backoff bajo carga
- [ ] Tests Edge Functions `notif-vencimiento`: invocación, emails Resend, condiciones límite de fechas
- [ ] Golden file tests de pantallas Flutter críticas: ObrasPage, WorkersPage, NewDeliveryPage

### Validated (v1.0 — entregado 2026-06-02)

- ✓ Tests unitarios hash chain, StockCalculator, OfflineQueueService — 50 tests
- ✓ Tests Supabase RLS por rol (ADMIN, SUPERVISOR, READONLY, anon) — 14 tests
- ✓ Tests triggers inmutabilidad, audit log, RPCs evaluar_entrega_v2 — incluidos arriba
- ✓ Tests E2E flujos críticos (login→obras, entrega EPP, sync offline, kiosko) — 3 service-layer
- ✓ CI/CD GitHub Actions: flutter analyze + flutter test + cobertura en cada PR

### Out of Scope

- Tests de performance/load de red o Supabase — no es prioridad actual
- Tests de otras Edge Functions (no notif-vencimiento)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| QA dentro del mismo repo | Más simple, comparte contexto de código, sin sincronización entre repos | — Confirmado |
| Tests Supabase contra DB real (no mocks) | Hubo incidentes por divergencia mock/prod; el RLS y triggers solo se validan en real | — Confirmado |
| Cobertura por capas (unit → integration → E2E) | Permite feedback rápido en lower layers, E2E para flujos críticos | — Pendiente |

## Evolution

Este documento evoluciona en cada transición de fase.

**Después de cada fase** (via `/gsd-transition`):
1. Requirements completados → mover a Validated
2. Nuevos requirements emergentes → agregar a Active
3. Decisiones clave → agregar a Key Decisions

---
*Last updated: 2026-06-13 — milestone v2.0 iniciado*

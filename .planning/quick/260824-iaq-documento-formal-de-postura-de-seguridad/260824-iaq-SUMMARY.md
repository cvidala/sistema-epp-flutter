---
quick_id: 260824-iaq
slug: documento-formal-de-postura-de-seguridad
date: 2026-08-24
status: complete
commit: bebe379
branch: docs/seguridad
---

# Quick Task 260824-iaq — Summary

## Qué se hizo

Se creó `docs/SEGURIDAD.md`: documento formal de postura de seguridad de
TrazApp, en español, orientado a clientes y fiscalización DT. Describe solo
controles efectivamente implementados y verificados.

Secciones: resumen ejecutivo; cifrado en tránsito (TLS 1.3 por defecto / 1.2
mínimo, verificado; ATS iOS, Android sin cleartext); cifrado en reposo
(servidor AES-256, caché local Hive cifrada); control de acceso (RLS
multi-tenant vía get_user_org_id, roles, service_role fuera de la app);
buckets privados + signed URLs; integridad forense (hash chain, inmutabilidad,
no-delete, audit_log); biometría sin template facial; marco normativo
(Ley 19.628 / 21.719, Res. Exenta N°38 DT); y comandos de re-verificación.

## Notas

- Documento vivo, fechado 2026-08-24. No es asesoría legal.
- `docs/**` no dispara `deploy.yml` (solo dashboard/website/inspector) y `*.md`
  está excluido de gh-pages, así que no se publica en el sitio.

## Commits

- `bebe379` — docs(security): documento formal de postura de seguridad

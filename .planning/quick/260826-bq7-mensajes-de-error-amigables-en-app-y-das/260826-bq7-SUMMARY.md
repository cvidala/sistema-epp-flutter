---
quick_id: 260826-bq7
slug: mensajes-de-error-amigables-en-app-y-das
date: 2026-08-26
status: complete
branch: fix/friendly-error-messages
---

# Quick Task 260826-bq7 — Summary

Traducción de errores crudos a mensajes amigables (app + dashboard).
- lib/services/error_messages.dart (nuevo): friendlyError(e) — red/credenciales/permiso/genérico.
- App: main.dart (login), stock_entry_page, stock_page, obras_page.
- Dashboard: helper mensajeError() + reemplazo de ~20 .message crudos en catch
  (textContent/innerHTML/alert). Logs de consola y checks .includes NO tocados.
- Verificado: flutter analyze limpio (5 archivos) · node --check dashboard OK.

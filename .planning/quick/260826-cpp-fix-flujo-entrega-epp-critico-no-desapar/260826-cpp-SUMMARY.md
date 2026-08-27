---
quick_id: 260826-cpp
slug: fix-flujo-entrega-epp-critico-no-desapar
date: 2026-08-26
status: complete
branch: fix/entrega-epp-critico-stock
---

# Quick Task 260826-cpp — Summary

Dos fixes de UX en lib/new_delivery_page.dart (detectados en terreno):
- Bug 1: el ítem crítico desaparecía de la lista al agregarlo. Fix: el filtro de
  soloPendientes ahora mantiene el ítem si `pendientes.contains(id) || carrito.containsKey(id)`.
- Bug 2: se podía agregar un EPP sin stock y fallaba al guardar. Fix: el botón "+"
  inicial se deshabilita (gris) cuando `sinStock`. Validación final en _guardar() intacta.
Verificado: flutter analyze sin issues.

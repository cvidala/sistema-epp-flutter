---
quick_id: 260826-d9c
slug: permitir-entrega-epp-con-critico-sin-sto
date: 2026-08-26
status: complete
branch: feat/entrega-critico-sin-stock
---

# Quick Task 260826-d9c — Summary

Permitir entrega EPP cuando un crítico falta por falta de stock (solo new_delivery_page.dart):
- Getter _bloqueoSoloPorStock + helper _sinStockCritico (usan stockDisponible).
- Botón Guardar se habilita cuando el BLOQUEO es solo por stock.
- _guardar: separa críticos por stock. Con stock (o indeterminado) → sigue bloqueando.
  Todos sin stock → diálogo _dialogFaltaStock, registra motivo en la evaluación
  (epp_no_entregado_sin_stock) y guarda _faltantesSinStock.
- Tras guardar: inserta solicitud automática en solicitudes_epp (best-effort).
Seguimiento: offline + render del motivo en comprobante (TODO en código).
Verificado: flutter analyze sin issues.

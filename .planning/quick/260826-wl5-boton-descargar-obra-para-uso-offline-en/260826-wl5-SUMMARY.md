---
quick_id: 260826-wl5
slug: boton-descargar-obra-para-uso-offline-en
date: 2026-08-26
status: complete
branch: feat/descargar-obra-offline
---

# Quick Task 260826-wl5 — Summary

Botón "Descargar para uso sin conexión" por obra en ObrasPage (MVP offline dirigido).
- lib/services/obra_offline_service.dart (nuevo): descargarObra(obraId) cachea
  trabajadores_activos + bodegas + catalogo_epp + stock (mapa por bodega) + descarga_ts,
  en las MISMAS claves de CacheService que leen workers_page y new_delivery_page offline.
- obras_page.dart: estado _descargando, método _descargarObra, botón por obra
  (cloud_download/cloud_done + spinner) en el trailing de la tarjeta.
- new_delivery_page.dart: _cargarStock lee 'stock' cacheado cuando modoOffline;
  se invoca en la rama offline de _loadInit.
Seguimiento: semáforo/pendientes offline (fase 2). Verificado: flutter analyze sin issues.

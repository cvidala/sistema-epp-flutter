---
quick_id: 260823-uf7
slug: cifrar-cache-local-hive-con-hiveaesciphe
date: 2026-08-23
status: complete
commit: 4a1c12e
branch: fix/encrypt-hive-cache
---

# Quick Task 260823-uf7 — Summary

## Qué se hizo

Cifrado en reposo de la caché local Hive. Las 5 boxes ahora se abren con
`HiveAesCipher` usando una clave AES-256 generada una vez por instalación y
guardada en `flutter_secure_storage` (Keychain iOS / Keystore Android), nunca
en la propia caché.

Archivos:
- `lib/services/secure_hive.dart` (nuevo): `SecureHive.cipher()` lazy + cache en
  memoria; `debugSetTestCipher()` (@visibleForTesting) para el entorno de test.
- Cifradas: `outbox_entregas` (offline_queue_service), `cache_api`
  (cache_service), `trazapp_offline_cache` (offline_cache_service),
  `device_config` (device_id_service), `asistencias_pendientes`
  (asistencia_hive_service).
- `pubspec.yaml` + `pubspec.lock`: `flutter_secure_storage ^9.2.2`.
- Tests (offline_queue unit/stress/e2e): `SecureHive.debugSetTestCipher()` en
  setUp — flutter_secure_storage no tiene plugin nativo en `flutter test`.

## Verificación

- `flutter analyze` (lib + test): sin issues.
- `flutter test test/unit/offline_queue_test.dart`: 14/14 verdes.
- `flutter test test/stress/ --tags stress`: 3/3 verdes.

## Notas

- App aún no entregada → sin migración de datos (abrir una box vieja sin cifrar
  con cipher fallaría, pero no hay instalaciones en terreno).
- Cierra el último pendiente de la auditoría de datos sensibles.

## Commits

- `4a1c12e` — feat(security): cifrar caché local Hive en reposo (AES-256)

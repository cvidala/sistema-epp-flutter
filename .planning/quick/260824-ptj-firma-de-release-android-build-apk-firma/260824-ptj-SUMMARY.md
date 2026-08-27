---
quick_id: 260824-ptj
slug: firma-de-release-android-build-apk-firma
date: 2026-08-24
status: complete
commit: 75eb0de
branch: chore/android-release-signing
---

# Quick Task 260824-ptj — Summary

## Qué se hizo
- Keystore de upload generado en `~/.trazapp/upload-keystore.jks` (PKCS12, RSA 2048,
  alias `trazapp-upload`, validez 10000 días), contraseña fuerte aleatoria.
- `android/key.properties` (gitignored) con las credenciales + ruta absoluta al keystore.
- `android/app/build.gradle.kts`: carga `key.properties` y aplica `signingConfig` de
  release; si `key.properties` no existe (CI) cae a debug. (Único archivo commiteado.)
- APK EPP recompilado y **firmado con la llave de release**: verificado con apksigner
  → `Signer #1 DN: CN=TrazApp`, esquema v2 válido.
- Versión web compilada (`build/web`, ~43 MB).

## Seguridad
- key.properties y el `.jks` NO están en git (verificado: `git status` limpio, keystore
  fuera del repo). El repo solo tiene la lógica que LEE key.properties.

## Notas
- Web: `camera` y ML Kit face detection no tienen soporte en navegador; el build genera
  artefactos pero el flujo de captura de foto no funciona en web.
- APK firmado solo con esquema v2 (sin v1) — correcto para API 24+ y Play App Signing.

## Commits
- `75eb0de` — chore(android): firma de release desde key.properties (fallback a debug)

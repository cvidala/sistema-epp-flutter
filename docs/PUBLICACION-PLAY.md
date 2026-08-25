# Publicación en Google Play — Checklist y estrategia

**Última actualización:** 2026-08-24
**Estado:** Documento vivo.
**Meta:** Publicar TrazApp (app EPP) evitando la prueba obligatoria de testers, sin bloquear la entrega al primer cliente.

---

## Contexto

- Ya existe una cuenta **Google Play Developer individual** ($25 pagados).
- **Requisito de testers (verificado 2026):** las cuentas **personales** creadas después del **13-nov-2023** deben correr una prueba cerrada con **12 testers** (bajó de 20 en dic-2024) durante **14 días continuos**, y Google además evalúa que los testers **usen** la app de verdad, antes de poder publicar en **producción pública**.
- **Las cuentas de Organización están EXENTAS** de ese requisito. Ese es el camino para saltárselo de forma legítima.

> No intentes falsear testers: es vía directa a la suspensión de la cuenta.

---

## Camino A — Entrega interina al primer cliente (SIN esperar nada)

Para B2B con pocos usuarios, **no necesitas producción pública** para que el cliente empiece a usar la app. Dos opciones:

### A.1 Sideload del APK firmado (lo más rápido)
- [ ] Tener el APK release firmado: `build/app/outputs/flutter-apk/app-epp-release.apk`.
- [ ] Enviárselo al cliente (link de descarga / correo).
- [ ] En el teléfono: activar **"Instalar apps de orígenes desconocidos"** para el instalador usado (Archivos/Chrome).
- [ ] Instalar el APK.
- Contras: las actualizaciones se distribuyen a mano (les reenvías el nuevo APK).

### A.2 Internal Testing en Play (recomendado como canal estable)
- [ ] Generar el App Bundle: `flutter build appbundle --release --flavor epp`.
- [ ] En Play Console → **Pruebas → Prueba interna**, subir el `.aab`.
- [ ] Agregar a los supervisores por correo (hasta **100** testers).
- [ ] Compartir el enlace de aceptación; instalan desde la Play Store.
- Ventajas: **auto-actualización** vía Play y **sin la regla de 12 testers / 14 días** (esa regla es solo para producción pública).

---

## Camino B — Convertir a cuenta de Organización (para producción pública)

Esto te exime de los 12 testers de forma permanente. Se hace sobre la **misma cuenta** (no pierdes los $25).

- [ ] **Empresa formalizada** (razón social vigente).
- [ ] **Obtener número D-U-N-S** — gratis, lo emite Dun & Bradstreet. ⏳ **Es la parte lenta** (días a semanas; existe trámite exprés). Empezar por aquí.
- [ ] **Verificar el sitio web oficial** de la organización (p. ej. `trazapp.cl`) en Play Console. Recién tras verificar la web se habilita el cambio de tipo de cuenta.
- [ ] **Crear/verificar el perfil de pago de organización** (tipo correcto) y vincularlo.
- [ ] **Cambiar el tipo de cuenta** Individual → Organización en Play Console.

> ⚠️ **Irreversible:** Individual → Organización se puede; **Organización → Individual NO**. Si algún día necesitaras volver a individual, tendrías que crear otra cuenta desde cero.

---

## Recomendación

Ejecuta **A y B en paralelo** para no frenar el trato:

1. **Ahora:** entrega al primer cliente con **A.1 (sideload)** o **A.2 (internal testing)**. Empieza a usar TrazApp esta semana.
2. **En paralelo:** arranca **B** (el D-U-N-S primero, porque es lo que más demora). Cuando la cuenta sea de Organización, publicas en producción pública **sin los 12 testers**.

---

## Enlaces oficiales

- [Elegir un tipo de cuenta de desarrollador — Play Console Help](https://support.google.com/googleplay/android-developer/answer/13634885?hl=es)
- [Mantener actualizada la información de tu cuenta — Play Console Help](https://support.google.com/googleplay/android-developer/answer/13634888?hl=es)

> Las políticas de Google cambian con frecuencia — confirma los pasos vigentes en Play Console al momento de ejecutarlos.

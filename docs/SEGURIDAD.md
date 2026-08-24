# Postura de Seguridad — TrazApp

**Última actualización:** 2026-08-24
**Estado:** Documento vivo — se actualiza cuando cambian los controles de seguridad.
**Alcance:** Aplicación TrazApp (Flutter iOS/Android/web), dashboard web y backend Supabase (proyecto `ppltpmmtdnprgauwnytf`).

> Este documento describe únicamente controles **efectivamente implementados y verificados** en el código y la infraestructura. No describe intenciones ni trabajo futuro.

---

## 1. Resumen ejecutivo

TrazApp maneja datos personales de trabajadores (nombre, RUT), evidencia fotográfica de entregas de EPP, firmas, coordenadas GPS e información forense de dispositivo. La seguridad se aborda en cuatro frentes, todos cubiertos:

| Frente | Estado |
|--------|--------|
| Cifrado en tránsito (TLS 1.2/1.3) | ✅ Implementado y verificado |
| Cifrado en reposo — servidor (AES-256) | ✅ Por defecto (Supabase/AWS) |
| Cifrado en reposo — dispositivo (caché local) | ✅ Implementado (AES-256) |
| Control de acceso multi-tenant (RLS) | ✅ Implementado |
| Integridad forense de la evidencia | ✅ Implementado (hash chain + inmutabilidad) |
| Almacenamiento de fotos con control de acceso | ✅ Buckets privados + URLs firmadas |
| Minimización de datos biométricos | ✅ Sin persistencia de template facial |

---

## 2. Cifrado en tránsito

Todo el tráfico (app ↔ Supabase, dashboard ↔ Supabase) viaja sobre **HTTPS**. No existen endpoints en texto plano.

**Verificado contra el endpoint de producción (2026-08-24):**

| Protocolo | Resultado |
|-----------|-----------|
| **TLS 1.3** | Negociado por defecto (cipher `TLS_AES_256_GCM_SHA384`) |
| **TLS 1.2** | Soportado |
| TLS 1.1 | Rechazado |
| TLS 1.0 | Rechazado |

**Refuerzo en el cliente:**
- **iOS:** App Transport Security (ATS) activo, sin excepciones (`NSAllowsArbitraryLoads` no presente). ATS exige TLS 1.2 como mínimo a nivel de sistema operativo.
- **Android:** sin `usesCleartextTraffic` ni configuración de red que permita tráfico en claro; el cleartext está bloqueado por defecto (API 28+).
- **Código:** no existen URLs `http://` — toda comunicación es `https://`.

---

## 3. Cifrado en reposo

### 3.1 Servidor (Supabase / AWS)
La base de datos PostgreSQL y el almacenamiento de objetos (Storage) están cifrados en reposo con **AES-256** por defecto en la infraestructura de Supabase sobre AWS.

### 3.2 Dispositivo (caché local)
La aplicación opera *offline-first* y mantiene una caché local (Hive) con datos que incluyen PII. Esa caché está **cifrada con `HiveAesCipher` (AES-256)**. La clave se genera una vez por instalación y se guarda en el almacenamiento seguro del sistema operativo:
- **iOS:** Keychain.
- **Android:** Keystore / EncryptedSharedPreferences.

La clave nunca se almacena en la propia caché. Implementación: [`lib/services/secure_hive.dart`](../lib/services/secure_hive.dart). Boxes cifradas: entregas en cola, caché de catálogo/obras/trabajadores, identificador de dispositivo y registros de asistencia pendientes.

---

## 4. Control de acceso

### 4.1 Aislamiento multi-tenant (Row Level Security)
Cada organización (empresa cliente) ve exclusivamente sus propios datos. El aislamiento se aplica con **Row Level Security (RLS)** de PostgreSQL en todas las tablas, filtrando por `org_id` mediante la función `get_user_org_id()` (`SECURITY DEFINER`, con `search_path` fijo para prevenir inyección). Un usuario de una empresa no puede acceder a datos de otra.

### 4.2 Roles
Perfiles con roles **ADMIN**, **SUPERVISOR** y **READONLY**, cuyos permisos de lectura/escritura se aplican en las políticas RLS.

### 4.3 Gestión de credenciales
- La **clave pública anónima** (anon key) es pública por diseño y está protegida por RLS.
- La **clave de servicio** (service_role, que omite RLS) **nunca** está presente en la aplicación cliente. Solo se usa en la Edge Function del servidor (leída de variables de entorno), en el entorno de pruebas y en los secretos de CI. No está en el control de versiones.
- Sesiones gestionadas por Supabase Auth (email/contraseña) con JWT.

---

## 5. Almacenamiento de evidencia (fotos y firmas)

Los buckets de almacenamiento con datos sensibles (`evidencias` — foto de entrega y firma; `fotos-rostro` — foto de perfil) son **privados**. No son accesibles por URL pública.

El acceso a cada imagen se realiza mediante **URLs firmadas temporales** (`signed URLs`), generadas solo para usuarios autenticados y con vencimiento. El bucket de asistencia (`asistencias-fotos`) también es privado con el mismo mecanismo.

---

## 6. Integridad forense de la evidencia

Los registros de entrega de EPP (`entregas_epp`) están diseñados para ser **inalterables**, condición clave para su valor probatorio ante fiscalización:

- **Cadena de hash (hash chain):** cada registro encadena `prev_hash` → `hash` (SHA-256), de modo que cualquier alteración rompe la cadena y es detectable.
- **Inmutabilidad:** un *trigger* en base de datos impide modificar los campos de integridad (evento, hashes, firma, forense) una vez insertado el registro.
- **No borrado:** la eliminación de registros de entrega está bloqueada **incluso para la clave de servicio** (service_role), vía trigger `BEFORE DELETE`.
- **Auditoría:** tabla `audit_log` con *triggers* sobre tablas críticas (cambios de rol, asignaciones, catálogo), registrando quién y cuándo.

---

## 7. Datos biométricos

La aplicación **no persiste plantillas biométricas** (descriptores faciales). La detección facial (Google ML Kit) se ejecuta **exclusivamente en el dispositivo** y solo para validar la calidad de la fotografía en el momento de la captura. Lo que se almacena es la fotografía (dato personal, protegida según las secciones 3 y 5), no un identificador biométrico reutilizable.

---

## 8. Marco normativo aplicable

TrazApp está diseñado teniendo presente el marco chileno:

- **Ley 19.628** sobre protección de la vida privada (protección de datos personales).
- **Ley 21.719** de protección de datos personales, incluidas sus disposiciones sobre datos sensibles y el principio de seguridad.
- **Resolución Exenta N°38 de la Dirección del Trabajo (DT)**, relativa al registro de entrega de elementos de protección personal (EPP).

Los controles de integridad forense (sección 6) y de acceso (sección 4) sustentan el valor probatorio de los registros ante una fiscalización.

> Nota: este documento describe controles técnicos. No constituye asesoría legal ni una certificación de cumplimiento; la evaluación de cumplimiento normativo corresponde al responsable de datos.

---

## 9. Verificación y re-auditoría

Los controles de este documento son re-verificables. Ejemplos:

**TLS del endpoint:**
```bash
# Protocolo negociado (esperado: TLSv1.3)
echo | openssl s_client -connect ppltpmmtdnprgauwnytf.supabase.co:443 \
  -servername ppltpmmtdnprgauwnytf.supabase.co 2>/dev/null | grep -i protocol

# TLS 1.0/1.1 deben ser rechazados (conexión falla)
curl -sI --tls-max 1.1 https://ppltpmmtdnprgauwnytf.supabase.co/rest/v1/ -o /dev/null -w "%{http_code}\n"
```

**Buckets privados** (el endpoint público debe responder "Bucket not found"):
```bash
curl -s "https://ppltpmmtdnprgauwnytf.supabase.co/storage/v1/object/public/evidencias/probe.jpg"
```

**RLS habilitado / advisors de seguridad:** Supabase Dashboard → Advisors → Security (debe estar sin hallazgos de RLS deshabilitado).

**Cifrado de caché local:** revisión de código en [`lib/services/secure_hive.dart`](../lib/services/secure_hive.dart) y su uso en los servicios que abren boxes de Hive.

---

*Contacto de seguridad: responsable del producto TrazApp.*

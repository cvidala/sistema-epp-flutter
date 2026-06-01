# Architecture

**Analysis Date:** 2026-06-01

## System Overview

```text
┌──────────────────────────────────────────────────────────────────┐
│                       Presentation Layer                          │
├─────────────────┬──────────────────┬──────────────┬──────────────┤
│  ObrasPage      │  WorkersPage     │  NewDelivery │  AsistenciaUI│
│ `lib/obras_*`   │ `lib/workers_*`  │ `lib/new_*`  │ `lib/asist/* │
└────────┬────────┴────────┬─────────┴──────┬───────┴──────────────┘
         │                 │                │
         ▼                 ▼                ▼
┌──────────────────────────────────────────────────────────────────┐
│                       Service Layer                               │
│  AuthService │ OfflineQueueService │ SyncService │ ForensicSvc   │
│  `lib/services/`                                                  │
└────────┬──────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│                      Persistence Layer                            │
│  OfflineCacheService (Hive) │ CacheService │ OfflineQueueService │
│  `lib/services/offline_*.dart`                                    │
└──────────────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│                    External Services                              │
│  Supabase (Auth, Database, Storage) │ Geolocator │ Camera        │
│  Device Info │ ML Kit Face Detection │ Signature Capture          │
└──────────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| **AuthService** | Load user profile, manage permissions, session state | `lib/services/auth_service.dart` |
| **OfflineQueueService** | Queue deliveries/attendance offline, manage retry backoff | `lib/services/offline_queue_service.dart` |
| **SyncService** | Sync queued data to Supabase, hash chaining, dedup | `lib/services/sync_service.dart` |
| **OfflineCacheService** | Hive-backed cache for obras, workers, EPP catalog | `lib/services/offline_cache_service.dart` |
| **ConnectivityService** | Monitor online/offline state, trigger auto-sync | `lib/services/connectivity_service.dart` |
| **ForensicService** | Capture GPS, device info, timestamp at signature time | `lib/services/forensic_service.dart` |
| **ObrasPage** | Select work site, navigate to workers/stock | `lib/obras_page.dart` |
| **WorkersPage** | List workers, view details, access EPP delivery | `lib/workers_page.dart` |
| **NewDeliveryPage** | Capture photo, select EPP items, sign, queue delivery | `lib/new_delivery_page.dart` |
| **RutInputScreen** | Attendance entry point (asistencia app), RUT capture | `lib/asistencia/screens/rut_input_screen.dart` |

## Pattern Overview

**Overall:** Service-Oriented Architecture with Offline-First Strategy

**Key Characteristics:**
- **Offline-first design**: All data operations go through local queues/caches; sync happens asynchronously when online
- **Two-app model**: `main.dart` (EPP management) and `main_asistencia.dart` (Attendance tracking) - separate entry points with shared Supabase backend
- **Singleton services**: Global service instances (AuthService, OfflineQueueService, ConnectivityService) manage state
- **Forensic capture**: GPS + device info + signature hash chaining for audit trail integrity
- **RLS-based security**: Supabase Row Level Security filters data per user/role; app trusts database layer

## Layers

**Presentation (UI):**
- Purpose: Render screens, capture user input (camera, signature, location), display status
- Location: `lib/*.dart` (pages), `lib/asistencia/screens/` (asistencia module)
- Contains: StatefulWidget screens, theme configuration, navigation logic
- Depends on: AuthService, OfflineQueueService, Supabase for real-time data
- Used by: Flutter engine (entry point: main.dart or main_asistencia.dart)

**Service (Business Logic):**
- Purpose: Authentication, offline data queuing, background sync, forensic capture, connectivity monitoring
- Location: `lib/services/`, `lib/asistencia/services/`
- Contains: Singleton services, domain models (PerfilUsuario, OfflineEntrega, AsistenciaPendiente)
- Depends on: Supabase client, Hive, device plugins (camera, geolocator, etc.)
- Used by: UI layer for data operations

**Persistence (Local Storage):**
- Purpose: Cache data for offline operation, queue operations until sync succeeds
- Location: `lib/services/offline_*.dart`, Hive boxes
- Contains: Hive-backed storage, in-memory queue management, JSON serialization
- Depends on: Hive library, file I/O
- Used by: Service layer (auth, sync, cache)

**External (Supabase + Device APIs):**
- Purpose: Server-side data, auth token management, storage, device capabilities
- Location: Cloud (Supabase), OS layers (Android/iOS)
- Contains: PostgreSQL database with RLS, S3-compatible storage, native device APIs
- Depends on: Network connectivity, OS permissions
- Used by: Service and persistence layers

## Data Flow

### Primary Request Path: EPP Delivery

1. **User enters WorkersPage** (`lib/workers_page.dart`) — loads worker list from Supabase (RLS filters by obra)
2. **User opens NewDeliveryPage** (`lib/new_delivery_page.dart`) with worker ID
3. **Page loads catálogo EPP + bodegas** — from Supabase if online, else fallback to OfflineCacheService
4. **User captures photo** (using camera plugin) → saved locally by EvidenceService (`lib/evidence_service.dart`)
5. **User selects EPP items** and signs with SignatureController → ForensicService captures GPS/device info at signature time
6. **User submits delivery**:
   - **Online**: Photo + signature uploaded to Supabase Storage; delivery record inserted into `entregas_epp` table
   - **Offline**: Delivery + photo/signature queued in OfflineQueueService (Hive); marked as PENDING
7. **ConnectivityService detects online** → triggers SyncService.syncOnce()
   - Sync deduplicates by event_id
   - Uploads evidence files to storage
   - Inserts delivery record with hash chain (prev_hash + current hash)
   - Marks delivery as SENT in local queue
8. **WorkersPage refreshes** after sync completes via DataCacheService.sincronizarTodo()

### Attendance (Asistencia) Flow

1. **App starts with main_asistencia.dart** → RutInputScreen (`lib/asistencia/screens/rut_input_screen.dart`)
2. **User enters RUT** → formatted and validated
3. **CameraCaptureScreen** (`lib/asistencia/screens/camera_capture_screen.dart`) captures selfie
   - ML Kit Face Detection (`google_mlkit_face_detection`) validates face presence
   - Optional: Anti-spoofing filter detects liveness
4. **AsistenciaHiveService** stores attendance locally: `AsistenciaPendiente(rut, tipo, fotoLocalPath, gpsCoords, timestamp)`
5. **AsistenciaUploadService** queues async upload when online
6. **Sync in background** → uploads photo + metadata to Supabase `asistencias` table

### Offline → Online Transition

1. **ConnectivityService._check()** polls Supabase every 10s (`lib/services/connectivity_service.dart`)
2. **Detects change from offline → online**
3. **Calls SyncService.syncOnce()** for each pending delivery/attendance
4. **Respects exponential backoff**: if sync fails, sets `nextRetryAt = now + 2^attempts minutes` (max 5 attempts)
5. **On success**: marks as SENT; UI refreshes

**State Management:**
- **In-memory**: AuthService.perfil (loaded once at login)
- **Local cache (Hive)**: Obras, catalog, workers, sync state — keyed by last update time
- **Queue (Hive)**: OfflineQueueService.listPending() — holds unsent deliveries with retry metadata
- **Remote (Supabase)**: Source of truth for all data; RLS ensures access control

## Key Abstractions

**PerfilUsuario:**
- Purpose: Represent authenticated user's permissions and module access
- Examples: `lib/services/auth_service.dart` lines 45–78
- Pattern: Singleton loaded at login; checked before write operations

**OfflineEntrega:**
- Purpose: Model queued delivery with offline-safe state machine (PENDING → UPLOADING → SENT, with ERROR backoff)
- Examples: `lib/services/offline_queue_service.dart` lines 9–31
- Pattern: Hive-serialized; includes hash chain (prevHash, hash) for integrity

**AsistenciaPendiente:**
- Purpose: Model queued attendance record with photo + GPS + device info
- Examples: `lib/asistencia/models/asistencia_pendiente.dart` lines 1–64
- Pattern: Hive-serialized; status tracks sync state (pendiente, subiendo, enviada, fallida)

**EvaluacionEntrega:**
- Purpose: Semaphore evaluation (OK, WARNING, BLOQUEO) based on stock rules
- Examples: `lib/models/evaluacion_entrega.dart` lines 1–16
- Pattern: Returned by Supabase RPC; used by NewDeliveryPage to show traffic light

## Entry Points

**EPP App (main.dart):**
- Location: `lib/main.dart` lines 14–30
- Triggers: `flutter run -t lib/main.dart`
- Responsibilities:
  1. Initialize Hive, services (OfflineQueueService, CacheService, etc.)
  2. Initialize Supabase client
  3. Run MyApp() with theme configuration
  4. Navigate to LoginGate (decides login vs. ObrasPage based on session + connectivity)

**Asistencia App (main_asistencia.dart):**
- Location: `lib/main_asistencia.dart` lines 8–20
- Triggers: `flutter run -t lib/main_asistencia.dart` (or separate build variant)
- Responsibilities:
  1. Initialize Hive + AsistenciaHiveService
  2. Initialize Supabase client
  3. Navigate directly to RutInputScreen

**LoginGate (main.dart):**
- Location: `lib/main.dart` lines 117–210
- Triggers: App launch when no cached session
- Decides:
  - **Online + session**: Load profile from Supabase, navigate to ObrasPage
  - **Offline + valid cache**: Load profile from OfflineCacheService, navigate to ObrasPage(modoOffline: true)
  - **Offline + no cache**: Show error, force login

## Architectural Constraints

- **Threading:** Single-threaded event loop (Flutter standard). All async I/O (Supabase, camera, geolocator) uses Future/async-await. No worker threads; heavy computation (image compression, hashing) runs on main thread.
- **Global state:** 
  - `AuthService.instance._perfil` (loaded at login, cleared at logout)
  - `OfflineQueueService._box` (Hive box opened at app startup, never closed during runtime)
  - `OfflineCacheService._box` (Hive box for sync cache)
  - `ConnectivityService.instance._timer` (periodic connectivity check, managed by start/stop)
- **Circular imports:** None detected; service layer imports presentation layer via callbacks (e.g., ConnectivityService.onSyncComplete), not vice versa
- **Offline mode limitations:**
  - Cannot create new obras (creation-only operations require online)
  - Can only view cached workers/EPP
  - New deliveries queued but not synced until online
  - No real-time sync of remote changes while offline

## Anti-Patterns

### Mixing UI state with persistent state

**What happens:** Pages use setState() to manage both UI toggle state (loading, error) and cached business data (obras, workers) in the same state object.

**Why it's wrong:** Causes unnecessary rebuilds when UI state changes; makes it hard to separate concerns between display logic and data logic.

**Do this instead:** Move cacheable data to services (e.g., ObrasPage should fetch from AuthService.instance.cargarObras() and store in-memory, not in widget state). Use setState() only for transient UI flags (loading, error, filters). Example: `lib/stock_page.dart` mixes `loading` and `stockItems` in _StockPageState — refactor to pull stockItems from a StockService singleton.

### No null-safety on service data

**What happens:** Services like OfflineCacheService.getCatalogo() return empty List if key is null, but callers don't check for initialization state. If OfflineCacheService.init() wasn't called, accessing _b throws StateError.

**Why it's wrong:** Errors surface at runtime in UI, not at startup. Hard to debug in offline scenarios.

**Do this instead:** Add startup checks. Example in main.dart: after OfflineCacheService.init(), verify _box is not null before proceeding to app. Add a OfflineCacheService.isInitialized getter.

### Direct Supabase.instance.client calls in multiple places

**What happens:** Pages and services directly call `Supabase.instance.client.from(...).select()` across the codebase, making offline behavior inconsistent.

**Why it's wrong:** Some screens use AuthService.cargarObras() (with fallback to cache), others call Supabase directly. No unified offline fallback.

**Do this instead:** Create domain-specific repository services (e.g., ObraRepository, TrabajadorRepository) that always check OfflineCacheService first, then hit Supabase. Inject them into pages instead of direct Supabase calls.

## Error Handling

**Strategy:** Graceful degradation with fallback to cache

**Patterns:**
- **Network errors in UI**: Page shows error message + falls back to cached data if available (see LoginGate._entrarDesdeCache, ObrasPage._loadObras)
- **Sync errors**: SyncService respects exponential backoff; failed deliveries stay PENDING in queue for retry
- **Offline without cache**: Force login (cannot enter app without cached profile + obras)
- **Auth failures**: PerfilNoEncontradoException caught, user logged out, returned to LoginPage
- **Evidence capture failures**: If camera or GPS fails, delivery still queued with degraded forensic data (null GPS fields acceptable)

## Cross-Cutting Concerns

**Logging:** 
- Debugprint statements throughout (e.g., `[SyncService] Pendientes a sincronizar: ${pendings.length}`)
- No centralized logger; ad-hoc debugging

**Validation:**
- User input: RUT formatting in RutInputScreen (custom TextInputFormatter `_RutFormatter`)
- EPP quantities: Stock availability checked in NewDeliveryPage._recalcularSemaforo() via RPC `get_evaluacion_entrega`
- Delivery state machine: Enforced by OfflineQueueService (PENDING → UPLOADING → SENT/ERROR)

**Authentication:**
- Session managed by Supabase.instance.client.auth
- Profile loaded into AuthService.instance._perfil after successful login
- RLS on all tables filters by user org + role
- No explicit token refresh; relies on Supabase SDK

---

*Architecture analysis: 2026-06-01*

# Codebase Structure

**Analysis Date:** 2026-06-01

## Directory Layout

```
sistema-epp-flutter/
├── lib/                          # Main Dart source code
│   ├── main.dart                 # EPP app entry point (login, obras, workers, delivery)
│   ├── main_asistencia.dart      # Asistencia app entry point (attendance tracking)
│   ├── obras_page.dart           # Work site selection screen
│   ├── workers_page.dart         # Worker list for selected obra
│   ├── worker_detail_page.dart   # Worker detail + EPP history
│   ├── new_delivery_page.dart    # EPP delivery form (camera, signature, cart)
│   ├── stock_page.dart           # Inventory management
│   ├── stock_entry_page.dart     # Stock entry form
│   ├── solicitudes_epp_page.dart # EPP requests tracking
│   ├── evidence_service.dart     # Evidence file I/O (photos, signatures)
│   │
│   ├── config/
│   │   └── supabase_config.dart  # Supabase URL + anon key (shared between apps)
│   │
│   ├── models/
│   │   └── evaluacion_entrega.dart # Delivery evaluation model (semaphore state)
│   │
│   ├── services/                 # Business logic services
│   │   ├── auth_service.dart     # Session, profile, permission checks
│   │   ├── offline_queue_service.dart # Queue offline deliveries (Hive)
│   │   ├── offline_cache_service.dart # Cache works/workers/EPP (Hive)
│   │   ├── cache_service.dart    # Cache operations helper
│   │   ├── data_cache_service.dart # Data sync/cache refresh orchestrator
│   │   ├── sync_service.dart     # Upload queued deliveries to Supabase
│   │   ├── connectivity_service.dart # Monitor online/offline, trigger sync
│   │   ├── forensic_service.dart # Capture GPS + device info + timestamp
│   │   ├── device_id_service.dart # Device unique identifier
│   │   ├── entrega_service.dart  # Delivery-related operations
│   │
│   └── asistencia/               # Attendance module (separate app)
│       ├── models/
│       │   └── asistencia_pendiente.dart # Queued attendance record
│       ├── screens/
│       │   ├── rut_input_screen.dart # RUT entry + tipo selector
│       │   └── camera_capture_screen.dart # Face capture + ML detection
│       └── services/
│           ├── asistencia_hive_service.dart # Hive storage for attendance
│           ├── asistencia_sync_service.dart # Sync attendance to Supabase
│           └── asistencia_upload_service.dart # Upload photo to storage
│
├── android/                      # Android native code (Kotlin/Java)
├── ios/                          # iOS native code (Swift/Objective-C)
├── web/                          # Web build (Flutter web, if used)
├── linux/, macos/, windows/      # Desktop builds (if any)
│
├── supabase/                     # Supabase migrations + SQL (if local)
├── dashboard/                    # Analytics/reporting dashboard (if any)
│
├── pubspec.yaml                  # Dart dependencies + version
├── pubspec.lock                  # Locked dependency versions
├── analysis_options.yaml         # Linter config (Flutter strict mode)
├── .metadata                     # Flutter project metadata
├── .flutter-plugins-dependencies # Plugin tracking
├── flutter_launcher_icons-*.yaml # Icon config (Android, iOS)
├── app_icon.png, icon_asistencia.png # App icons
│
└── test/                         # Test directory (minimal test coverage)
```

## Directory Purposes

**lib/:**
- Purpose: All Dart source code (UI screens, services, models)
- Contains: StatefulWidget pages, singleton services, domain models
- Key files: `main.dart` (EPP), `main_asistencia.dart` (attendance)

**lib/config/:**
- Purpose: Configuration and environment setup
- Contains: Supabase credentials (URL, anon key) shared between apps
- Key files: `supabase_config.dart`

**lib/models/:**
- Purpose: Domain models (data classes that represent business entities)
- Contains: EvaluacionEntrega (semaphore state)
- Note: Most models (OfflineEntrega, AsistenciaPendiente) live in services or asistencia/models for co-location

**lib/services/:**
- Purpose: Business logic and data access layer
- Contains: Singletons for auth, offline queueing, caching, sync, connectivity, forensics
- Key files: `auth_service.dart` (session), `offline_queue_service.dart` (delivery queue), `sync_service.dart` (upload to Supabase)

**lib/asistencia/:**
- Purpose: Attendance tracking module (separate Flutter app entry point)
- Contains: RUT input screen, camera capture screen, attendance queue + sync services
- Key files: `main_asistencia.dart` (entry), `rut_input_screen.dart` (start), `asistencia_hive_service.dart` (storage)

**android/, ios/, web/, etc.:**
- Purpose: Platform-specific native code and build configurations
- Contains: Native plugins (camera, geolocator, device_info), Android/iOS source
- Generated: Many build artifacts

**supabase/:**
- Purpose: Database migrations, RLS policies, SQL functions (if version-controlled locally)
- Contains: SQL migrations, function definitions
- Generated: Auto-generated during local Supabase setup

**test/:**
- Purpose: Unit + widget tests (minimal in this project)
- Contains: Test files (if any exist — check current state)

## Key File Locations

**Entry Points:**
- `lib/main.dart` — EPP app (login → obras → workers → delivery)
- `lib/main_asistencia.dart` — Asistencia app (RUT → camera → attendance queue)

**Configuration:**
- `lib/config/supabase_config.dart` — Supabase URL + anon key
- `pubspec.yaml` — Dart dependencies (Supabase, Hive, camera, etc.)
- `analysis_options.yaml` — Linter rules (Flutter strict mode)

**Core Logic:**
- `lib/services/auth_service.dart` — User profile, roles, permissions
- `lib/services/offline_queue_service.dart` — Delivery queue state machine (PENDING → SENT)
- `lib/services/sync_service.dart` — Upload queued deliveries to Supabase
- `lib/services/connectivity_service.dart` — Monitor online/offline, auto-sync on transition
- `lib/services/offline_cache_service.dart` — Hive cache (obras, workers, EPP catalog)

**Screens (Pages):**
- `lib/obras_page.dart` — Select work site
- `lib/workers_page.dart` — Worker list for obra
- `lib/worker_detail_page.dart` — Worker detail + EPP delivery history
- `lib/new_delivery_page.dart` — Capture photo, select EPP items, sign, submit
- `lib/stock_page.dart` — Inventory overview by bodega
- `lib/stock_entry_page.dart` — Add stock entry

**Asistencia Screens:**
- `lib/asistencia/screens/rut_input_screen.dart` — RUT + tipo entrada/salida
- `lib/asistencia/screens/camera_capture_screen.dart` — Selfie + ML face detection

**Testing:**
- `test/` — Test files (minimal coverage currently)

## Naming Conventions

**Files:**
- Dart files: `snake_case.dart` (e.g., `auth_service.dart`, `new_delivery_page.dart`)
- Exception files: Same pattern (e.g., `offline_queue_service.dart` contains OfflineEntrega class)

**Directories:**
- Module/feature directories: `lowercase` (e.g., `services`, `config`, `models`, `asistencia`)
- Platform-specific: Named after platform (e.g., `android`, `ios`, `web`)

**Classes:**
- PascalCase (e.g., `AuthService`, `PerfilUsuario`, `OfflineEntrega`, `NewDeliveryPage`)
- Singletons: Typically named `*Service` and accessed via `ClassName.instance`

**Methods:**
- camelCase (e.g., `cargarPerfil()`, `syncOnce()`, `_loadObras()`)
- Private methods: Prefixed with `_` (e.g., `_check()`, `_loadInit()`)

**Constants:**
- camelCase if mutable (local variables), UPPER_CASE if global (e.g., `_keyPerfil` in OfflineCacheService)
- Colors: Hex notation (e.g., `Color(0xFF0D2148)` for dark blue)

**Variables:**
- Instance variables: camelCase (e.g., `evidenciaBytes`, `bodegaId`, `loading`)
- Private instance variables: camelCase prefixed with `_` (e.g., `_perfil`, `_timer`, `_box`)

## Where to Add New Code

**New Feature (e.g., new workflow):**
1. **Screen/Page**: Add new `lib/my_feature_page.dart` (StatefulWidget)
2. **Service**: Add `lib/services/my_feature_service.dart` if it needs business logic
3. **Models**: Add `lib/models/my_feature.dart` if new domain object needed
4. **Navigation**: Wire up in parent page navigation (e.g., add route to ObrasPage or MainApp)

**New Service/Singleton:**
1. Add to `lib/services/my_service.dart`
2. Implement singleton pattern: `static final instance = MyService._();` + private constructor `MyService._()`
3. Initialize in main.dart after services startup (see auth_service, cache_service, etc.)
4. Inject into pages via constructor or via `MyService.instance` static access

**New Asistencia Screen:**
1. Add to `lib/asistencia/screens/my_screen.dart`
2. Register in RutInputScreen navigation or AsistenciaApp home

**Utilities/Helpers:**
1. **Shared across modules**: `lib/services/` (e.g., `forensic_service.dart` for GPS + device info)
2. **Asistencia-specific**: `lib/asistencia/services/`
3. **Evidence handling**: Extend or mirror `lib/evidence_service.dart` pattern

**Models:**
1. **Domain models used in services**: `lib/services/` (e.g., PerfilUsuario in auth_service.dart)
2. **Feature-specific models**: `lib/models/` (e.g., EvaluacionEntrega)
3. **Asistencia models**: `lib/asistencia/models/` (e.g., AsistenciaPendiente)

**Configuration:**
1. Environment-specific config: `lib/config/` (e.g., supabase_config.dart)
2. Theme/UI config: In `main.dart` or `main_asistencia.dart` (ThemeData)

## Special Directories

**lib/services/:**
- **Purpose:** Singleton service classes that manage app state and business logic
- **Generated:** No (hand-coded)
- **Committed:** Yes
- **Lifecycle:** Initialized in main() before runApp(), persist for app lifetime
- **Pattern:** All services use singleton pattern (static final instance) and are accessed globally
- **Hive Boxes:** Several services open Hive boxes (OfflineQueueService._box, OfflineCacheService._box) at init; never explicitly closed during runtime

**lib/asistencia/:**
- **Purpose:** Self-contained attendance module with separate entry point (main_asistencia.dart)
- **Generated:** No
- **Committed:** Yes
- **Isolation:** Minimally coupled to EPP module; shares Supabase config but has own screens, services, models
- **Scaling note:** If asistencia grows, consider extracting to separate package

**android/, ios/, web/, etc.:**
- **Purpose:** Platform-specific code and build artifacts
- **Generated:** Mostly auto-generated by Flutter (gradle, xcode, etc.)
- **Committed:** Source code (Kotlin, Swift) committed; build artifacts (.gradle, .build, .derived) gitignored
- **Customization:** Native code for plugins (camera, geolocator) in android/src and ios/ directories

**build/:**
- **Purpose:** Build artifacts (APK, app bundle, web output)
- **Generated:** Yes, auto-generated
- **Committed:** No (in .gitignore)
- **Size:** Large; only regenerate when needed

**.dart_tool/:**
- **Purpose:** Dart analyzer cache, plugin discovery
- **Generated:** Yes, auto-generated
- **Committed:** No (in .gitignore)

**test/:**
- **Purpose:** Unit and widget tests
- **Generated:** No (hand-coded, if tests exist)
- **Committed:** Yes
- **Pattern:** Currently minimal; expand with new features

---

*Structure analysis: 2026-06-01*

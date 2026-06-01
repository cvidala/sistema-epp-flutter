<!-- GSD:project-start source:PROJECT.md -->

## Project

**TrazApp — QA & Quality System**

Suite de calidad integral para TrazApp, integrada dentro del mismo repo `sistema-epp-flutter`. Cubre cuatro capas de testing y monitoreo para garantizar la confiabilidad de un sistema de cumplimiento normativo EPP en obras de construcción.

**Core Value:** Detectar regresiones antes de que lleguen a producción y tener visibilidad en tiempo real del estado del sistema en campo.
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->

## Technology Stack

## Languages

- Dart 3.10.8+ - Flutter app codebase for iOS, Android, web
- TypeScript - Supabase Edge Functions (Node.js runtime)
- SQL - Database schema and stored procedures (PostgreSQL)
- HTML/CSS - Web UI static assets (`web/`, `dashboard/`, `website/`)

## Runtime

- Flutter SDK (latest stable) - Cross-platform mobile/web framework
- Dart VM - Dart runtime for Flutter apps
- Deno (via Supabase Edge Functions) - TypeScript/JavaScript runtime for serverless functions
- Pub - Dart package manager
- Lockfile: `pubspec.lock` (present)

## Frameworks

- Flutter 3.x - Cross-platform UI framework
- Material Design 3 - UI design system (via `package:flutter`)
- Supabase Flutter SDK 2.8.0 - Backend-as-a-service client
- PostgreSQL (via Supabase) - Relational database
- Supabase Edge Functions - Serverless compute (Deno runtime)
- Supabase Storage - File storage for images/documents
- Supabase Auth - Authentication provider
- Hive 2.2.3 - Local key-value storage for offline data
- Hive Flutter 1.1.0 - Flutter integration for Hive

## Key Dependencies

- `supabase_flutter` 2.8.0 - Supabase client for Dart, handles auth, database, storage access
- `hive` 2.2.3 - Local NoSQL database for offline caching
- `hive_flutter` 1.1.0 - Hive initialization and Flutter integration
- `connectivity_plus` 6.0.0 - Network connectivity detection (iOS/Android/web)
- `camera` 0.10.6 - Camera access for photo capture
- `google_mlkit_face_detection` 0.11.0 - Face detection via Google ML Kit (no cloud API calls)
- `image_picker` 1.0.0 - Image selection from gallery/camera
- `geolocator` 13.0.0 - GPS location capture with permission handling
- `device_info_plus` 10.1.0 - Device model, OS version, hardware ID retrieval
- `pdf` 3.11.3 - PDF generation for reports
- `printing` 5.13.0 - Printing and PDF export
- `file_picker` 8.0.0 - File system access for document selection
- `crypto` 3.0.3 - SHA256 hashing for forensic data
- `uuid` 4.4.2 - UUID v4 generation for event IDs
- `intl` 0.19.0 - Internationalization (date/time formatting for Spanish)
- `signature` 5.4.0 - Signature capture widget
- `flutter_image_compress` 2.3.0 - Image compression before upload
- `cupertino_icons` 1.0.8 - iOS-style icon pack
- `flutter_lints` 6.0.0 - Lint rules for Dart/Flutter
- `flutter_launcher_icons` 0.13.1 - App icon generation for Android/iOS
- `flutter_test` - Flutter testing framework

## Configuration

- Supabase configuration hardcoded in `lib/config/supabase_config.dart`:
- Supabase project: `ppltpmmtdnprgauwnytf`
- Database: PostgreSQL via Supabase
- Authentication: Supabase Auth (email/password)
- Notifications: Resend API (via Edge Function `notif-vencimiento`)
- Scheduled Jobs: pg_cron (Supabase extension) triggers daily notification function at 8:00 AM UTC
- `pubspec.yaml` - Dart/Flutter manifest
- `analysis_options.yaml` - Linter configuration (extends `package:flutter_lints`)
- `flutter_launcher_icons-epp.yaml` - Icon config for main app
- `flutter_launcher_icons-asistencia.yaml` - Icon config for attendance app
- `.metadata` - Flutter project metadata
- Platform-specific:

## Platform Requirements

- Flutter SDK 3.10.8 or later
- Dart 3.10.8 or later
- Android SDK (API 21+) for Android builds
- Xcode (macOS/iOS builds)
- For backend development: Supabase CLI, Deno runtime (for local Edge Function testing)
- Android 5.1+ (API 21) - Set in `flutter_launcher_icons-epp.yaml`
- iOS 11.0+ (implicit via Flutter)
- Web: Modern browser with WebGL support
- Backend: Supabase cloud hosting (no on-premise required)
- Email notifications: Resend API (requires API key in Supabase environment secrets)
- Scheduled tasks: pg_cron and pg_net extensions enabled in Supabase
- Supabase (authentication, database, storage, edge functions)
- Google ML Kit (on-device face detection, no cloud calls)
- Resend (email notifications for EPP expiration)
- Geolocator (device GPS, no third-party API)

<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

## Naming Patterns

- Pages: `_page.dart` (e.g., `workers_page.dart`, `stock_page.dart`)
- Services: `_service.dart` (e.g., `auth_service.dart`, `sync_service.dart`)
- Models: `_pendiente.dart`, `_entrega.dart`, or plain model names (e.g., `asistencia_pendiente.dart`, `evaluacion_entrega.dart`)
- Screens: `_screen.dart` (e.g., `camera_capture_screen.dart`)
- Public classes: PascalCase (e.g., `WorkersPage`, `LoginPage`, `AuthService`)
- Private (inner) classes: `_ClassName` with underscore prefix (e.g., `_LoginGateState`, `_StockPageState`, `_FaceOvalPainter`)
- State classes for StatefulWidget: `_WidgetNameState` (e.g., `_LoginPageState`, `_WorkersPageState`)
- Public functions: camelCase (e.g., `cargarPerfil()`, `syncOnce()`, `markSent()`)
- Private methods: `_methodName` with underscore prefix (e.g., `_loadWorkers()`, `_check()`, `_runSync()`)
- Async methods: marked with `Future<ReturnType>` or `async`
- Callback/listener methods: start with `_on` prefix (e.g., `_onStatusChange()`, `_onSyncComplete()`)
- Local variables: camelCase (e.g., `loading`, `error`, `trabajadores`, `bodegaId`)
- Instance variables: camelCase (e.g., `searchCtrl`, `supabase`, `_syncing`, `_perfil`)
- Constants: SCREAMING_SNAKE_CASE (e.g., `_boxName`, `const Duration(seconds: 10)`)
- Boolean flags: prefixed with `is` or `_` underscore (e.g., `isAdmin`, `_syncing`, `_estabaOnline`)
- Classes: PascalCase (e.g., `PerfilUsuario`, `ConfigModulos`, `OfflineEntrega`)
- Enums: PascalCase items (e.g., status values: `'PENDING'`, `'SENT'`, `'ERROR'`)
- Typedefs: PascalCase (e.g., `VoidCallback`)

## Code Style

- No explicit code formatter configured (using Dart/Flutter defaults)
- Line length: observed 80-100 character limit in many files
- Indentation: 2 spaces (standard Dart)
- Trailing commas: used in multi-line collections and function arguments for cleaner diffs
- Uses `flutter_lints: ^6.0.0`
- Config: `analysis_options.yaml` with base `package:flutter_lints/flutter.yaml`
- Most linting rules are defaults; custom rules commented out
- Linting can be checked with: `flutter analyze`
- Dart null safety enforced (requires SDK ^3.10.8)
- Use `?` for nullable types and `!` for non-nullable assertions where certain
- Null coalescing with `??` (e.g., `data['status'] ?? 'OK'`)

## Import Organization

- No path aliases configured in `pubspec.yaml`
- Imports use relative paths: `import 'services/auth_service.dart'`

## Error Handling

- Custom exceptions: implement `Exception` interface (e.g., `PerfilNoEncontradoException`)
- Use `on SpecificException catch (e)` for known exception types
- Use bare `catch (e)` for unexpected errors, typically converting to string
- Exceptions include `toString()` methods for logging
- Errors stored in local state (`String? error`)
- Set via `setState(() => error = e.toString())` in StatefulWidgets
- Error display conditional: `if (error != null) { ... }`

## Logging

- Prefix logs with service name in brackets: `debugPrint('[SyncService] ...')`
- Log state transitions: `debugPrint('[Connectivity] Estado cambió → ONLINE')`
- Include operation counts in summaries: `'enviadas: $enviadas, errores: $errores'`
- Use symbols for status: `✅` (success), `❌` (error), `⏳` (waiting), `⛔` (failed)
- No logging output to console in production (all `debugPrint` calls ignored)

## Comments

- Comment complex logic (state machine transitions, backoff calculations)
- Document non-obvious control flow (if/else chains, nested async operations)
- Explain business rules and constraints (e.g., RLS checks, permission resolution)
- Mark code as "✅ FIX" or similar when addressing known issues
- Limited use; Dart uses `///` for doc comments
- Used for public APIs and complex classes
- Example from `auth_service.dart`:
- Used sparingly
- Multi-line section dividers: `// ─────────────────────────────────────────────`
- Status markers: `// ── Step description ─────────────────`

## Function Design

- Typical functions: 10-50 lines
- Larger methods allowed in page/widget state classes (up to 100+ lines for complex UI logic)
- Complex business logic extracted to services
- Use positional parameters for required values
- Use named parameters for optional values
- Constructor parameters marked `required` when mandatory
- Example from `NewDeliveryPage`:
- Most async operations return `Future<T>` or `Future<void>`
- Complex results returned as `Map<String, dynamic>` or typed objects
- Void callbacks via `VoidCallback` type alias

## Module Design

- No barrel files observed (`index.dart`)
- Imports use direct file paths
- Services organized in `lib/services/` directory
- Pages in `lib/` root or `lib/asistencia/` subdirectory
- Services use private constructor and static `instance` getter
- Example from `auth_service.dart`:
- Services require explicit `init()` calls in `main()` before use
- Hive boxes initialized via `Hive.openBox()` in service `init()` methods
- StateManager pattern for lifecycle: `_box` stored as static variable, accessed via getter

## Specific Dart/Flutter Conventions

- StatefulWidget + State pattern throughout (no Provider, Bloc, or Riverpod)
- Local state: `bool`, `String`, `List` instance variables
- State updates via `setState(() => { ... })`
- Async operations initiated in `initState()` or callbacks
- `initState()`: load data, start listeners
- `dispose()`: cleanup controllers, cancel timers
- Always check `if (mounted)` before `setState()` in async callbacks
- TextEditingController instances created and disposed
- Controllers accessed via property, not recreated per build
- `MaterialPageRoute` for screen transitions
- Use `Navigator.of(context).pushReplacement()` for login/auth flows
- Parameters passed via constructor to target page

<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

## Architecture

## System Overview

```text

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

- **Offline-first design**: All data operations go through local queues/caches; sync happens asynchronously when online
- **Two-app model**: `main.dart` (EPP management) and `main_asistencia.dart` (Attendance tracking) - separate entry points with shared Supabase backend
- **Singleton services**: Global service instances (AuthService, OfflineQueueService, ConnectivityService) manage state
- **Forensic capture**: GPS + device info + signature hash chaining for audit trail integrity
- **RLS-based security**: Supabase Row Level Security filters data per user/role; app trusts database layer

## Layers

- Purpose: Render screens, capture user input (camera, signature, location), display status
- Location: `lib/*.dart` (pages), `lib/asistencia/screens/` (asistencia module)
- Contains: StatefulWidget screens, theme configuration, navigation logic
- Depends on: AuthService, OfflineQueueService, Supabase for real-time data
- Used by: Flutter engine (entry point: main.dart or main_asistencia.dart)
- Purpose: Authentication, offline data queuing, background sync, forensic capture, connectivity monitoring
- Location: `lib/services/`, `lib/asistencia/services/`
- Contains: Singleton services, domain models (PerfilUsuario, OfflineEntrega, AsistenciaPendiente)
- Depends on: Supabase client, Hive, device plugins (camera, geolocator, etc.)
- Used by: UI layer for data operations
- Purpose: Cache data for offline operation, queue operations until sync succeeds
- Location: `lib/services/offline_*.dart`, Hive boxes
- Contains: Hive-backed storage, in-memory queue management, JSON serialization
- Depends on: Hive library, file I/O
- Used by: Service layer (auth, sync, cache)
- Purpose: Server-side data, auth token management, storage, device capabilities
- Location: Cloud (Supabase), OS layers (Android/iOS)
- Contains: PostgreSQL database with RLS, S3-compatible storage, native device APIs
- Depends on: Network connectivity, OS permissions
- Used by: Service and persistence layers

## Data Flow

### Primary Request Path: EPP Delivery

### Attendance (Asistencia) Flow

### Offline → Online Transition

- **In-memory**: AuthService.perfil (loaded once at login)
- **Local cache (Hive)**: Obras, catalog, workers, sync state — keyed by last update time
- **Queue (Hive)**: OfflineQueueService.listPending() — holds unsent deliveries with retry metadata
- **Remote (Supabase)**: Source of truth for all data; RLS ensures access control

## Key Abstractions

- Purpose: Represent authenticated user's permissions and module access
- Examples: `lib/services/auth_service.dart` lines 45–78
- Pattern: Singleton loaded at login; checked before write operations
- Purpose: Model queued delivery with offline-safe state machine (PENDING → UPLOADING → SENT, with ERROR backoff)
- Examples: `lib/services/offline_queue_service.dart` lines 9–31
- Pattern: Hive-serialized; includes hash chain (prevHash, hash) for integrity
- Purpose: Model queued attendance record with photo + GPS + device info
- Examples: `lib/asistencia/models/asistencia_pendiente.dart` lines 1–64
- Pattern: Hive-serialized; status tracks sync state (pendiente, subiendo, enviada, fallida)
- Purpose: Semaphore evaluation (OK, WARNING, BLOQUEO) based on stock rules
- Examples: `lib/models/evaluacion_entrega.dart` lines 1–16
- Pattern: Returned by Supabase RPC; used by NewDeliveryPage to show traffic light

## Entry Points

- Location: `lib/main.dart` lines 14–30
- Triggers: `flutter run -t lib/main.dart`
- Responsibilities:
- Location: `lib/main_asistencia.dart` lines 8–20
- Triggers: `flutter run -t lib/main_asistencia.dart` (or separate build variant)
- Responsibilities:
- Location: `lib/main.dart` lines 117–210
- Triggers: App launch when no cached session
- Decides:

## Architectural Constraints

- **Threading:** Single-threaded event loop (Flutter standard). All async I/O (Supabase, camera, geolocator) uses Future/async-await. No worker threads; heavy computation (image compression, hashing) runs on main thread.
- **Global state:** 
- **Circular imports:** None detected; service layer imports presentation layer via callbacks (e.g., ConnectivityService.onSyncComplete), not vice versa
- **Offline mode limitations:**

## Anti-Patterns

### Mixing UI state with persistent state

### No null-safety on service data

### Direct Supabase.instance.client calls in multiple places

## Error Handling

- **Network errors in UI**: Page shows error message + falls back to cached data if available (see LoginGate._entrarDesdeCache, ObrasPage._loadObras)
- **Sync errors**: SyncService respects exponential backoff; failed deliveries stay PENDING in queue for retry
- **Offline without cache**: Force login (cannot enter app without cached profile + obras)
- **Auth failures**: PerfilNoEncontradoException caught, user logged out, returned to LoginPage
- **Evidence capture failures**: If camera or GPS fails, delivery still queued with degraded forensic data (null GPS fields acceptable)

## Cross-Cutting Concerns

- Debugprint statements throughout (e.g., `[SyncService] Pendientes a sincronizar: ${pendings.length}`)
- No centralized logger; ad-hoc debugging
- User input: RUT formatting in RutInputScreen (custom TextInputFormatter `_RutFormatter`)
- EPP quantities: Stock availability checked in NewDeliveryPage._recalcularSemaforo() via RPC `get_evaluacion_entrega`
- Delivery state machine: Enforced by OfflineQueueService (PENDING → UPLOADING → SENT/ERROR)
- Session managed by Supabase.instance.client.auth
- Profile loaded into AuthService.instance._perfil after successful login
- RLS on all tables filters by user org + role
- No explicit token refresh; relies on Supabase SDK

<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->

## Project Skills

| Skill | Description | Path |
|-------|-------------|------|
| supabase | "Use when doing ANY task involving Supabase. Triggers: Supabase products (Database, Auth, Edge Functions, Realtime, Storage, Vectors, Cron, Queues); client libraries and SSR integrations (supabase-js, @supabase/ssr) in Next.js, React, SvelteKit, Astro, Remix; auth issues (login, logout, sessions, JWT, cookies, getSession, getUser, getClaims, RLS); Supabase CLI or MCP server; schema changes, migrations, security audits, Postgres extensions (pg_graphql, pg_cron, pg_vector)." | `.agents/skills/supabase/SKILL.md` |
| supabase-postgres-best-practices | Postgres performance optimization and best practices from Supabase. Use this skill when writing, reviewing, or optimizing Postgres queries, schema designs, or database configurations. | `.agents/skills/supabase-postgres-best-practices/SKILL.md` |
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:

- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->

## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->

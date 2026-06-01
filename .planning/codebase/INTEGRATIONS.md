# External Integrations

**Analysis Date:** 2026-06-01

## APIs & External Services

**Email Notifications:**
- Resend - Transactional email service for EPP expiration alerts
  - SDK/Client: HTTP API (called from Supabase Edge Function at `supabase/functions/notif-vencimiento/index.ts`)
  - Auth: `RESEND_API_KEY` environment variable in Supabase
  - Trigger: Daily at 8:00 AM UTC via pg_cron scheduled job
  - From Address: `TrazApp <notificaciones@trazapp.cl>`
  - Recipients: Users with `recibe_notif_venc = true` in `perfiles` table

**Face Recognition (On-Device):**
- Google ML Kit Face Detection
  - SDK/Client: `google_mlkit_face_detection` 0.11.0
  - Auth: None (runs on-device, no API calls)
  - Used in: `lib/asistencia/screens/camera_capture_screen.dart`
  - Purpose: Detect faces in camera frames for attendance validation (anti-spoofing)

**Location Services (On-Device):**
- Geolocator
  - SDK/Client: `geolocator` 13.0.0
  - Auth: None (uses device GPS, no third-party API)
  - Used in: `lib/services/forensic_service.dart`
  - Purpose: Capture GPS coordinates (lat, lng, accuracy) at time of EPP delivery
  - Permissions: Requires location permission (iOS: NSLocationWhenInUseUsageDescription, Android: ACCESS_FINE_LOCATION)

## Data Storage

**Databases:**
- PostgreSQL (via Supabase)
  - Connection: `https://ppltpmmtdnprgauwnytf.supabase.co`
  - Client: `supabase_flutter` 2.8.0 SDK
  - Tables: 
    - `perfiles` - User profiles with org, role, module config
    - `trabajadores` - Worker records
    - `obras` - Work sites
    - `catalogo_epp` - PPE catalog with expiration rules
    - `entregas_epp` - PPE delivery records (items stored as JSONB)
    - `asistencias` - Attendance records
    - `solicitudes_epp` - PPE requests
    - `stock_movimientos` - Stock history
    - `trabajador_obras` - Worker-to-site assignments
    - `audit_log` - Automatic audit trail (triggers on all critical tables)
  - Authentication: Via Supabase Auth (JWT token in Authorization header)

**File Storage:**
- Supabase Storage (`storage.from('evidencias')`)
  - Bucket: `evidencias` - Photo evidence and signatures
  - Paths: `/{year}/{month}/{day}/{uuid}.{ext}`
  - Access: Public URLs generated via `getPublicUrl()`
  - Used in:
    - `lib/new_delivery_page.dart` - Upload delivery photo and signature
    - `lib/services/sync_service.dart` - Sync offline uploads to cloud
    - `lib/asistencia/screens/camera_capture_screen.dart` - Upload attendance photo

**Local/Offline Storage:**
- Hive (Key-value store)
  - Location: Device local storage via `hive_flutter`
  - Used in:
    - `lib/services/offline_queue_service.dart` - Queue pending operations during offline
    - `lib/services/offline_cache_service.dart` - Cache for profile/org data
    - `lib/services/data_cache_service.dart` - Cache for deliveries, stock, workers
    - `lib/services/cache_service.dart` - Generic cache operations
    - `lib/asistencia/services/asistencia_hive_service.dart` - Offline attendance data

**Caching Strategy:**
- No remote caching layer (Redis, etc.)
- Local caching only via Hive
- Background sync service pushes offline data when connectivity restored

## Authentication & Identity

**Auth Provider:**
- Supabase Auth
  - Method: Email/password authentication
  - Entry point: `lib/main.dart` - `LoginPage` widget
  - Flow:
    1. User enters email + password
    2. `Supabase.instance.client.auth.signInWithPassword()` authenticates
    3. `AuthService.instance.cargarPerfil()` fetches user profile from `perfiles` table
    4. Profile cached in memory (`PerfilUsuario` singleton in `lib/services/auth_service.dart`)
    5. Session stored in device secure storage (Supabase SDK handles)
  - Token: JWT in Authorization header (managed by SDK)
  - Offline Access: Partial - cached profile used if offline, but cannot refresh session without connectivity

**Roles & Authorization:**
- Three-tier: ADMIN, SUPERVISOR, READONLY
- Configured in `perfiles` table via `rol` column
- Row-level security (RLS) policies enforce access in Supabase (see `supabase/security_hardening.sql`)

## Monitoring & Observability

**Error Tracking:**
- None - No error tracking service integrated (Sentry, Bugsnag, etc.)
- Errors logged to console via `debugPrint()` in development

**Logs:**
- Supabase: Automatic request logs in dashboard
- Flutter: Console logs via `debugPrint()` (debug mode only)
- Audit: Automatic audit log triggers on critical tables (`audit_log` table via `supabase/audit_log.sql`)
  - Tracks INSERT/UPDATE/DELETE on: `entregas_epp`, `stock_movimientos`, `trabajadores`, `asistencias`, `solicitudes_epp`

**Analytics:**
- None - No analytics service integrated

## CI/CD & Deployment

**Hosting:**
- Android: Google Play Store (build via Flutter)
- iOS: Apple App Store (build via Xcode/Flutter)
- Web: Flutter for Web (hosted on CDN, typically)
- Dashboard: Static HTML at `dashboard/index.html` and `website/index.html` (likely hosted on Supabase Hosting or separate CDN)

**CI Pipeline:**
- None detected - No GitHub Actions, GitLab CI, or similar configured

**Supabase Deployment:**
- Edge Functions: Manual deploy via Supabase CLI to project `ppltpmmtdnprgauwnytf`
- SQL Migrations: Manual execution of `.sql` files in `supabase/` directory via Supabase SQL Editor
- No automated migration runner detected

## Environment Configuration

**Required env vars (Backend/Edge Functions):**
- `SUPABASE_URL` - Supabase project URL
- `SUPABASE_SERVICE_ROLE_KEY` - Service role key (for functions with bypass RLS)
- `RESEND_API_KEY` - Resend API key for email notifications

**Secrets location:**
- Flutter app: Hardcoded in `lib/config/supabase_config.dart` (anon key is public)
- Edge Functions: Supabase Project Settings → API → Environment Variables

**Runtime Configuration (App-specific):**
- `lib/main.dart` - Main EPP management app
- `lib/main_asistencia.dart` - Attendance app (alternative entry point)
- Both share Supabase config and local storage initialization

## Webhooks & Callbacks

**Incoming:**
- None detected

**Outgoing:**
- Supabase triggers:
  - `audit_log` table - Automatic triggers on critical tables (see `supabase/audit_log.sql`)
  - Custom RPC functions that can call external APIs via pg_net (not actively used beyond Resend)

**Scheduled Jobs (pg_cron):**
- `notif-vencimiento-diario` - Daily at 8:00 AM UTC
  - Calls Edge Function: `POST https://[PROJECT_ID].supabase.co/functions/v1/notif-vencimiento`
  - Function: `supabase/functions/notif-vencimiento/index.ts`
  - Detects EPP expiring in 7 or 30 days
  - Sends HTML email via Resend API
  - Requires: `pg_cron` and `pg_net` extensions enabled in Supabase

## Data Privacy & Security

**Encryption:**
- Transit: HTTPS (Supabase enforces TLS)
- At rest: Supabase default encryption (AES-256)
- Hashing: SHA256 for forensic data integrity (via `crypto` package)

**RLS Policies:**
- Configured in Supabase via `supabase/security_hardening.sql`
- Users can only access data for their organization (`org_id` match)
- READONLY users have restricted UPDATE/DELETE permissions

**Data Validation:**
- Client-side: Flutter forms validate email, RUT format
- Server-side: Supabase triggers and RLS policies enforce constraints

---

*Integration audit: 2026-06-01*

# Technology Stack

**Analysis Date:** 2026-06-01

## Languages

**Primary:**
- Dart 3.10.8+ - Flutter app codebase for iOS, Android, web
- TypeScript - Supabase Edge Functions (Node.js runtime)
- SQL - Database schema and stored procedures (PostgreSQL)

**Secondary:**
- HTML/CSS - Web UI static assets (`web/`, `dashboard/`, `website/`)

## Runtime

**Environment:**
- Flutter SDK (latest stable) - Cross-platform mobile/web framework
- Dart VM - Dart runtime for Flutter apps
- Deno (via Supabase Edge Functions) - TypeScript/JavaScript runtime for serverless functions

**Package Manager:**
- Pub - Dart package manager
- Lockfile: `pubspec.lock` (present)

## Frameworks

**Core:**
- Flutter 3.x - Cross-platform UI framework
- Material Design 3 - UI design system (via `package:flutter`)
- Supabase Flutter SDK 2.8.0 - Backend-as-a-service client

**Backend/Database:**
- PostgreSQL (via Supabase) - Relational database
- Supabase Edge Functions - Serverless compute (Deno runtime)
- Supabase Storage - File storage for images/documents
- Supabase Auth - Authentication provider

**Local Storage:**
- Hive 2.2.3 - Local key-value storage for offline data
- Hive Flutter 1.1.0 - Flutter integration for Hive

## Key Dependencies

**Critical Infrastructure:**
- `supabase_flutter` 2.8.0 - Supabase client for Dart, handles auth, database, storage access
- `hive` 2.2.3 - Local NoSQL database for offline caching
- `hive_flutter` 1.1.0 - Hive initialization and Flutter integration

**Connectivity & Offline:**
- `connectivity_plus` 6.0.0 - Network connectivity detection (iOS/Android/web)

**Camera & Biometrics:**
- `camera` 0.10.6 - Camera access for photo capture
- `google_mlkit_face_detection` 0.11.0 - Face detection via Google ML Kit (no cloud API calls)
- `image_picker` 1.0.0 - Image selection from gallery/camera

**Location Services:**
- `geolocator` 13.0.0 - GPS location capture with permission handling

**Device Information:**
- `device_info_plus` 10.1.0 - Device model, OS version, hardware ID retrieval

**Document & PDF:**
- `pdf` 3.11.3 - PDF generation for reports
- `printing` 5.13.0 - Printing and PDF export
- `file_picker` 8.0.0 - File system access for document selection

**Cryptography:**
- `crypto` 3.0.3 - SHA256 hashing for forensic data

**Utilities:**
- `uuid` 4.4.2 - UUID v4 generation for event IDs
- `intl` 0.19.0 - Internationalization (date/time formatting for Spanish)
- `signature` 5.4.0 - Signature capture widget
- `flutter_image_compress` 2.3.0 - Image compression before upload

**Cupertino:**
- `cupertino_icons` 1.0.8 - iOS-style icon pack

**Development:**
- `flutter_lints` 6.0.0 - Lint rules for Dart/Flutter
- `flutter_launcher_icons` 0.13.1 - App icon generation for Android/iOS
- `flutter_test` - Flutter testing framework

## Configuration

**Environment:**
- Supabase configuration hardcoded in `lib/config/supabase_config.dart`:
  - `SupabaseConfig.url`: Production Supabase project URL
  - `SupabaseConfig.anonKey`: Public anon key for client-side access
  - Used by both `main.dart` (EPP app) and `main_asistencia.dart` (Attendance app)

**Backend Services:**
- Supabase project: `ppltpmmtdnprgauwnytf`
- Database: PostgreSQL via Supabase
- Authentication: Supabase Auth (email/password)
- Notifications: Resend API (via Edge Function `notif-vencimiento`)
- Scheduled Jobs: pg_cron (Supabase extension) triggers daily notification function at 8:00 AM UTC

**Build Configuration:**
- `pubspec.yaml` - Dart/Flutter manifest
- `analysis_options.yaml` - Linter configuration (extends `package:flutter_lints`)
- `flutter_launcher_icons-epp.yaml` - Icon config for main app
- `flutter_launcher_icons-asistencia.yaml` - Icon config for attendance app
- `.metadata` - Flutter project metadata
- Platform-specific:
  - `android/` - Android Gradle build configuration
  - `ios/` - iOS Xcode build configuration
  - `web/` - Web build (Flutter for web)
  - `macos/`, `linux/` - Desktop platform configs

## Platform Requirements

**Development:**
- Flutter SDK 3.10.8 or later
- Dart 3.10.8 or later
- Android SDK (API 21+) for Android builds
- Xcode (macOS/iOS builds)
- For backend development: Supabase CLI, Deno runtime (for local Edge Function testing)

**Production:**
- Android 5.1+ (API 21) - Set in `flutter_launcher_icons-epp.yaml`
- iOS 11.0+ (implicit via Flutter)
- Web: Modern browser with WebGL support
- Backend: Supabase cloud hosting (no on-premise required)
- Email notifications: Resend API (requires API key in Supabase environment secrets)
- Scheduled tasks: pg_cron and pg_net extensions enabled in Supabase

**External Integrations Used:**
- Supabase (authentication, database, storage, edge functions)
- Google ML Kit (on-device face detection, no cloud calls)
- Resend (email notifications for EPP expiration)
- Geolocator (device GPS, no third-party API)

---

*Stack analysis: 2026-06-01*

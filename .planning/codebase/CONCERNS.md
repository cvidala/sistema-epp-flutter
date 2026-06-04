# Codebase Concerns

**Analysis Date:** 2026-06-01

## Tech Debt

**Print statements instead of structured logging:**
- Issue: Codebase uses `print()` and `debugPrint()` extensively instead of a proper logging framework
- Files: `lib/services/data_cache_service.dart`, `lib/services/sync_service.dart`, `lib/services/connectivity_service.dart`, multiple pages
- Impact: No log levels, filtering, or centralized log management. Difficult to debug in production. Logs mixed with debug output.
- Fix approach: Implement structured logging service (e.g., `logger` package) with configurable log levels, file output support, and log rotation

**Large monolithic page files:**
- Issue: Page files exceed 1000+ lines, mixing UI, business logic, state management, and data persistence
- Files: `lib/new_delivery_page.dart` (1524 lines), `lib/worker_detail_page.dart` (1062 lines), `lib/workers_page.dart` (958 lines)
- Impact: Difficult to test, maintain, and modify. High cognitive complexity. Violates single responsibility principle.
- Fix approach: Extract service layers, create reusable widgets, separate concerns into smaller, focused classes

**Multiple cache implementations:**
- Issue: Three separate caching services exist: `CacheService`, `OfflineCacheService`, `DataCacheService` with overlapping responsibilities
- Files: `lib/services/cache_service.dart`, `lib/services/offline_cache_service.dart`, `lib/services/data_cache_service.dart`, `lib/services/data_cache_service.dart`
- Impact: Risk of cache inconsistency, code duplication, difficulty knowing which cache to use
- Fix approach: Consolidate into single unified cache layer with clear separation between local device cache and offline sync queue

**No type safety in dynamic data handling:**
- Issue: Extensive use of `dynamic` types, loose casting with `Map<String, dynamic>`, unsafe list access
- Files: Throughout - `lib/new_delivery_page.dart`, `lib/workers_page.dart`, `lib/stock_page.dart`
- Impact: Runtime errors from type mismatches, no IDE type checking, risk of null pointer exceptions
- Fix approach: Generate models from database schema, use code generation tools (build_runner, freezed), enforce strong typing throughout

**Hard-coded API credentials in main.dart:**
- Issue: Supabase URL and anonymous key hard-coded directly in source code
- Files: `lib/main.dart` (lines 23-27)
- Impact: Credentials visible in version control, risk of exposure in compiled apps
- Fix approach: Use environment configuration files (`.env`), flutter_dotenv, or build flavors; implement secure credential storage

**Bare catch blocks silencing errors:**
- Issue: Multiple catch blocks catching all exceptions silently without logging or re-throwing
- Files: `lib/new_delivery_page.dart` (line 228: `catch (_)`), `lib/services/sync_service.dart` (multiple locations)
- Impact: Errors hidden from debugging, production issues hard to diagnose
- Fix approach: Log all caught exceptions with context, distinguish between handled and unhandled errors, use specific exception types

## Known Bugs

**Offline/online state race condition:**
- Symptoms: Flags like `modoOffline` and `evaluando` can become inconsistent if rapid state changes occur. Semaphore evaluation might fire when offline.
- Files: `lib/new_delivery_page.dart` (lines 174-181: `_programarEvaluacionSemaforo()`)
- Trigger: Rapid network transitions or concurrent user actions while connectivity is unstable
- Workaround: Current code includes guards (`if (modoOffline) return`) but timing issues remain possible with concurrent Futures

**Potential deadlock in offline sync queue:**
- Symptoms: Entries stuck in ERROR state with backoff, may never retry if backoff calculation overflows or time comparison fails
- Files: `lib/services/offline_queue_service.dart` (lines 115-120: `backoffDelay` calculation)
- Trigger: Very old entries (attempts > 6) hit max backoff; `DateTime.now()` comparison edge cases
- Workaround: Manual sync button in UI can force retry

**Face detection false negatives when lighting is poor:**
- Symptoms: Camera capture hangs on "Posiciona tu rostro en el óvalo" when face not reliably detected
- Files: `lib/asistencia/screens/camera_capture_screen.dart` (lines 86-96: face filtering heuristics)
- Trigger: Low light, extreme angles, partially obscured face
- Workaround: Increase hold duration or relax heuristics (15% width minimum may be too strict)

**Signature controller disposal not canceling ongoing operations:**
- Symptoms: Potential memory leak if `_mostrarPanelFirma()` exits before `_firmaCtrl.toPngBytes()` completes
- Files: `lib/new_delivery_page.dart` (lines 856-928, dispose at 75-79)
- Trigger: User closes signature panel rapidly while conversion in progress
- Workaround: Current code checks `if (png != null)` and `if (mounted)` but race condition still possible

## Security Considerations

**GPS and device data stored in plaintext:**
- Risk: Forensic data (GPS coordinates, device identifiers) stored unencrypted in offline queue and sent to server
- Files: `lib/services/forensic_service.dart`, `lib/services/sync_service.dart` (line 123: `forensics_gps_lat`)
- Current mitigation: Stored on device only, encrypted by device storage; transmitted over HTTPS
- Recommendations: Add database-level encryption for forensic fields; implement selective disclosure (only transmit when required); add audit logging for GPS access

**No input validation on RUT field:**
- Risk: Although RUT format is enforced client-side, server RPC should validate format independently
- Files: `lib/workers_page.dart`, forms lack SQL input validation mention
- Current mitigation: RLS policies on Supabase tables
- Recommendations: Implement server-side RUT format validation in RPC functions; sanitize all user inputs at database layer

**Offline queue contains full delivery data without encryption:**
- Risk: Evidence images, signature PNGs, and delivery metadata stored unencrypted on device in Hive
- Files: `lib/services/offline_queue_service.dart` (Hive box `outbox_entregas`)
- Current mitigation: Device storage encryption (Android KeyStore, iOS Keychain)
- Recommendations: Implement Hive encryption, use `hive_sealed_boxes`; consider differential privacy for sensitive forensic data

**No session timeout enforcement:**
- Risk: Authenticated session remains valid indefinitely if not explicitly logged out
- Files: `lib/main.dart` (LoginGate), auth_service.dart - no timeout mechanism visible
- Current mitigation: Supabase session management
- Recommendations: Implement client-side session timeout, require re-authentication after X minutes, clear cached credentials on timeout

**Hardcoded debug print exposure:**
- Risk: Sensitive operational data logged to console (event IDs, hash values, sync status)
- Files: Throughout - `lib/new_delivery_page.dart`, `lib/services/sync_service.dart`, etc.
- Current mitigation: `debugPrint()` only active in debug builds
- Recommendations: Implement log sanitization, mask PII and sensitive IDs; use environment-specific log levels

## Performance Bottlenecks

**Large list rendering without virtualization:**
- Problem: Workers list, stock items, and entrega history rendered without pagination or lazy loading
- Files: `lib/workers_page.dart` (line 36: `List<dynamic> trabajadores`), `lib/stock_page.dart` (line 22: `stockItems`)
- Cause: Full data fetch with no limit, all items built into widget tree
- Improvement path: Implement `ListView.builder()` with pagination cursors; add `.limit(50)` to database queries; implement infinite scroll with threshold detection

**Face detection on every frame in camera screen:**
- Problem: ML Kit face detection runs on every camera frame (30+ FPS) even when already holding a valid face
- Files: `lib/asistencia/screens/camera_capture_screen.dart` (lines 76-134: `_procesarFrame()`)
- Cause: No frame skipping or debouncing of detection results
- Improvement path: Skip processing if face already detected for N frames; reduce frame processing rate; implement multi-threading for ML operations

**Synchronous Hive reads/writes in hot paths:**
- Problem: Offline queue and cache operations are async but called frequently without buffering
- Files: `lib/services/offline_queue_service.dart`, `lib/services/sync_service.dart` (line 38: `await OfflineQueueService.update(e)`)
- Cause: Each offline delivery write is an individual Hive operation
- Improvement path: Batch writes in transactions; implement write-ahead logging; cache in-memory until flush window

**No connection pooling for Supabase queries:**
- Problem: Each UI action spawns new HTTP request to Supabase; no query batching or caching
- Files: Multiple pages fetch data independently without shared requests
- Cause: Direct `.from()` calls on supabase client without coordination
- Improvement path: Implement request coalescing, batch RPC calls, add response caching layer

## Fragile Areas

**Offline queue state management:**
- Files: `lib/services/offline_queue_service.dart`, `lib/services/sync_service.dart`
- Why fragile: Complex state machine (PENDING → UPLOADING → SENT / ERROR) with exponential backoff. Race conditions between sync worker and UI updates. No distributed locking.
- Safe modification: Add comprehensive state transition tests; implement optimistic locking with timestamps; add state consistency checks on app startup
- Test coverage: No unit tests visible for queue state transitions or backoff logic

**Forensic data capture timing:**
- Files: `lib/services/forensic_service.dart`, `lib/new_delivery_page.dart` (line 923: called after signature)
- Why fragile: Captures GPS at signature time, but position may be inaccurate if device was stationary. No validation that captured location is reasonable (could be spoofed).
- Safe modification: Add location sanity checks (reasonable coordinates, not teleporting); capture multiple GPS points and average; add timestamp validation against server time
- Test coverage: No tests for forensic service error cases (GPS disabled, permission denied timeouts)

**Cache invalidation with multiple sources:**
- Files: `lib/services/cache_service.dart`, `lib/services/offline_cache_service.dart`
- Why fragile: Data can come from online sync, offline queue, or previous cache. No clear invalidation strategy. Stale data may be served indefinitely.
- Safe modification: Implement cache versioning with TTL; add cache coherence checks; store sync timestamp with each cached item; invalidate cache on version mismatch
- Test coverage: No integration tests for cache consistency across online/offline transitions

**Connectivity detection dependent on Supabase query:**
- Files: `lib/services/connectivity_service.dart` (line 120: `from('obras')` query)
- Why fragile: Assumes Supabase availability = internet availability. If backend is down, app treats it as offline. No fallback to ping-based detection.
- Safe modification: Add multiple connectivity checks (DNS, ICMP, known service); implement timeout escalation; add circuit breaker pattern
- Test coverage: No tests for false offline detection when backend is slow

## Scaling Limits

**Single Hive instance for all offline data:**
- Current capacity: Single `outbox_entregas` box and monolithic offline cache
- Limit: Hive not designed for sharding; performance degrades with large box size (~1000+ entries)
- Scaling path: Implement per-obra queue partitioning; migrate to SQLite for offline storage; add archive mechanism for old sync entries

**Firebase ML Kit face detection library loading:**
- Current capacity: Single detector instance per app lifecycle
- Limit: Large model size; slow model loading on first use; memory footprint
- Scaling path: Lazy load ML Kit model; implement model caching; consider lighter alternative like `tflite_flutter`

**Direct Supabase client initialization:**
- Current capacity: Single Supabase client instance (line 48: `final supabase = Supabase.instance.client`)
- Limit: No request prioritization, no queue depth management; potential for unbounded concurrent requests
- Scaling path: Implement request queue with priority levels; add connection pooling; implement rate limiting

## Dependencies at Risk

**`google_mlkit_face_detection: ^0.11.0`:**
- Risk: Large binary dependency; model files add significant APK/IPA size; Google ML Kit is deprecated in favor of Google's new ML Kit libraries
- Impact: Face detection failures if model files corrupt or device storage low; slow initialization
- Migration plan: Evaluate migration to `google_ml_kit` v2 or TensorFlow Lite models; consider cloud-based face detection API for reduced app size

**`signature: ^5.4.0`:**
- Risk: Package has no recent updates (may be unmaintained); custom drawing canvas implementation
- Impact: Signature capture may fail on future Flutter versions; no support for pressure-sensitive stylus
- Migration plan: Monitor package updates; evaluate alternatives like `hand_signature` or platform-native signing

**`hive: ^2.2.3` for offline storage:**
- Risk: Hive has history of data corruption with malformed boxes; no built-in encryption
- Impact: Offline queue data can become unreadable, blocking app startup
- Migration plan: Add Hive migration/recovery code; consider Isar (faster, type-safe); implement pre-flight Hive integrity check on init

**`connectivity_plus: ^6.0.0`:**
- Risk: Platform-specific behavior; unreliable on Android 10+ due to permission changes
- Impact: Offline detection may be incorrect; false offline states
- Migration plan: Supplement with direct Supabase connectivity test (already done in `connectivity_service.dart`); monitor platform changes

## Missing Critical Features

**No error recovery for partial sync failures:**
- Problem: If sync partially completes (some items sent, some failed), no mechanism to detect and resume
- Blocks: Reliable offline sync in intermittent connectivity scenarios
- Recommendation: Implement atomic RPC transactions; add per-item retry with idempotency keys; log partial failures for audit

**No signature verification in offline delivery:**
- Problem: Offline deliveries use signature image but no validation that signature matches worker
- Blocks: Chain-of-custody verification for offline transactions
- Recommendation: Implement signature quality validation; add signature-to-device-id binding; require server-side verification of signature hash

**No backup mechanism for offline data:**
- Problem: If device storage corrupted or app uninstalled, offline queue lost permanently
- Blocks: Data recovery after app crashes or reinstallation
- Recommendation: Implement encrypted cloud backup of offline queue; add iCloud/Google Drive integration; provide user-facing queue status dashboard

**No audit trail for cache operations:**
- Problem: Cache invalidation, misses, and stale data access not logged
- Blocks: Debugging data inconsistency issues in production
- Recommendation: Add cache operation logging with hit/miss metrics; implement cache coherence monitoring; add analytics for offline → online transition success rates

## Test Coverage Gaps

**Offline queue state transitions:**
- What's not tested: State machine transitions (PENDING → UPLOADING → SENT, ERROR states, backoff logic), concurrent sync operations
- Files: `lib/services/offline_queue_service.dart`, `lib/services/sync_service.dart`
- Risk: Entries could get stuck in invalid states undetected; race conditions on state updates
- Priority: High - critical for data integrity

**Connectivity and sync edge cases:**
- What's not tested: Offline → online transitions during in-flight requests, network timeouts, partial response handling, concurrent sync calls
- Files: `lib/services/connectivity_service.dart`, `lib/services/sync_service.dart`
- Risk: Undetected sync failures, data duplication, orphaned entries
- Priority: High - affects production reliability

**Cache invalidation scenarios:**
- What's not tested: Stale data serving after server update, cache miss fallback behavior, concurrent cache updates from multiple sources
- Files: `lib/services/cache_service.dart`, `lib/services/offline_cache_service.dart`
- Risk: App serves outdated worker/EPP/warehouse data; users see stale information
- Priority: Medium - data freshness issue

**Face detection robustness:**
- What's not tested: Low-light conditions, face detection timeouts, multiple faces in frame, rapid face loss/reappearance
- Files: `lib/asistencia/screens/camera_capture_screen.dart`
- Risk: Attendance capture hangs or captures wrong person
- Priority: Medium - user experience degradation

**Forensic data capture errors:**
- What's not tested: GPS permission denied/timeout, device info fetch failures, concurrent forensic captures
- Files: `lib/services/forensic_service.dart`
- Risk: App crash if forensic service fails; data inconsistency if partial data captured
- Priority: Medium - impacts evidence integrity

---

*Concerns audit: 2026-06-01*

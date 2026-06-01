# Coding Conventions

**Analysis Date:** 2026-06-01

## Naming Patterns

**Files:**
- Pages: `_page.dart` (e.g., `workers_page.dart`, `stock_page.dart`)
- Services: `_service.dart` (e.g., `auth_service.dart`, `sync_service.dart`)
- Models: `_pendiente.dart`, `_entrega.dart`, or plain model names (e.g., `asistencia_pendiente.dart`, `evaluacion_entrega.dart`)
- Screens: `_screen.dart` (e.g., `camera_capture_screen.dart`)

**Classes:**
- Public classes: PascalCase (e.g., `WorkersPage`, `LoginPage`, `AuthService`)
- Private (inner) classes: `_ClassName` with underscore prefix (e.g., `_LoginGateState`, `_StockPageState`, `_FaceOvalPainter`)
- State classes for StatefulWidget: `_WidgetNameState` (e.g., `_LoginPageState`, `_WorkersPageState`)

**Functions and Methods:**
- Public functions: camelCase (e.g., `cargarPerfil()`, `syncOnce()`, `markSent()`)
- Private methods: `_methodName` with underscore prefix (e.g., `_loadWorkers()`, `_check()`, `_runSync()`)
- Async methods: marked with `Future<ReturnType>` or `async`
- Callback/listener methods: start with `_on` prefix (e.g., `_onStatusChange()`, `_onSyncComplete()`)

**Variables:**
- Local variables: camelCase (e.g., `loading`, `error`, `trabajadores`, `bodegaId`)
- Instance variables: camelCase (e.g., `searchCtrl`, `supabase`, `_syncing`, `_perfil`)
- Constants: SCREAMING_SNAKE_CASE (e.g., `_boxName`, `const Duration(seconds: 10)`)
- Boolean flags: prefixed with `is` or `_` underscore (e.g., `isAdmin`, `_syncing`, `_estabaOnline`)

**Types:**
- Classes: PascalCase (e.g., `PerfilUsuario`, `ConfigModulos`, `OfflineEntrega`)
- Enums: PascalCase items (e.g., status values: `'PENDING'`, `'SENT'`, `'ERROR'`)
- Typedefs: PascalCase (e.g., `VoidCallback`)

## Code Style

**Formatting:**
- No explicit code formatter configured (using Dart/Flutter defaults)
- Line length: observed 80-100 character limit in many files
- Indentation: 2 spaces (standard Dart)
- Trailing commas: used in multi-line collections and function arguments for cleaner diffs

**Linting:**
- Uses `flutter_lints: ^6.0.0`
- Config: `analysis_options.yaml` with base `package:flutter_lints/flutter.yaml`
- Most linting rules are defaults; custom rules commented out
- Linting can be checked with: `flutter analyze`

**Null Safety:**
- Dart null safety enforced (requires SDK ^3.10.8)
- Use `?` for nullable types and `!` for non-nullable assertions where certain
- Null coalescing with `??` (e.g., `data['status'] ?? 'OK'`)

## Import Organization

**Order:**
1. Dart imports (`dart:async`, `dart:convert`, `dart:io`, etc.)
2. Package imports (Flutter, Supabase, etc.) from `package:`
3. Relative imports from same project (using `./` or plain relative paths)

**Example from `lib/new_delivery_page.dart`:**
```dart
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';
import 'evidence_service.dart';
import 'models/evaluacion_entrega.dart';
```

**Path Aliases:**
- No path aliases configured in `pubspec.yaml`
- Imports use relative paths: `import 'services/auth_service.dart'`

## Error Handling

**Exception Types:**
- Custom exceptions: implement `Exception` interface (e.g., `PerfilNoEncontradoException`)
- Use `on SpecificException catch (e)` for known exception types
- Use bare `catch (e)` for unexpected errors, typically converting to string
- Exceptions include `toString()` methods for logging

**Error Propagation:**
```dart
// Example from auth_service.dart
try {
  // operation
} on PerfilNoEncontradoException catch (e) {
  // handle specific case
  await Supabase.instance.client.auth.signOut();
  setState(() => error = e.message);
} catch (e) {
  // generic error
  setState(() => error = e.toString());
}
```

**State Updates:**
- Errors stored in local state (`String? error`)
- Set via `setState(() => error = e.toString())` in StatefulWidgets
- Error display conditional: `if (error != null) { ... }`

## Logging

**Framework:** `debugPrint()` from `package:flutter/foundation.dart`

**Patterns:**
- Prefix logs with service name in brackets: `debugPrint('[SyncService] ...')`
- Log state transitions: `debugPrint('[Connectivity] Estado cambió → ONLINE')`
- Include operation counts in summaries: `'enviadas: $enviadas, errores: $errores'`
- Use symbols for status: `✅` (success), `❌` (error), `⏳` (waiting), `⛔` (failed)
- No logging output to console in production (all `debugPrint` calls ignored)

**Examples:**
```dart
debugPrint('[Connectivity] Estado cambió → ${online ? "ONLINE" : "OFFLINE"}');
debugPrint('[SyncService] ✅ ${e.localEventId} → SENT');
debugPrint('[SyncService] ⏳ ${e.localEventId} → retry en ${delayMin}min');
```

## Comments

**When to Comment:**
- Comment complex logic (state machine transitions, backoff calculations)
- Document non-obvious control flow (if/else chains, nested async operations)
- Explain business rules and constraints (e.g., RLS checks, permission resolution)
- Mark code as "✅ FIX" or similar when addressing known issues

**JSDoc/TSDoc:**
- Limited use; Dart uses `///` for doc comments
- Used for public APIs and complex classes
- Example from `auth_service.dart`:
```dart
/// Servicio singleton que carga y cachea el perfil del usuario actual.
///
/// Uso:
///   await AuthService.instance.cargarPerfil();
///   final perfil = AuthService.instance.perfil;
class AuthService {
  ...
}
```

**Inline Comments:**
- Used sparingly
- Multi-line section dividers: `// ─────────────────────────────────────────────`
- Status markers: `// ── Step description ─────────────────`

## Function Design

**Size:**
- Typical functions: 10-50 lines
- Larger methods allowed in page/widget state classes (up to 100+ lines for complex UI logic)
- Complex business logic extracted to services

**Parameters:**
- Use positional parameters for required values
- Use named parameters for optional values
- Constructor parameters marked `required` when mandatory
- Example from `NewDeliveryPage`:
```dart
const NewDeliveryPage({
  super.key,
  required this.obraId,
  required this.obraNombre,
  required this.trabajadorId,
  required this.trabajadorNombre,
  required this.trabajadorRut,
});
```

**Return Values:**
- Most async operations return `Future<T>` or `Future<void>`
- Complex results returned as `Map<String, dynamic>` or typed objects
- Void callbacks via `VoidCallback` type alias

## Module Design

**Exports:**
- No barrel files observed (`index.dart`)
- Imports use direct file paths
- Services organized in `lib/services/` directory
- Pages in `lib/` root or `lib/asistencia/` subdirectory

**Singleton Pattern:**
- Services use private constructor and static `instance` getter
- Example from `auth_service.dart`:
```dart
class AuthService {
  AuthService._();
  static final instance = AuthService._();
}
```

**Service Initialization:**
- Services require explicit `init()` calls in `main()` before use
- Hive boxes initialized via `Hive.openBox()` in service `init()` methods
- StateManager pattern for lifecycle: `_box` stored as static variable, accessed via getter

## Specific Dart/Flutter Conventions

**State Management:**
- StatefulWidget + State pattern throughout (no Provider, Bloc, or Riverpod)
- Local state: `bool`, `String`, `List` instance variables
- State updates via `setState(() => { ... })`
- Async operations initiated in `initState()` or callbacks

**Widget Lifecycle:**
- `initState()`: load data, start listeners
- `dispose()`: cleanup controllers, cancel timers
- Always check `if (mounted)` before `setState()` in async callbacks

**Text Input:**
- TextEditingController instances created and disposed
- Controllers accessed via property, not recreated per build

**Navigation:**
- `MaterialPageRoute` for screen transitions
- Use `Navigator.of(context).pushReplacement()` for login/auth flows
- Parameters passed via constructor to target page

---

*Convention analysis: 2026-06-01*

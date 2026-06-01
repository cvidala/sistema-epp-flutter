# Testing Patterns

**Analysis Date:** 2026-06-01

## Test Framework

**Runner:**
- `flutter_test` (included in SDK)
- SDK: Dart ^3.10.8
- Config: None (uses default Flutter test runner)

**Assertion Library:**
- Flutter's built-in `expect()` function from `flutter_test` package
- Matchers: `findsOneWidget`, `findsNothing`, `findsWidgets`

**Run Commands:**
```bash
flutter test                    # Run all tests
flutter test -v                 # Run with verbose output
flutter test --coverage         # Generate coverage report
flutter test test/widget_test.dart  # Run single test file
```

## Test File Organization

**Location:**
- Test files placed in `test/` directory at project root
- One test file exists: `test/widget_test.dart`
- **Pattern:** Co-located in separate `test/` directory (not alongside source code)

**Naming:**
- Test files: `*_test.dart` (e.g., `widget_test.dart`)
- No test specifications observed for services or models

**Structure:**
```
test/
├── widget_test.dart    # Widget and smoke tests
```

## Test Structure

**Suite Organization:**
```dart
// From test/widget_test.dart
void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Test body
  });
}
```

**Patterns:**
- Single `void main()` entry point
- Test cases declared with `testWidgets()` for widget tests
- Test function receives `WidgetTester` parameter for widget interaction
- Async test functions prefixed with `async` keyword

**Setup/Teardown:**
- Implicit: `testWidgets()` automatically initializes Flutter binding
- No explicit setup/teardown observed
- Widget cleanup automatic at test end

## Mocking

**Framework:**
- No explicit mocking library in dependencies
- Supabase and external services not mocked in current tests

**Patterns:**
- Current test suite is minimal (smoke test only)
- No service mocks, no database mocks observed

**What NOT Mocked:**
- Full app widget (`MyApp()` instantiated in test)
- UI layer fully exercised in widget tests

## Fixtures and Factories

**Test Data:**
- No fixtures or factories defined
- Smoke test uses simple assertions on default state

**Location:**
- `test/` directory (could expand with helper classes)

## Coverage

**Requirements:** None enforced

**View Coverage:**
```bash
flutter test --coverage
```

## Test Types

**Widget Tests:**
- **Scope:** Full app initialization and basic user interaction
- **Approach:** Uses `WidgetTester` to pump widgets and verify UI state
- **Example:** `test/widget_test.dart` - tests counter increment on button tap
- **Pattern:**
  ```dart
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());  // Build app
    expect(find.text('0'), findsOneWidget);  // Assert initial state
    await tester.tap(find.byIcon(Icons.add)); // Interact
    await tester.pump();                      // Trigger rebuild
    expect(find.text('1'), findsOneWidget);  // Assert result
  });
  ```

**Unit Tests:**
- Not implemented
- Services (`AuthService`, `SyncService`, etc.) have no unit tests
- Models (`PerfilUsuario`, `OfflineEntrega`) have no unit tests

**Integration Tests:**
- Not implemented
- No E2E tests defined

**E2E Tests:**
- Not used
- No `integration_test/` directory present

## Common Patterns

**Widget Finding:**
```dart
find.text('label')              # Find by text content
find.byIcon(Icons.add)          # Find by icon
find.byWidget(widget)           # Find by widget instance
find.byType(WidgetType)         # Find by type
```

**Widget Interaction:**
```dart
await tester.tap(finder)        # Simulate tap
await tester.pump()             # Trigger frame rebuild
await tester.pumpWidget(widget) # Build widget and render
```

**Assertions:**
```dart
expect(finder, findsOneWidget)  # Expects exactly one match
expect(finder, findsNothing)    # Expects no matches
expect(finder, findsWidgets)    # Expects one or more matches
expect(value, equals(expected)) # Assert value equality
```

## Testing Gaps

**Critical Areas Without Tests:**
- `AuthService` - Profile loading, permission checks
- `SyncService` - Offline sync, retry logic, hash chain validation
- `ForensicService` - GPS capture, device info collection
- `OfflineQueueService` - Hive storage, state transitions
- All page/screen widgets except basic app startup

**Impact:**
- No regression detection for auth flows
- Sync errors may go undetected until production
- Refactoring services carries risk of breaking offline functionality

## Recommendations for Testing

1. **Unit Tests for Services:**
   - Mock Supabase client
   - Test `AuthService.cargarPerfil()` with various permission scenarios
   - Test `SyncService.syncOnce()` with simulated offline conditions

2. **Integration Tests:**
   - Test full offline-to-online sync flow
   - Test permission resolution across roles (ADMIN, SUPERVISOR, READONLY)

3. **Widget Test Expansion:**
   - Test login flow (success, invalid credentials, network errors)
   - Test page navigation and data loading
   - Test offline mode indicators

4. **Mocking Strategy:**
   - Create test doubles for `SupabaseClient`
   - Mock Hive boxes for local storage tests
   - Mock `connectivity_plus` for offline scenarios

---

*Testing analysis: 2026-06-01*

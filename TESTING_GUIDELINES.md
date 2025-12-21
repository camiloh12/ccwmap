# Testing Guidelines

## Critical Rule: Never Leave Failing Tests

**IMPORTANT**: Always ensure all tests pass before considering any work complete.

### Why This Matters

1. **Broken Windows Theory**: One failing test leads to more failing tests. If tests are allowed to fail, developers stop trusting the test suite and ignore failures.

2. **CI/CD Integrity**: Failing tests break continuous integration pipelines and prevent deployments.

3. **Regression Detection**: You can't detect new bugs if existing tests are already failing.

4. **Code Quality Signal**: A green test suite is a signal that the codebase is in a good state.

### What To Do

✅ **ALWAYS**:
- Fix failing tests immediately when you discover them
- Run tests before committing code
- Ensure all tests pass after refactoring
- Update tests when changing functionality
- Add `setUpAll` or `setUp` methods to properly initialize test dependencies

❌ **NEVER**:
- Commit code with failing tests
- Comment out failing tests "temporarily"
- Skip or ignore failing tests
- Leave tests in a broken state "to fix later"

### Common Test Failures and Fixes

#### Uninitialized Dependencies
**Problem**: Tests fail because dependencies (like dotenv, databases, etc.) aren't initialized.

**Solution**: Use `setUpAll()` to initialize dependencies before tests run:
```dart
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Initialize dependencies
    dotenv.testLoad(fileInput: 'TEST_KEY=value');
  });

  test('my test', () {
    // Test code
  });
}
```

#### Widget Tests Requiring Context
**Problem**: Widget tests fail because they need proper Flutter binding.

**Solution**: Ensure `TestWidgetsFlutterBinding.ensureInitialized()` is called.

#### Database Tests
**Problem**: Tests fail because database isn't in expected state.

**Solution**: Use `setUp()` and `tearDown()` to reset database state:
```dart
setUp(() async {
  await database.clearAll();
});

tearDown(() async {
  await database.close();
});
```

## Test Coverage Goals

As specified in CLAUDE.md:
- **Domain models**: 100% coverage (pure logic, critical)
- **Mappers**: 100% coverage (data consistency is critical)
- **Repositories**: 90%+ coverage
- **ViewModels**: 80%+ coverage
- **UI**: 50%+ coverage (smoke tests)

## Current Test Status

All tests passing ✅ (33/33 tests)

### Test Breakdown
- Location model: 11 tests ✅
- PinStatus enum: 5 tests ✅
- RestrictionTag enum: 6 tests ✅
- Pin model: 11 tests ✅
- Widget tests: 1 test ✅

## Running Tests

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/domain/models/pin_test.dart

# Run tests with coverage
flutter test --coverage

# Watch mode (re-run on changes)
flutter test --watch
```

## Test Structure

```
test/
├── domain/
│   └── models/
│       ├── location_test.dart
│       ├── pin_status_test.dart
│       ├── pin_test.dart
│       └── restriction_tag_test.dart
└── widget_test.dart
```

## Next Steps

As we progress through iterations:
1. Add repository tests (with mocks/fakes)
2. Add ViewModel tests
3. Add integration tests for sync logic
4. Add widget tests for dialogs and screens
5. Maintain 100% pass rate at all times

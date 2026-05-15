# Forgot Password + Auth-Screen Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship self-service email-based password reset, and split the combined login/signup screen into two dedicated screens (with a confirm-password field on signup).

**Architecture:** Reuse the existing Supabase PKCE deep-link infrastructure — the recovery flow piggybacks on the same `verifyOTP(type, tokenHash)` path the email-confirmation flow already uses. A new one-shot flag on `AuthViewModel` distinguishes a recovery callback from a normal sign-in so `_AppRoot` can route the user into a `ResetPasswordScreen`. The login/signup split is a pure-UI refactor that produces a new `SignUpScreen` and strips signup-only widgets from `LoginScreen`.

**Tech Stack:** Flutter 3.41.7 / Dart 3.11.5, `supabase_flutter ^2.3.0`, `app_links ^7.0.0`, `provider`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-05-02-forgot-password-design.md`

---

## File Structure

### New files

| Path | Responsibility |
|------|----------------|
| `lib/presentation/screens/forgot_password_screen.dart` | Email entry → success state, sends reset link |
| `lib/presentation/screens/reset_password_screen.dart` | New-password + confirm fields, called via deep-link recovery callback |
| `lib/presentation/screens/sign_up_screen.dart` | Signup-only screen with confirm-password + EULA checkbox |
| `lib/presentation/utils/terms_url.dart` | Tiny shared helper for opening the Terms URL externally |
| `test/presentation/screens/forgot_password_screen_test.dart` | Widget tests for forgot-password screen |
| `test/presentation/screens/reset_password_screen_test.dart` | Widget tests for reset-password screen |
| `test/presentation/screens/sign_up_screen_test.dart` | Widget tests for signup screen |
| `test/presentation/viewmodels/auth_viewmodel_password_reset_test.dart` | Unit tests for new VM methods + recovery flag + new error mappings |

### Modified files

| Path | Change |
|------|--------|
| `lib/domain/repositories/auth_repository.dart` | Add `sendPasswordResetEmail`, `updatePassword`, `passwordRecoveryEvents` |
| `lib/data/repositories/supabase_auth_repository.dart` | Implement the three new methods + subscribe to `onAuthStateChange` and emit on `AuthChangeEvent.passwordRecovery` |
| `lib/presentation/viewmodels/auth_viewmodel.dart` | Add `sendPasswordReset`, `updatePassword`, `isInPasswordRecovery`, `clearRecoveryState`; subscribe to recovery stream; extend `_formatAuthError` |
| `lib/presentation/screens/login_screen.dart` | Strip signup logic + EULA checkbox; relax password validator; add "Forgot password?" + "Sign up" links |
| `lib/presentation/widgets/sign_in_prompt_sheet.dart` | Make "Create Account" land on `SignUpScreen` (pushed on top of `LoginScreen`) |
| `lib/main.dart` | `_AppRoot` watches `isInPasswordRecovery` and pushes `ResetPasswordScreen`; surfaces deep-link errors as snackbar; uses shared `openTermsUrl` |
| `test/fakes/fake_auth_repository.dart` | Implement the three new interface methods + recovery stream + failure toggles |
| `test/presentation/screens/login_screen_test.dart` | Update assertions for the slimmed-down LoginScreen + new footer links |
| `test/presentation/widgets/sign_in_prompt_sheet_test.dart` | Update push-count assertion for the new "Create Account" → SignUpScreen path |
| `docs/auth/callback/index.html` | Branch on `?type` so recovery flows render "Reset Your Password" copy |

---

## Task 1: Extend `AuthRepository` interface

**Files:**
- Modify: `lib/domain/repositories/auth_repository.dart`

Domain interface change. No test — abstract method declarations have no behavior to test directly; downstream tests against `FakeAuthRepository` and `AuthViewModel` cover the contract.

- [ ] **Step 1: Add the three new method declarations**

Append to `lib/domain/repositories/auth_repository.dart`, immediately before the closing `}` of the `AuthRepository` class:

```dart
  /// Sends a password reset email to [email]. Always succeeds-looking from
  /// the caller's perspective even when the email is unregistered (Supabase
  /// prevents enumeration). Throws on network/transport errors only.
  Future<void> sendPasswordResetEmail(String email);

  /// Updates the password for the user in the current recovery session.
  /// Must only be called while a recovery session is active.
  /// Throws AuthException on weak password, expired session, etc.
  Future<void> updatePassword(String newPassword);

  /// Stream that emits whenever the underlying auth provider signals that
  /// the session was created via a password-recovery flow. The viewmodel
  /// uses this to flag the session as recovery-mode and route to the reset
  /// screen.
  Stream<void> passwordRecoveryEvents();
```

- [ ] **Step 2: Verify compile errors surface in dependents (expected — they aren't fixed yet)**

Run: `flutter analyze`
Expected: errors in `supabase_auth_repository.dart` and `fake_auth_repository.dart` complaining the class is missing concrete implementations of `sendPasswordResetEmail`, `updatePassword`, `passwordRecoveryEvents`. This confirms the interface change took effect everywhere.

- [ ] **Step 3: Commit (the failing-analysis state — fixed in Tasks 2 and 3)**

```bash
git add lib/domain/repositories/auth_repository.dart
git commit -m "feat(auth): add reset-password methods + recovery event stream to AuthRepository"
```

---

## Task 2: Extend `FakeAuthRepository` to satisfy the new interface

**Files:**
- Modify: `test/fakes/fake_auth_repository.dart`

The fake powers all ViewModel/widget tests. Add the new methods with configurable failure toggles and a broadcast controller for the recovery stream.

- [ ] **Step 1: Add fields and methods to the fake**

Replace the entire body of `test/fakes/fake_auth_repository.dart` with:

```dart
import 'dart:async';
import 'package:ccwmap/domain/models/user.dart';
import 'package:ccwmap/domain/repositories/auth_repository.dart';

/// Fake AuthRepository for testing
/// Can be configured to simulate different auth states
class FakeAuthRepository implements AuthRepository {
  User? _currentUser;
  final StreamController<User?> _authStateController =
      StreamController<User?>.broadcast();
  final StreamController<void> _passwordRecoveryController =
      StreamController<void>.broadcast();

  /// Set the current user (simulates sign in)
  void setCurrentUser(User? user) {
    _currentUser = user;
    _authStateController.add(user);
  }

  /// Emit a synthetic password-recovery event (simulates the callback that
  /// fires when verifyOTP completes for a recovery deep link).
  void emitPasswordRecovery() {
    _passwordRecoveryController.add(null);
  }

  @override
  Future<User?> getCurrentUser() async {
    return _currentUser;
  }

  @override
  Stream<User?> authStateChanges() {
    return _authStateController.stream;
  }

  @override
  Future<void> signUpWithEmail(String email, String password) async {
    // Simulate signup
    final user = User(id: 'test-id', email: email);
    setCurrentUser(user);
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    // Simulate sign in
    final user = User(id: 'test-id', email: email);
    setCurrentUser(user);
  }

  @override
  Future<void> signOut() async {
    setCurrentUser(null);
  }

  @override
  Future<void> handleDeepLink(Uri uri) async {
    // Simulate deep link handling
    final user = User(id: 'test-id', email: 'deeplink@test.com');
    setCurrentUser(user);
  }

  bool deleteShouldThrow = false;
  int deleteCallCount = 0;

  @override
  Future<void> deleteAccount() async {
    deleteCallCount++;
    if (deleteShouldThrow) {
      throw Exception('simulated delete failure');
    }
    setCurrentUser(null);
  }

  // --- Password reset ---

  bool sendResetShouldThrow = false;
  Object sendResetThrownError = Exception('simulated reset send failure');
  int sendResetCallCount = 0;
  String? sendResetLastEmail;

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    sendResetCallCount++;
    sendResetLastEmail = email;
    if (sendResetShouldThrow) {
      throw sendResetThrownError;
    }
  }

  bool updatePasswordShouldThrow = false;
  Object updatePasswordThrownError =
      Exception('simulated update-password failure');
  int updatePasswordCallCount = 0;
  String? updatePasswordLastValue;

  @override
  Future<void> updatePassword(String newPassword) async {
    updatePasswordCallCount++;
    updatePasswordLastValue = newPassword;
    if (updatePasswordShouldThrow) {
      throw updatePasswordThrownError;
    }
  }

  @override
  Stream<void> passwordRecoveryEvents() => _passwordRecoveryController.stream;

  /// Clean up resources
  void dispose() {
    _authStateController.close();
    _passwordRecoveryController.close();
  }
}
```

- [ ] **Step 2: Run analyze — should now be clean for the fake**

Run: `flutter analyze test/fakes/fake_auth_repository.dart`
Expected: No issues found in this file.

- [ ] **Step 3: Run existing auth tests — they must still pass unchanged**

Run: `flutter test test/presentation/viewmodels/auth_viewmodel_delete_test.dart test/presentation/screens/login_screen_test.dart`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add test/fakes/fake_auth_repository.dart
git commit -m "test(auth): extend FakeAuthRepository for reset-password methods + recovery stream"
```

---

## Task 3: Implement new methods on `SupabaseAuthRepository`

**Files:**
- Modify: `lib/data/repositories/supabase_auth_repository.dart`

The Supabase client is not unit-tested directly in this project — the interface contract is exercised through the fake, and manual testing covers the integration. We just need a clean, correct implementation.

- [ ] **Step 1: Add a recovery-event broadcast controller and subscription**

In `lib/data/repositories/supabase_auth_repository.dart`, change the class declaration block to add a private `StreamController<void>` and a constructor body that subscribes to `onAuthStateChange`:

```dart
class SupabaseAuthRepository implements AuthRepository {
  final supabase.SupabaseClient _supabase;
  final SyncManager? _syncManager;
  final FlutterSecureStorage _secureStorage;
  final StreamController<void> _passwordRecoveryController =
      StreamController<void>.broadcast();

  SupabaseAuthRepository(
    this._supabase, {
    SyncManager? syncManager,
    FlutterSecureStorage? secureStorage,
  })  : _syncManager = syncManager,
        _secureStorage = secureStorage ?? const FlutterSecureStorage() {
    // Surface password-recovery events from the underlying Supabase auth
    // stream as a separate stream consumers can listen to. This is the
    // signal that distinguishes a recovery callback from a normal sign-in.
    _supabase.auth.onAuthStateChange.listen((state) {
      if (state.event == supabase.AuthChangeEvent.passwordRecovery) {
        _passwordRecoveryController.add(null);
      }
    });
  }
```

Add the `dart:async` import at the top of the file:

```dart
import 'dart:async';
```

- [ ] **Step 2: Add the three new method implementations**

Insert before the existing `@override Future<void> deleteAccount()` declaration:

```dart
  @override
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: 'https://camiloh12.github.io/ccwmap/auth/callback',
      );
    } on supabase.AuthException {
      rethrow;
    } catch (e) {
      throw supabase.AuthException('Send reset email failed: $e');
    }
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    try {
      await _supabase.auth.updateUser(
        supabase.UserAttributes(password: newPassword),
      );
    } on supabase.AuthException {
      rethrow;
    } catch (e) {
      throw supabase.AuthException('Update password failed: $e');
    }
  }

  @override
  Stream<void> passwordRecoveryEvents() => _passwordRecoveryController.stream;
```

- [ ] **Step 3: Run analyze and tests**

Run: `flutter analyze` then `flutter test`
Expected: No analyzer issues. All 109 existing tests still pass.

- [ ] **Step 4: Commit**

```bash
git add lib/data/repositories/supabase_auth_repository.dart
git commit -m "feat(auth): implement reset-password + recovery event stream on SupabaseAuthRepository"
```

---

## Task 4: Extend `AuthViewModel` (TDD)

**Files:**
- Modify: `lib/presentation/viewmodels/auth_viewmodel.dart`
- Test: `test/presentation/viewmodels/auth_viewmodel_password_reset_test.dart` (new)

- [ ] **Step 1: Write the failing test file**

Create `test/presentation/viewmodels/auth_viewmodel_password_reset_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../fakes/fake_auth_repository.dart';

void main() {
  group('AuthViewModel.sendPasswordReset', () {
    late FakeAuthRepository fake;
    late AuthViewModel vm;

    setUp(() {
      fake = FakeAuthRepository();
      vm = AuthViewModel(fake);
    });

    tearDown(() {
      vm.dispose();
      fake.dispose();
    });

    test('trims email before delegating', () async {
      await vm.sendPasswordReset('  user@example.com  ');
      expect(fake.sendResetCallCount, 1);
      expect(fake.sendResetLastEmail, 'user@example.com');
      expect(vm.error, isNull);
    });

    test('toggles isLoading around the call', () async {
      expect(vm.isLoading, isFalse);
      final future = vm.sendPasswordReset('u@example.com');
      expect(vm.isLoading, isTrue);
      await future;
      expect(vm.isLoading, isFalse);
    });

    test('rate-limit error formats to friendly copy', () async {
      fake.sendResetShouldThrow = true;
      fake.sendResetThrownError = const supabase.AuthException(
        'over_email_send_rate_limit: too many requests',
      );
      await vm.sendPasswordReset('u@example.com');
      expect(vm.error, contains('Too many'));
    });
  });

  group('AuthViewModel.updatePassword', () {
    late FakeAuthRepository fake;
    late AuthViewModel vm;

    setUp(() async {
      fake = FakeAuthRepository();
      vm = AuthViewModel(fake);
      await vm.initialize();
      // Put the VM into recovery mode by emitting the synthetic event.
      fake.emitPasswordRecovery();
      // Allow the broadcast stream to deliver.
      await Future<void>.delayed(Duration.zero);
    });

    tearDown(() {
      vm.dispose();
      fake.dispose();
    });

    test('precondition: recovery flag is set after the synthetic event',
        () {
      expect(vm.isInPasswordRecovery, isTrue);
    });

    test('success clears the recovery flag', () async {
      await vm.updatePassword('newpass123');
      expect(fake.updatePasswordCallCount, 1);
      expect(fake.updatePasswordLastValue, 'newpass123');
      expect(vm.isInPasswordRecovery, isFalse);
      expect(vm.error, isNull);
    });

    test('failure: surfaces error and leaves the recovery flag set',
        () async {
      fake.updatePasswordShouldThrow = true;
      fake.updatePasswordThrownError = const supabase.AuthException(
        'New password should be different from the old password.',
      );
      await vm.updatePassword('newpass123');
      expect(vm.error, contains('differ'));
      expect(vm.isInPasswordRecovery, isTrue);
    });

    test('expired-link error formats to friendly copy', () async {
      fake.updatePasswordShouldThrow = true;
      fake.updatePasswordThrownError = const supabase.AuthException(
        'Token has expired or is invalid (otp_expired).',
      );
      await vm.updatePassword('newpass123');
      expect(vm.error, contains('expired'));
    });
  });

  group('AuthViewModel password-recovery flag plumbing', () {
    test('emitPasswordRecovery sets the flag and notifies listeners',
        () async {
      final fake = FakeAuthRepository();
      final vm = AuthViewModel(fake);
      await vm.initialize();
      var notified = 0;
      vm.addListener(() => notified++);

      expect(vm.isInPasswordRecovery, isFalse);
      fake.emitPasswordRecovery();
      await Future<void>.delayed(Duration.zero);

      expect(vm.isInPasswordRecovery, isTrue);
      expect(notified, greaterThanOrEqualTo(1));

      vm.dispose();
      fake.dispose();
    });

    test('clearRecoveryState resets the flag without signing out',
        () async {
      final fake = FakeAuthRepository();
      final vm = AuthViewModel(fake);
      await vm.initialize();
      fake.emitPasswordRecovery();
      await Future<void>.delayed(Duration.zero);
      expect(vm.isInPasswordRecovery, isTrue);

      vm.clearRecoveryState();
      expect(vm.isInPasswordRecovery, isFalse);
      // currentUser remains untouched — clearRecoveryState does not log out.

      vm.dispose();
      fake.dispose();
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/presentation/viewmodels/auth_viewmodel_password_reset_test.dart`
Expected: Compile errors — `sendPasswordReset`, `updatePassword`, `isInPasswordRecovery`, `clearRecoveryState` are not defined on `AuthViewModel`.

- [ ] **Step 3: Implement the new methods on `AuthViewModel`**

In `lib/presentation/viewmodels/auth_viewmodel.dart`:

a) Add a second subscription field at the top of the class:

```dart
StreamSubscription<void>? _recoverySubscription;
```

b) Add the recovery flag with getter just below `_error`:

```dart
bool _isInPasswordRecovery = false;
```

```dart
bool get isInPasswordRecovery => _isInPasswordRecovery;
```

c) Subscribe to the recovery stream inside `initialize()` — append after the existing `_authSubscription = ...` block but before the trailing `debugPrint` call:

```dart
    // Listen for password-recovery events. When fired, the current session
    // is recovery-mode and the UI must route the user to a "set new password"
    // screen instead of the regular post-login state.
    _recoverySubscription = _repository.passwordRecoveryEvents().listen((_) {
      debugPrint('AuthViewModel: passwordRecovery event received');
      _isInPasswordRecovery = true;
      notifyListeners();
    });
```

d) Add the three new methods immediately above the `clearError()` method:

```dart
  /// Sends a password-reset email. Always presents as success to the caller
  /// (the repository hides email-enumeration; we surface only transport
  /// errors).
  Future<void> sendPasswordReset(String email) async {
    _setLoading(true);
    _clearError();

    try {
      debugPrint('AuthViewModel: Sending password reset for: $email');
      await _repository.sendPasswordResetEmail(email.trim());
      debugPrint('AuthViewModel: Password reset email sent');
    } on supabase.AuthException catch (e) {
      debugPrint('AuthViewModel: Password reset failed: ${e.message}');
      _error = _formatAuthError(e);
      notifyListeners();
    } catch (e) {
      debugPrint('AuthViewModel: Password reset error: $e');
      _error = 'Could not send reset link. Please try again.';
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  /// Updates the current user's password. Only valid during a recovery
  /// session. Clears the recovery flag on success.
  Future<void> updatePassword(String newPassword) async {
    _setLoading(true);
    _clearError();

    try {
      debugPrint('AuthViewModel: Updating password');
      await _repository.updatePassword(newPassword);
      debugPrint('AuthViewModel: Password updated');
      _isInPasswordRecovery = false;
      notifyListeners();
    } on supabase.AuthException catch (e) {
      debugPrint('AuthViewModel: Update password failed: ${e.message}');
      _error = _formatAuthError(e);
      notifyListeners();
    } catch (e) {
      debugPrint('AuthViewModel: Update password error: $e');
      _error = 'Could not update password. Please try again.';
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  /// Resets the recovery flag without affecting the session. Used when the
  /// user cancels the reset flow (the caller is responsible for signing the
  /// user out separately if appropriate).
  void clearRecoveryState() {
    if (!_isInPasswordRecovery) return;
    _isInPasswordRecovery = false;
    notifyListeners();
  }
```

e) Extend `_formatAuthError` to handle the new cases. Replace the existing method body with:

```dart
  String _formatAuthError(supabase.AuthException e) {
    final message = e.message.toLowerCase();

    if (message.contains('banned') || message.contains('suspended')) {
      return 'This account has been suspended for violating the community '
          'guidelines. For appeals, email camilo@kyberneticlabs.com.';
    }
    if (message.contains('rate limit') ||
        message.contains('over_email_send_rate_limit')) {
      return 'Too many reset requests. Please wait a few minutes and try '
          'again.';
    }
    if (message.contains('token has expired') ||
        message.contains('otp_expired')) {
      return 'This reset link has expired. Request a new one.';
    }
    if (message.contains('different from the old password') ||
        message.contains('same password')) {
      return 'New password must differ from your current one.';
    }
    if (message.contains('invalid login credentials')) {
      return 'Invalid email or password. Please try again.';
    } else if (message.contains('user already registered')) {
      return 'This email is already registered. Please sign in instead.';
    } else if (message.contains('email not confirmed')) {
      return 'Please confirm your email before signing in.';
    } else if (message.contains('invalid email')) {
      return 'Please enter a valid email address.';
    } else if (message.contains('password')) {
      return 'Password must be at least 6 characters.';
    } else {
      return e.message;
    }
  }
```

f) Update `dispose()` to cancel the recovery subscription:

```dart
  @override
  void dispose() {
    _authSubscription?.cancel();
    _recoverySubscription?.cancel();
    super.dispose();
  }
```

- [ ] **Step 4: Run the new tests — they must pass**

Run: `flutter test test/presentation/viewmodels/auth_viewmodel_password_reset_test.dart`
Expected: All 8 tests pass.

- [ ] **Step 5: Run the full suite — no regressions**

Run: `flutter test`
Expected: All tests pass (109 existing + 8 new = 117).

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/viewmodels/auth_viewmodel.dart test/presentation/viewmodels/auth_viewmodel_password_reset_test.dart
git commit -m "feat(auth): add sendPasswordReset/updatePassword + recovery flag to AuthViewModel"
```

---

## Task 5: Extract shared `openTermsUrl` helper

**Files:**
- Create: `lib/presentation/utils/terms_url.dart`
- Modify: `lib/main.dart` (replace `_AppRoot._openTermsUrl` with the shared helper)
- Modify: `lib/presentation/screens/login_screen.dart` (delete the now-orphaned `_openTermsUrl` — `LoginScreen` will lose its only EULA caller in Task 9, but we drop the helper now to keep the change small)

This is a tiny non-behavior-changing refactor done up-front so later tasks can use it.

- [ ] **Step 1: Create the helper**

Create `lib/presentation/utils/terms_url.dart`:

```dart
import 'package:url_launcher/url_launcher.dart';

/// Public Terms-of-Use page hosted on GitHub Pages.
const termsUrl = 'https://camiloh12.github.io/ccwmap/terms';

/// Opens the Terms-of-Use page in the system browser. No-ops if the
/// platform refuses to launch the URL.
Future<void> openTermsUrl() async {
  final uri = Uri.parse(termsUrl);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
```

- [ ] **Step 2: Replace `_AppRoot._openTermsUrl` in `main.dart`**

In `lib/main.dart`:

a) Add the import near the top:

```dart
import 'package:ccwmap/presentation/utils/terms_url.dart';
```

b) Delete the `_openTermsUrl` method body inside `_AppRootState`:

Delete this block (it currently lives between `_maybeShowRetroactiveEula` and `dispose`):

```dart
  Future<void> _openTermsUrl() async {
    final uri = Uri.parse('https://camiloh12.github.io/ccwmap/terms');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
```

c) Replace the two call sites `onReadTerms: _openTermsUrl,` with `onReadTerms: openTermsUrl,` (both inside `_maybeShowPassiveEula` and `_maybeShowRetroactiveEula`).

d) Remove the now-unused `import 'package:url_launcher/url_launcher.dart';` from `main.dart` if it has no other consumers. Run `flutter analyze` afterwards — if `url_launcher` is still referenced elsewhere in the file, leave the import in place.

- [ ] **Step 3: Update `LoginScreen` to use the shared helper (interim — full strip happens in Task 9)**

In `lib/presentation/screens/login_screen.dart`:

a) Add the import:

```dart
import 'package:ccwmap/presentation/utils/terms_url.dart';
```

b) Delete the `_openTermsUrl` method on `_LoginScreenState`:

```dart
  Future<void> _openTermsUrl() async {
    final uri = Uri.parse('https://camiloh12.github.io/ccwmap/terms');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
```

c) Update the only call site inside the EULA `Wrap`:

```dart
                                  TextButton(
                                    onPressed: isLoading ? null : openTermsUrl,
```

d) Remove the `import 'package:url_launcher/url_launcher.dart';` line from `login_screen.dart` if `url_launcher` has no other consumers in the file (it should not).

- [ ] **Step 4: Run analyze + full test suite**

Run: `flutter analyze && flutter test`
Expected: No analyzer issues. All 117 tests still pass.

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/utils/terms_url.dart lib/main.dart lib/presentation/screens/login_screen.dart
git commit -m "refactor: extract openTermsUrl into shared util"
```

---

## Task 6: Build `ForgotPasswordScreen` (TDD)

**Files:**
- Create: `lib/presentation/screens/forgot_password_screen.dart`
- Test: `test/presentation/screens/forgot_password_screen_test.dart` (new)

- [ ] **Step 1: Write the failing widget test**

Create `test/presentation/screens/forgot_password_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ccwmap/presentation/screens/forgot_password_screen.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';

import '../../fakes/fake_auth_repository.dart';

Widget _hostedScreen(AuthViewModel vm) {
  return ChangeNotifierProvider<AuthViewModel>.value(
    value: vm,
    child: const MaterialApp(home: ForgotPasswordScreen()),
  );
}

void main() {
  group('ForgotPasswordScreen', () {
    testWidgets('empty email blocks submit with validation error',
        (tester) async {
      final fake = FakeAuthRepository();
      final vm = AuthViewModel(fake);
      await tester.pumpWidget(_hostedScreen(vm));

      await tester.tap(find.text('Send reset link'));
      await tester.pump();

      expect(find.text('Email is required'), findsOneWidget);
      expect(fake.sendResetCallCount, 0);

      vm.dispose();
      fake.dispose();
    });

    testWidgets('valid email + submit calls VM and shows success state',
        (tester) async {
      final fake = FakeAuthRepository();
      final vm = AuthViewModel(fake);
      await tester.pumpWidget(_hostedScreen(vm));

      await tester.enterText(find.byType(TextFormField), 'user@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();

      expect(fake.sendResetCallCount, 1);
      expect(fake.sendResetLastEmail, 'user@example.com');
      expect(find.textContaining('user@example.com'), findsOneWidget);
      expect(find.text('Back to sign in'), findsOneWidget);
      expect(find.text('Send reset link'), findsNothing);

      vm.dispose();
      fake.dispose();
    });

    testWidgets('error from VM renders the red banner', (tester) async {
      final fake = FakeAuthRepository();
      fake.sendResetShouldThrow = true;
      final vm = AuthViewModel(fake);
      await tester.pumpWidget(_hostedScreen(vm));

      await tester.enterText(find.byType(TextFormField), 'user@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();

      // Generic catch-all copy from sendPasswordReset's `catch (e)` branch.
      expect(find.textContaining('Could not send reset link'), findsOneWidget);
      // Stays on form, does NOT show success state.
      expect(find.text('Send reset link'), findsOneWidget);

      vm.dispose();
      fake.dispose();
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/presentation/screens/forgot_password_screen_test.dart`
Expected: Compile error — `forgot_password_screen.dart` does not exist.

- [ ] **Step 3: Implement `ForgotPasswordScreen`**

Create `lib/presentation/screens/forgot_password_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';

/// Screen for requesting a password-reset email.
///
/// Two states:
/// 1. Form: email field + "Send reset link" button.
/// 2. Success: confirmation copy + "Back to sign in" button (pops route).
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email is required';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    final vm = context.read<AuthViewModel>();
    vm.clearError();
    await vm.sendPasswordReset(_emailController.text);
    if (!mounted) return;
    if (vm.error == null) {
      setState(() => _sent = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthViewModel>(
      builder: (context, vm, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Reset Password')),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: _sent ? _buildSuccess(context) : _buildForm(context, vm),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildForm(BuildContext context, AuthViewModel vm) {
    final isLoading = vm.isLoading;
    final errorMessage = vm.error;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Enter the email associated with your account and we\'ll send you '
            'a link to reset your password.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            enabled: !isLoading,
            validator: _validateEmail,
            decoration: const InputDecoration(
              labelText: 'Email',
              hintText: 'you@example.com',
              prefixIcon: Icon(Icons.email),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[300]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.error, color: Colors.red[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      errorMessage,
                      style: TextStyle(color: Colors.red[700]),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          ElevatedButton(
            onPressed: isLoading ? null : _handleSubmit,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Send reset link'),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    final email = _emailController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.mark_email_read,
            size: 64, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'Check your email',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'If an account exists for $email, we\'ve sent a reset link. Check '
          'your inbox and spam folder.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/presentation/screens/forgot_password_screen_test.dart`
Expected: All 3 tests pass.

- [ ] **Step 5: Run full suite — no regressions**

Run: `flutter test`
Expected: All tests pass (now ~120).

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/screens/forgot_password_screen.dart test/presentation/screens/forgot_password_screen_test.dart
git commit -m "feat(auth): add ForgotPasswordScreen"
```

---

## Task 7: Build `ResetPasswordScreen` (TDD)

**Files:**
- Create: `lib/presentation/screens/reset_password_screen.dart`
- Test: `test/presentation/screens/reset_password_screen_test.dart` (new)

- [ ] **Step 1: Write the failing widget test**

Create `test/presentation/screens/reset_password_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ccwmap/presentation/screens/reset_password_screen.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';

import '../../fakes/fake_auth_repository.dart';

Widget _hosted(AuthViewModel vm) {
  return ChangeNotifierProvider<AuthViewModel>.value(
    value: vm,
    child: const MaterialApp(home: ResetPasswordScreen()),
  );
}

Future<(FakeAuthRepository, AuthViewModel)> _setupRecoveryVm() async {
  final fake = FakeAuthRepository();
  final vm = AuthViewModel(fake);
  await vm.initialize();
  fake.emitPasswordRecovery();
  await Future<void>.delayed(Duration.zero);
  return (fake, vm);
}

void main() {
  group('ResetPasswordScreen', () {
    testWidgets('mismatched passwords block submit with validation error',
        (tester) async {
      final (fake, vm) = await _setupRecoveryVm();
      await tester.pumpWidget(_hosted(vm));

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'newpass123');
      await tester.enterText(fields.at(1), 'different');
      await tester.tap(find.text('Update password'));
      await tester.pump();

      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(fake.updatePasswordCallCount, 0);

      vm.dispose();
      fake.dispose();
    });

    testWidgets('matching passwords + submit calls VM', (tester) async {
      final (fake, vm) = await _setupRecoveryVm();
      await tester.pumpWidget(_hosted(vm));

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'newpass123');
      await tester.enterText(fields.at(1), 'newpass123');
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();

      expect(fake.updatePasswordCallCount, 1);
      expect(fake.updatePasswordLastValue, 'newpass123');
      expect(vm.isInPasswordRecovery, isFalse);

      vm.dispose();
      fake.dispose();
    });

    testWidgets('cancel signs out and clears recovery state', (tester) async {
      final (fake, vm) = await _setupRecoveryVm();
      // Make the VM look like a logged-in recovery session.
      fake.setCurrentUser(User(id: 'u1', email: 'u1@example.com'));
      await tester.pumpWidget(_hosted(vm));

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(vm.isAuthenticated, isFalse); // signOut was called
      expect(vm.isInPasswordRecovery, isFalse);

      vm.dispose();
      fake.dispose();
    });
  });
}
```

The test imports `User` — add this to the import block at the top of the file:

```dart
import 'package:ccwmap/domain/models/user.dart';
```

- [ ] **Step 2: Run the test — verify it fails**

Run: `flutter test test/presentation/screens/reset_password_screen_test.dart`
Expected: Compile error — `reset_password_screen.dart` does not exist.

- [ ] **Step 3: Implement `ResetPasswordScreen`**

Create `lib/presentation/screens/reset_password_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';

/// Screen shown when the user lands back in the app via a password-recovery
/// deep link. Two password fields (new + confirm) and an Update button.
/// OS back/swipe is blocked — only Cancel (sign-out + clear) or successful
/// update can dismiss this screen.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  String? _validateConfirm(String? value) {
    if (value == null || value.isEmpty) return 'Please confirm your password';
    if (value != _passwordController.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    final vm = context.read<AuthViewModel>();
    vm.clearError();
    await vm.updatePassword(_passwordController.text);
    if (!mounted) return;
    if (vm.error == null) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleCancel() async {
    final vm = context.read<AuthViewModel>();
    await vm.signOut();
    vm.clearRecoveryState();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthViewModel>(
      builder: (context, vm, _) {
        final isLoading = vm.isLoading;
        final errorMessage = vm.error;
        return PopScope(
          canPop: false,
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              title: const Text('Set New Password'),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : _handleCancel,
                  child: const Text('Cancel'),
                ),
              ],
            ),
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Choose a new password for your CCW Map account.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          enabled: !isLoading,
                          validator: _validatePassword,
                          decoration: InputDecoration(
                            labelText: 'New password',
                            hintText: 'At least 6 characters',
                            prefixIcon: const Icon(Icons.lock),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () => setState(() {
                                _obscurePassword = !_obscurePassword;
                              }),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirmController,
                          obscureText: _obscureConfirm,
                          enabled: !isLoading,
                          validator: _validateConfirm,
                          decoration: InputDecoration(
                            labelText: 'Confirm new password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirm
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () => setState(() {
                                _obscureConfirm = !_obscureConfirm;
                              }),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red[300]!),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error, color: Colors.red[700]),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    errorMessage,
                                    style: TextStyle(color: Colors.red[700]),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        ElevatedButton(
                          onPressed: isLoading ? null : _handleSubmit,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Text('Update password'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run the tests — verify they pass**

Run: `flutter test test/presentation/screens/reset_password_screen_test.dart`
Expected: All 3 tests pass.

- [ ] **Step 5: Run full suite — no regressions**

Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/screens/reset_password_screen.dart test/presentation/screens/reset_password_screen_test.dart
git commit -m "feat(auth): add ResetPasswordScreen"
```

---

## Task 8: Build `SignUpScreen` (TDD)

**Files:**
- Create: `lib/presentation/screens/sign_up_screen.dart`
- Test: `test/presentation/screens/sign_up_screen_test.dart` (new)

- [ ] **Step 1: Write the failing widget test**

Create `test/presentation/screens/sign_up_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ccwmap/domain/models/user.dart';
import 'package:ccwmap/domain/repositories/agreements_repository.dart';
import 'package:ccwmap/presentation/screens/sign_up_screen.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';

import '../../fakes/fake_auth_repository.dart';

class _FakeAgreementsRepository implements AgreementsRepository {
  int recordCount = 0;

  @override
  Future<bool> hasAcceptedAgreement({
    required String userId,
    required int version,
  }) async => true;

  @override
  Future<void> recordAgreementAcceptance({
    required String userId,
    required int version,
  }) async {
    recordCount++;
  }
}

Widget _hosted(AuthViewModel vm, AgreementsRepository agreements) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthViewModel>.value(value: vm),
      Provider<AgreementsRepository>.value(value: agreements),
    ],
    child: const MaterialApp(home: SignUpScreen()),
  );
}

void main() {
  group('SignUpScreen', () {
    testWidgets('Create Account is disabled until EULA is checked',
        (tester) async {
      final fake = FakeAuthRepository();
      final vm = AuthViewModel(fake);
      final agreements = _FakeAgreementsRepository();
      await tester.pumpWidget(_hosted(vm, agreements));

      final button = find.widgetWithText(ElevatedButton, 'Create Account');
      expect(tester.widget<ElevatedButton>(button).onPressed, isNull);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);

      vm.dispose();
      fake.dispose();
    });

    testWidgets('mismatched passwords block submit', (tester) async {
      final fake = FakeAuthRepository();
      final vm = AuthViewModel(fake);
      final agreements = _FakeAgreementsRepository();
      await tester.pumpWidget(_hosted(vm, agreements));

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'user@example.com');
      await tester.enterText(fields.at(1), 'password1');
      await tester.enterText(fields.at(2), 'password2');
      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
      await tester.pump();

      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(agreements.recordCount, 0);

      vm.dispose();
      fake.dispose();
    });

    testWidgets('valid form submits, records agreement, shows snackbar',
        (tester) async {
      final fake = FakeAuthRepository();
      final vm = AuthViewModel(fake);
      final agreements = _FakeAgreementsRepository();
      // Pre-set the user so post-signup `vm.currentUser` is non-null when
      // SignUpScreen reads it (the fake's signUp also sets it, but the
      // notify ordering means the read inside the screen needs the user
      // available immediately).
      fake.setCurrentUser(User(id: 'u1', email: 'user@example.com'));
      await tester.pumpWidget(_hosted(vm, agreements));

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'user@example.com');
      await tester.enterText(fields.at(1), 'password1');
      await tester.enterText(fields.at(2), 'password1');
      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(agreements.recordCount, 1);
      expect(find.textContaining('Account created'), findsOneWidget);

      vm.dispose();
      fake.dispose();
    });

    testWidgets('"Sign in" footer link pops the screen', (tester) async {
      final fake = FakeAuthRepository();
      final vm = AuthViewModel(fake);
      final agreements = _FakeAgreementsRepository();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthViewModel>.value(value: vm),
            Provider<AgreementsRepository>.value(value: agreements),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SignUpScreen(),
                    ),
                  ),
                  child: const Text('open signup'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open signup'));
      await tester.pumpAndSettle();
      expect(find.byType(SignUpScreen), findsOneWidget);

      await tester.tap(find.text('Already have an account? Sign in'));
      await tester.pumpAndSettle();
      expect(find.byType(SignUpScreen), findsNothing);

      vm.dispose();
      fake.dispose();
    });
  });
}
```

The test imports `SupabaseAgreementsRepository` for type signature reference but never instantiates it — actually it doesn't need that import since the local fake `_FakeAgreementsRepository` implements the interface directly. Remove the `supabase_agreements_repository.dart` import line (it's a leftover from earlier scaffolding) before saving:

```dart
// Remove this line (do not include it in the test file):
// import 'package:ccwmap/data/repositories/supabase_agreements_repository.dart';
```

- [ ] **Step 2: Run the test — verify it fails**

Run: `flutter test test/presentation/screens/sign_up_screen_test.dart`
Expected: Compile error — `sign_up_screen.dart` does not exist.

- [ ] **Step 3: Implement `SignUpScreen`**

Create `lib/presentation/screens/sign_up_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ccwmap/domain/repositories/agreements_repository.dart';
import 'package:ccwmap/presentation/utils/terms_url.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';

/// Screen for creating a new account. Email + password + confirm-password
/// + EULA checkbox. Auto-pops when auth state flips to authenticated.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _eulaChecked = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Email is required';
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) return 'Enter a valid email address';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  String? _validateConfirm(String? value) {
    if (value == null || value.isEmpty) return 'Please confirm your password';
    if (value != _passwordController.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_eulaChecked) return;

    final vm = context.read<AuthViewModel>();
    final agreements = context.read<AgreementsRepository>();
    vm.clearError();

    await vm.signUp(
      _emailController.text.trim(),
      _passwordController.text,
    );
    if (!mounted) return;

    if (vm.error == null) {
      final user = vm.currentUser;
      if (user != null) {
        try {
          await agreements.recordAgreementAcceptance(
            userId: user.id,
            version: AgreementsRepository.currentAgreementVersion,
          );
        } catch (_) {
          // Non-fatal: retroactive modal will catch the unrecorded user.
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account created! Check your email to confirm.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthViewModel>(
      builder: (context, vm, _) {
        // Auto-pop on auth flip — same pattern LoginScreen uses.
        if (vm.isAuthenticated && vm.error == null && !vm.isLoading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
        }

        final isLoading = vm.isLoading;
        final errorMessage = vm.error;
        return Scaffold(
          appBar: AppBar(title: const Text('Create Account')),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.map,
                        size: 80,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'CCW Map',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        enabled: !isLoading,
                        validator: _validateEmail,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          hintText: 'you@example.com',
                          prefixIcon: Icon(Icons.email),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        enabled: !isLoading,
                        validator: _validatePassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          hintText: 'At least 6 characters',
                          prefixIcon: const Icon(Icons.lock),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmController,
                        obscureText: _obscureConfirm,
                        enabled: !isLoading,
                        validator: _validateConfirm,
                        decoration: InputDecoration(
                          labelText: 'Confirm password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureConfirm
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () => setState(
                                () => _obscureConfirm = !_obscureConfirm),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _eulaChecked,
                            onChanged: isLoading
                                ? null
                                : (v) => setState(
                                    () => _eulaChecked = v ?? false),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Wrap(
                                children: [
                                  const Text(
                                    'I agree to the Terms of Use and '
                                    'Community Guidelines and understand that '
                                    'objectionable content and abusive '
                                    'behavior are not tolerated. ',
                                  ),
                                  TextButton(
                                    onPressed: isLoading ? null : openTermsUrl,
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text('Read terms'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red[300]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error, color: Colors.red[700]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  errorMessage,
                                  style: TextStyle(color: Colors.red[700]),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      ElevatedButton(
                        onPressed: (isLoading || !_eulaChecked)
                            ? null
                            : _handleSignUp,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Text('Create Account'),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: isLoading
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Already have an account? Sign in'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run the tests — verify they pass**

Run: `flutter test test/presentation/screens/sign_up_screen_test.dart`
Expected: All 4 tests pass.

- [ ] **Step 5: Run full suite — no regressions**

Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/screens/sign_up_screen.dart test/presentation/screens/sign_up_screen_test.dart
git commit -m "feat(auth): add SignUpScreen with confirm-password field"
```

---

## Task 9: Slim down `LoginScreen` (TDD)

**Files:**
- Modify: `lib/presentation/screens/login_screen.dart`
- Modify: `test/presentation/screens/login_screen_test.dart`

Strip signup logic, EULA checkbox, the 6-char password validator, and the now-orphaned signup state. Add "Forgot password?" link and "Sign up" footer link. Keep the auto-pop behavior.

- [ ] **Step 1: Add the new test cases first**

Replace the entire body of `test/presentation/screens/login_screen_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ccwmap/domain/models/user.dart';
import 'package:ccwmap/presentation/screens/forgot_password_screen.dart';
import 'package:ccwmap/presentation/screens/login_screen.dart';
import 'package:ccwmap/presentation/screens/sign_up_screen.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';

import '../../fakes/fake_auth_repository.dart';

Widget _wrappedLoginEntry(AuthViewModel vm) {
  return ChangeNotifierProvider<AuthViewModel>.value(
    value: vm,
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LoginScreen(),
                ),
              ),
              child: const Text('open login'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('LoginScreen auto-pop on auth', () {
    testWidgets('pops when authStateChanges emits an authenticated user',
        (tester) async {
      final fakeRepo = FakeAuthRepository();
      final authViewModel = AuthViewModel(fakeRepo);
      await authViewModel.initialize();

      await tester.pumpWidget(_wrappedLoginEntry(authViewModel));
      await tester.tap(find.text('open login'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      fakeRepo.setCurrentUser(User(id: 'test-id', email: 'me@example.com'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsNothing);

      fakeRepo.dispose();
      authViewModel.dispose();
    });

    testWidgets('stays when authStateChanges emits null (still guest)',
        (tester) async {
      final fakeRepo = FakeAuthRepository();
      final authViewModel = AuthViewModel(fakeRepo);
      await authViewModel.initialize();

      await tester.pumpWidget(_wrappedLoginEntry(authViewModel));
      await tester.tap(find.text('open login'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      fakeRepo.setCurrentUser(null);
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      fakeRepo.dispose();
      authViewModel.dispose();
    });
  });

  group('LoginScreen post-split structure', () {
    testWidgets('does not render EULA checkbox or Create Account button',
        (tester) async {
      final fakeRepo = FakeAuthRepository();
      final authViewModel = AuthViewModel(fakeRepo);
      await authViewModel.initialize();

      await tester.pumpWidget(_wrappedLoginEntry(authViewModel));
      await tester.tap(find.text('open login'));
      await tester.pumpAndSettle();

      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('Create Account'), findsNothing);

      fakeRepo.dispose();
      authViewModel.dispose();
    });

    testWidgets('"Forgot password?" link pushes ForgotPasswordScreen',
        (tester) async {
      final fakeRepo = FakeAuthRepository();
      final authViewModel = AuthViewModel(fakeRepo);
      await authViewModel.initialize();

      await tester.pumpWidget(_wrappedLoginEntry(authViewModel));
      await tester.tap(find.text('open login'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      expect(find.byType(ForgotPasswordScreen), findsOneWidget);

      fakeRepo.dispose();
      authViewModel.dispose();
    });

    testWidgets('"Sign up" footer link pushes SignUpScreen', (tester) async {
      final fakeRepo = FakeAuthRepository();
      final authViewModel = AuthViewModel(fakeRepo);
      await authViewModel.initialize();

      // SignUpScreen only reads AgreementsRepository inside its submit
      // handler, not during build. So a build-without-submit test like
      // this one needs no agreements provider.
      await tester.pumpWidget(_wrappedLoginEntry(authViewModel));
      await tester.tap(find.text('open login'));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Don't have an account? Sign up"));
      await tester.pumpAndSettle();

      expect(find.byType(SignUpScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);

      fakeRepo.dispose();
      authViewModel.dispose();
    });

    testWidgets('sign-in form accepts a 5-character password (no client-side '
        'min-length on sign-in)', (tester) async {
      final fakeRepo = FakeAuthRepository();
      final authViewModel = AuthViewModel(fakeRepo);
      await authViewModel.initialize();

      await tester.pumpWidget(_wrappedLoginEntry(authViewModel));
      await tester.tap(find.text('open login'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'user@example.com');
      await tester.enterText(fields.at(1), 'short');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
      await tester.pumpAndSettle();

      // No client-side validator should have stopped the submit.
      expect(find.text('Password must be at least 6 characters'), findsNothing);
      // The fake's signIn auto-authenticates — LoginScreen should pop.
      expect(find.byType(LoginScreen), findsNothing);

      fakeRepo.dispose();
      authViewModel.dispose();
    });
  });
}

```

- [ ] **Step 2: Run the test — verify it fails**

Run: `flutter test test/presentation/screens/login_screen_test.dart`
Expected: Failures because the current `LoginScreen` still renders the Checkbox / "Create Account" button, and there is no "Forgot password?" / "Sign up" link to find. Also the existing 6-char password validator blocks the 5-char submit test.

- [ ] **Step 3: Rewrite `LoginScreen`**

Replace the entire body of `lib/presentation/screens/login_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ccwmap/presentation/screens/forgot_password_screen.dart';
import 'package:ccwmap/presentation/screens/sign_up_screen.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';

/// Sign-in screen. Email + password + Sign In, with side links to the
/// forgot-password flow and to signup. Auto-pops when auth state flips.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Email is required';
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) return 'Enter a valid email address';
    return null;
  }

  String? _validatePassword(String? value) {
    // Sign-in does NOT enforce a min-length client-side. Legacy accounts may
    // hold passwords that don't meet current rules; let the server reject.
    if (value == null || value.isEmpty) return 'Password is required';
    return null;
  }

  Future<void> _handleSignIn() async {
    if (!_formKey.currentState!.validate()) return;
    final vm = context.read<AuthViewModel>();
    vm.clearError();
    await vm.signIn(_emailController.text.trim(), _passwordController.text);
    // Auto-pop is handled reactively in build(); see the comment there.
  }

  void _openForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ForgotPasswordScreen()),
    );
  }

  void _openSignUp() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SignUpScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthViewModel>(
      builder: (context, authViewModel, _) {
        // Auto-pop when auth flips to true. This screen is always pushed on
        // top of MapScreen, so popping reveals the now-authenticated map.
        // Pop runs in addPostFrameCallback to stay out of the build phase;
        // guards make it idempotent across rebuilds.
        if (authViewModel.isAuthenticated &&
            authViewModel.error == null &&
            !authViewModel.isLoading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
        }

        final isLoading = authViewModel.isLoading;
        final errorMessage = authViewModel.error;

        return Scaffold(
          appBar: AppBar(title: const Text('Sign In')),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.map,
                        size: 80,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'CCW Map',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Collaborative mapping of concealed carry zones',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 48),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        enabled: !isLoading,
                        validator: _validateEmail,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          hintText: 'you@example.com',
                          prefixIcon: Icon(Icons.email),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        enabled: !isLoading,
                        validator: _validatePassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: isLoading ? null : _openForgotPassword,
                          child: const Text('Forgot password?'),
                        ),
                      ),
                      if (errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red[300]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error, color: Colors.red[700]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  errorMessage,
                                  style: TextStyle(color: Colors.red[700]),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: isLoading ? null : _handleSignIn,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Text('Sign In'),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: isLoading ? null : _openSignUp,
                        child: const Text("Don't have an account? Sign up"),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run the LoginScreen tests — verify they pass**

Run: `flutter test test/presentation/screens/login_screen_test.dart`
Expected: All 5 tests pass. The "Sign up" footer test asserts only that navigation occurred (it pops `LoginScreen`); the full SignUpScreen is exercised by `sign_up_screen_test.dart`.

- [ ] **Step 5: Run full suite — no regressions**

Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/screens/login_screen.dart test/presentation/screens/login_screen_test.dart
git commit -m "refactor(auth): split signup out of LoginScreen, add forgot/sign-up links"
```

---

## Task 10: Wire `_AppRoot` to push `ResetPasswordScreen` + surface deep-link errors

**Files:**
- Modify: `lib/main.dart`

No isolated test — this is integration glue. Manual testing covers it.

- [ ] **Step 1: Add the import for `ResetPasswordScreen`**

In `lib/main.dart`, near the other screen imports:

```dart
import 'package:ccwmap/presentation/screens/reset_password_screen.dart';
```

- [ ] **Step 2: Add a recovery-screen-pushed flag and the push logic in `_AppRootState`**

Add a new field to `_AppRootState`:

```dart
bool _resetScreenPushed = false;
```

Inside `_AppRootState.build`, after the existing `auth.currentUser` checks but before `return const MapScreen();`, add:

```dart
    // When a password-recovery deep link is processed, the AuthViewModel
    // flips isInPasswordRecovery to true. Push the ResetPasswordScreen on
    // the root navigator and block further pushes until the screen pops
    // (whether via successful update or Cancel).
    if (auth.isInPasswordRecovery && !_resetScreenPushed) {
      _resetScreenPushed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true)
            .push(MaterialPageRoute<void>(
              builder: (_) => const ResetPasswordScreen(),
            ))
            .then((_) {
          _resetScreenPushed = false;
        });
      });
    }
```

- [ ] **Step 3: Surface deep-link errors as a snackbar**

Replace the body of `_initializeDeepLinkListener` with:

```dart
  Future<void> _initializeDeepLinkListener(AuthViewModel authViewModel) async {
    final appLinks = AppLinks();

    Future<void> processAndMaybeShowError(Uri uri) async {
      await authViewModel.handleDeepLink(uri);
      if (!mounted) return;
      final err = authViewModel.error;
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 6),
          ),
        );
        authViewModel.clearError();
      }
    }

    try {
      final initialLink = await appLinks.getInitialLink();
      if (initialLink != null) {
        debugPrint('_AppRoot: Processing initial deep link: $initialLink');
        await processAndMaybeShowError(initialLink);
      }
    } catch (e) {
      debugPrint('_AppRoot: Failed to process initial deep link: $e');
      authViewModel.setError('Failed to process authentication link.');
    }

    _deepLinkSubscription = appLinks.uriLinkStream.listen(
      (Uri uri) {
        debugPrint('_AppRoot: Processing runtime deep link: $uri');
        processAndMaybeShowError(uri);
      },
      onError: (err) {
        debugPrint('_AppRoot: Deep link stream error: $err');
        authViewModel.setError('Failed to process authentication link.');
      },
    );
  }
```

- [ ] **Step 4: Run analyze + full test suite**

Run: `flutter analyze && flutter test`
Expected: No analyzer issues. All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart
git commit -m "feat(auth): _AppRoot pushes ResetPasswordScreen on recovery + snackbars deep-link errors"
```

---

## Task 11: Update `SignInPromptSheet` to route Create Account through `SignUpScreen`

**Files:**
- Modify: `lib/presentation/widgets/sign_in_prompt_sheet.dart`

Today the bottom sheet's "Create Account" button pushes `LoginScreen`, which previously hosted both flows. After the split, both buttons still landing on `LoginScreen` would force the user to find the "Sign up" link themselves. Push `LoginScreen` first (so the back stack reads naturally), then immediately push `SignUpScreen` on top.

- [ ] **Step 1: Update the widget**

Replace the body of `lib/presentation/widgets/sign_in_prompt_sheet.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:ccwmap/presentation/screens/login_screen.dart';
import 'package:ccwmap/presentation/screens/sign_up_screen.dart';

/// A bottom-sheet prompt shown to guests when they attempt an action that
/// requires an account. Offers Sign In / Create Account (Sign In opens
/// LoginScreen; Create Account opens LoginScreen with SignUpScreen pushed
/// on top so the back stack reads as Map → Login → Signup) and Cancel.
class SignInPromptSheet extends StatelessWidget {
  final String title;
  final String body;

  const SignInPromptSheet({super.key, required this.title, required this.body});

  void _openLogin(BuildContext context) {
    Navigator.of(context).pop();
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute<void>(builder: (_) => const LoginScreen()));
  }

  void _openSignUp(BuildContext context) {
    Navigator.of(context).pop();
    final navigator = Navigator.of(context, rootNavigator: true);
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => const LoginScreen(),
    ));
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => const SignUpScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(body, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _openLogin(context),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Sign In'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _openSignUp(context),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Create Account'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Update the existing sign-in-prompt-sheet test**

The existing "Create Account pushes another route" assertion expects `+1` push. After this change Create Account pushes two routes (LoginScreen + SignUpScreen on top), so update the assertion in `test/presentation/widgets/sign_in_prompt_sheet_test.dart`:

Find this block at the end of the third `testWidgets` block:

```dart
        await tester.tap(find.widgetWithText(OutlinedButton, 'Create Account'));
        await tester.pumpAndSettle();
        expect(
          pushedRoutes,
          countAfterSecondSheetOpen + 1,
        ); // second LoginScreen pushed
```

Replace with:

```dart
        await tester.tap(find.widgetWithText(OutlinedButton, 'Create Account'));
        await tester.pumpAndSettle();
        expect(
          pushedRoutes,
          countAfterSecondSheetOpen + 2,
        ); // LoginScreen pushed, then SignUpScreen pushed on top
```

- [ ] **Step 3: Run the existing sign-in-prompt-sheet tests**

Run: `flutter test test/presentation/widgets/sign_in_prompt_sheet_test.dart`
Expected: All 3 tests pass.

- [ ] **Step 4: Run analyze + full suite**

Run: `flutter analyze && flutter test`
Expected: No analyzer issues. All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/widgets/sign_in_prompt_sheet.dart test/presentation/widgets/sign_in_prompt_sheet_test.dart
git commit -m "refactor: route SignInPromptSheet 'Create Account' through SignUpScreen"
```

---

## Task 12: Update GitHub Pages callback page for `type=recovery`

**Files:**
- Modify: `docs/auth/callback/index.html`

Add a copy branch so the recovery flow shows reset-relevant text instead of "Email Confirmed!". The deep-link construction (which already propagates `type`) is unchanged.

- [ ] **Step 1: Add a tiny script that swaps the visible copy based on `?type`**

Open `docs/auth/callback/index.html` and replace the `<body>` opening through the start of the existing `<script>` tag with the version below. Keep everything in `<head>` (CSS, etc.) unchanged.

Find this block (approximately lines 161–197):

```html
<body>
    <div class="container">
        <div class="checkmark"></div>
        <h1>Email Confirmed!</h1>
        <p class="subtitle">Your CCW Map account has been verified.</p>

        <div class="instructions">
            <h3>Next Steps</h3>

            <div class="instruction-item">
                <div class="instruction-icon">1</div>
                <div class="instruction-text">
                    <strong>On Mobile Device</strong>
                    The CCW Map app should open automatically. If not, tap the button below.
                </div>
            </div>

            <div class="instruction-item">
                <div class="instruction-icon">2</div>
                <div class="instruction-text">
                    <strong>On Desktop</strong>
                    Open the CCW Map app on your phone and sign in with your email and password.
                </div>
            </div>
        </div>

        <div class="loading">
            <div class="spinner"></div>
            <p style="margin-top: 10px; color: #666;">Opening app...</p>
        </div>

        <button class="button" onclick="tryOpenApp()">Open CCW Map App</button>

        <div class="footer">
            Need help? Contact support or check the app for more information.
        </div>
    </div>
```

Replace with:

```html
<body>
    <div class="container">
        <div class="checkmark"></div>
        <h1 id="page-title">Email Confirmed!</h1>
        <p class="subtitle" id="page-subtitle">Your CCW Map account has been verified.</p>

        <div class="instructions">
            <h3 id="next-steps-heading">Next Steps</h3>

            <div class="instruction-item">
                <div class="instruction-icon">1</div>
                <div class="instruction-text">
                    <strong>On Mobile Device</strong>
                    <span id="mobile-copy">The CCW Map app should open automatically. If not, tap the button below.</span>
                </div>
            </div>

            <div class="instruction-item">
                <div class="instruction-icon">2</div>
                <div class="instruction-text">
                    <strong>On Desktop</strong>
                    <span id="desktop-copy">Open the CCW Map app on your phone and sign in with your email and password.</span>
                </div>
            </div>
        </div>

        <div class="loading">
            <div class="spinner"></div>
            <p style="margin-top: 10px; color: #666;">Opening app...</p>
        </div>

        <button class="button" id="open-app-button" onclick="tryOpenApp()">Open CCW Map App</button>

        <div class="footer">
            Need help? Contact support or check the app for more information.
        </div>
    </div>
```

- [ ] **Step 2: Insert the copy-branching logic at the top of the existing `<script>`**

Find the existing `<script>` tag (just below the closing `</div>` of `.container`, at approximately line 199) and insert this immediately after `<script>`, before the existing `function tryOpenApp() {` declaration:

```javascript
        // Branch the visible copy based on the OTP `type` query param so
        // the password-recovery flow doesn't render "Email Confirmed!".
        (function applyTypeCopy() {
            const params = new URLSearchParams(window.location.search);
            const type = params.get('type');
            if (type === 'recovery') {
                document.getElementById('page-title').textContent = 'Reset Your Password';
                document.getElementById('page-subtitle').textContent =
                    'Open this link in the CCW Map app to set a new password.';
                document.getElementById('mobile-copy').textContent =
                    'The CCW Map app should open automatically. If not, tap the button below.';
                document.getElementById('desktop-copy').textContent =
                    'Open this email on the device where CCW Map is installed and tap the link there to set a new password.';
                document.getElementById('open-app-button').textContent = 'Open CCW Map App';
            }
        })();
```

- [ ] **Step 3: Smoke-test the page locally**

Open the page directly in a browser via two URLs to confirm the branch:

```bash
# Open the file in your default browser. Adjust path on Windows if needed.
start docs/auth/callback/index.html?type=recovery
start docs/auth/callback/index.html?type=signup
```

Expected: First URL shows "Reset Your Password" + the desktop-copy "Open this email on the device …"; second URL shows "Email Confirmed!" + the original copy.

- [ ] **Step 4: Commit**

```bash
git add docs/auth/callback/index.html
git commit -m "docs(auth): branch callback copy on ?type for password-recovery flow"
```

---

## Final verification

- [ ] **Run the full test suite one last time**

Run: `flutter test`
Expected: All tests pass — roughly 109 (original) + 8 (VM) + 3 (forgot) + 3 (reset) + 4 (signup) + 3 new login = ~130 tests.

- [ ] **Run `flutter analyze` cleanly**

Run: `flutter analyze`
Expected: No issues found.

- [ ] **Manual test plan** — see `docs/superpowers/specs/2026-05-02-forgot-password-design.md` Manual test plan (14 steps, Android first per the project's per-SP testing cadence).

---

## Self-Review Notes

**Spec coverage check:**
- Forgot-password user flow → Tasks 4, 6, 7, 10
- Login/signup split → Tasks 8, 9, 11
- AuthRepository interface additions → Task 1
- SupabaseAuthRepository wiring → Task 3
- AuthViewModel additions including `_formatAuthError` extensions → Task 4
- ResetPasswordScreen with `PopScope` and Cancel → Task 7
- ForgotPasswordScreen success state → Task 6
- SignUpScreen with confirm-password + EULA → Task 8
- LoginScreen slim-down (drop EULA, drop signup, relax validator, add links) → Task 9
- `_AppRoot` recovery push + deep-link snackbar → Task 10
- SignInPromptSheet update → Task 11
- GitHub Pages callback copy branch → Task 12
- Shared `openTermsUrl` helper → Task 5
- FakeAuthRepository extension → Task 2
- Updated login_screen_test.dart → Task 9 Step 1
- New auth_viewmodel_password_reset_test.dart → Task 4 Step 1

**No deferred edge cases.** Recovery-link expiry, banned-user reset, cold-start trigger, pre-existing recovery session, and email-enumeration safety are all covered by the implementation as described in the spec — no additional task needed because they emerge naturally from the architecture (e.g., the recovery flag only fires on the explicit event, so closed-app-mid-recovery doesn't re-trigger).

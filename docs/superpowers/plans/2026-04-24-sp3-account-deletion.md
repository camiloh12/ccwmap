# SP-3 — Account Deletion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an authenticated user permanently delete their account from inside the app. Their pins persist with `created_by = NULL` (the "[deleted]" convention). Unblocks Apple Guideline 5.1.1(v) ("no in-app account deletion path").

**Architecture:** Client calls a new `delete-account` Supabase Edge Function. The function authenticates the caller via JWT, spins up an admin client with the service-role key, and invokes `supabase.auth.admin.deleteUser(user_id)` on the caller's own id — no admin role check is needed because callers can only delete themselves. Foreign-key cascades handle cleanup: `user_agreements` and `blocked_users` (both directions) are `ON DELETE CASCADE`, `pin_reports.reporter_id` and `pins.created_by` are `ON DELETE SET NULL`. On the client, a new Settings screen (reachable from a gear icon on `MapScreen` for authenticated users) hosts the two-dialog confirmation flow (warning → "type DELETE"). The ban error path updates `AuthViewModel._formatAuthError` to map the Supabase "banned" auth exception to a user-readable copy with the appeals email.

**Tech Stack:** Flutter 3.41.7 / Dart 3.11.5; Supabase Edge Functions (Deno runtime); `supabase_flutter`'s `functions.invoke` for the client call. No new packages.

**Spec reference:** `docs/superpowers/specs/2026-04-24-ios-rejection-response-design.md` — SP-3 section.

**Dependency on SP-2:** This plan assumes SP-1 and SP-2 are merged. `SupabaseRemoteDataSource` already contains moderation-related methods; `AuthViewModel` is already in use; `MapScreen` already has SP-1's auth-aware top-right icon. The delete-account cascade relies on FKs established by SP-2 migrations 004, 005, 006.

---

## File Structure

- **Create** `supabase/functions/delete-account/index.ts` — Deno edge function, ~60 LOC.
- **Create** `supabase/functions/delete-account/deno.json`.
- **Create** `lib/presentation/screens/settings_screen.dart` — account summary + Sign Out + Delete Account.
- **Create** `test/presentation/screens/settings_screen_test.dart`.
- **Modify** `lib/domain/repositories/auth_repository.dart` — add `deleteAccount()` to the interface.
- **Modify** `lib/data/repositories/supabase_auth_repository.dart` — implement via `functions.invoke`, drain sync queue, sign out, clear secure storage.
- **Modify** `test/fakes/fake_auth_repository.dart` — implement `deleteAccount()` for tests.
- **Modify** `lib/presentation/viewmodels/auth_viewmodel.dart` — add `deleteAccount()` with loading/error state; map the "banned" error in `_formatAuthError`.
- **Modify** `lib/presentation/screens/map_screen.dart` — add a gear icon next to the existing top-right icon; authenticated users see it, guests don't.
- **Modify** `docs/DEPLOY.md` — document the `delete-account` function alongside `send-moderation-email`.
- **Modify** `CLAUDE.md` — iteration status.

### Schema note

No schema migration. Verified 2026-04-24 in the design spec:
`public.pins.created_by` is already `uuid NULL` with `FK ... ON DELETE SET NULL`. SP-2 migrations 004/005/006 supply the cascades for the other tables. No migration 008.

---

### Task 1: `delete-account` Edge Function

**Files:**
- Create: `supabase/functions/delete-account/index.ts`
- Create: `supabase/functions/delete-account/deno.json`

- [x] **Step 1: Scaffold the function**

Create `supabase/functions/delete-account/deno.json`:

```json
{
  "imports": {
    "std/": "https://deno.land/std@0.224.0/"
  }
}
```

Create `supabase/functions/delete-account/index.ts`:

```typescript
// Supabase Edge Function: delete-account
//
// Authenticated-user self-deletion. The caller authenticates via JWT in
// the Authorization header; the function extracts the user id and calls
// supabase.auth.admin.deleteUser with the service-role key.
//
// No admin role check is required: callers can only delete themselves.
// Foreign-key cascades handle related rows:
//   user_agreements   ON DELETE CASCADE
//   blocked_users     ON DELETE CASCADE (both blocker_id and blocked_id)
//   pin_reports       reporter_id ON DELETE SET NULL
//   pins              created_by  ON DELETE SET NULL (preserves pins)

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) {
    return new Response("Missing bearer token", { status: 401 });
  }

  // Identify the caller using the anon key + the caller's JWT. getUser
  // validates the JWT and returns the user it belongs to.
  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: auth } },
  });

  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData.user) {
    return new Response("Invalid token", { status: 401 });
  }
  const userId = userData.user.id;

  // Use the service-role client for the admin delete.
  const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { error: delErr } = await adminClient.auth.admin.deleteUser(userId);
  if (delErr) {
    return new Response(`Delete failed: ${delErr.message}`, { status: 500 });
  }

  return new Response(JSON.stringify({ ok: true, user_id: userId }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
```

- [x] **Step 2: Commit**

```bash
git add supabase/functions/delete-account/
git commit -m "feat(sp3): delete-account Edge Function"
```

---

### Task 2: Deploy the function

**Files:** (none — live operation)

**Deployed 2026-04-24 via Supabase MCP** (`mcp__supabase__deploy_edge_function`, version 1, `verify_jwt: true`, slug `delete-account`). The manual CLI form below is kept for reference / re-deploy via laptop.

- [x] **Step 1: Deploy**

Run:

```bash
supabase functions deploy delete-account
```

Expected: success message + URL `https://<project-ref>.supabase.co/functions/v1/delete-account`.

- [x] **Step 2: Confirm env vars are set**

The `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` env vars are injected automatically into Supabase Edge Functions and do not need to be set explicitly. No action required — proceed.

- [ ] **Step 3: Manual smoke test**

Create a throwaway test account via the app. In Supabase Studio, note the user row exists in `auth.users` and has a zero or more pins in `public.pins`. Then from a terminal:

```bash
curl -X POST \
  -H "Authorization: Bearer <that-user's-access-token>" \
  https://<project-ref>.supabase.co/functions/v1/delete-account
```

(The access token is easiest to grab by logging the Supabase session from the client after signing in, temporarily.)

Expected response: `{"ok": true, "user_id": "<uuid>"}`. Verify in Studio: the row is gone from `auth.users`; the user's pins persist in `pins` with `created_by = NULL`; `user_agreements` rows for the user are gone.

- [x] **Step 4: No commit** (live operation only).

---

### Task 3: Add `deleteAccount()` to the domain interface and fake

**Files:**
- Modify: `lib/domain/repositories/auth_repository.dart`
- Modify: `test/fakes/fake_auth_repository.dart`

- [x] **Step 1: Extend the interface**

Edit `lib/domain/repositories/auth_repository.dart`. Append to the class:

```dart
  /// Permanently deletes the currently-authenticated user's account.
  ///
  /// Calls the `delete-account` Supabase Edge Function, which verifies
  /// the caller's JWT and invokes `auth.admin.deleteUser` for that user.
  /// On success, local secure storage is cleared and the user is signed
  /// out.
  ///
  /// Throws on network error or if the server rejects the deletion.
  Future<void> deleteAccount();
```

- [x] **Step 2: Extend the fake**

Edit `test/fakes/fake_auth_repository.dart`. Add:

```dart
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
```

Place these members just above the `/// Clean up resources` comment.

- [x] **Step 3: Run `flutter analyze`**

Expected: no errors. `SupabaseAuthRepository` will fail to compile because it hasn't implemented `deleteAccount` yet — that's the next task.

Run: `flutter analyze`
Expected: one analyzer error: `'SupabaseAuthRepository' is missing implementations for these members: AuthRepository.deleteAccount`. This is deliberate — Task 4 resolves it.

- [x] **Step 4: Commit (intermediate)**

```bash
git add lib/domain/repositories/auth_repository.dart \
        test/fakes/fake_auth_repository.dart
git commit -m "feat(sp3): deleteAccount() on AuthRepository interface + fake"
```

---

### Task 4: Implement `SupabaseAuthRepository.deleteAccount`

**Files:**
- Modify: `lib/data/repositories/supabase_auth_repository.dart`

- [x] **Step 1: Add constructor deps for cleanup**

The spec requires draining the local sync queue and clearing secure storage on successful delete. `SyncManager` and `FlutterSecureStorage` aren't currently on this class — inject them.

Edit `lib/data/repositories/supabase_auth_repository.dart`. Update the imports and the class:

Replace the top of the file (imports + constructor + private field):

```dart
import 'package:ccwmap/domain/models/user.dart' as domain;
import 'package:ccwmap/domain/repositories/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Supabase implementation of AuthRepository
class SupabaseAuthRepository implements AuthRepository {
  final supabase.SupabaseClient _supabase;

  SupabaseAuthRepository(this._supabase);
```

With:

```dart
import 'package:ccwmap/data/sync/sync_manager.dart';
import 'package:ccwmap/domain/models/user.dart' as domain;
import 'package:ccwmap/domain/repositories/auth_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Supabase implementation of AuthRepository
class SupabaseAuthRepository implements AuthRepository {
  final supabase.SupabaseClient _supabase;
  final SyncManager? _syncManager;
  final FlutterSecureStorage _secureStorage;

  SupabaseAuthRepository(
    this._supabase, {
    SyncManager? syncManager,
    FlutterSecureStorage? secureStorage,
  })  : _syncManager = syncManager,
        _secureStorage = secureStorage ?? const FlutterSecureStorage();
```

- [x] **Step 2: Implement `deleteAccount`**

Append to the class (before the closing brace):

```dart
  @override
  Future<void> deleteAccount() async {
    // Drain pending local writes first so we don't attempt uploads under
    // the soon-to-be-revoked JWT.
    try {
      await _syncManager?.processQueue();
    } catch (e) {
      debugPrint('SupabaseAuthRepository: pre-delete sync drain failed: $e');
      // Non-fatal: deleting an account with undelivered local writes is
      // acceptable. The local DB is cleared below.
    }

    // Call the Edge Function. invoke() automatically attaches the current
    // session's access token as the Authorization header.
    final resp = await _supabase.functions.invoke('delete-account');
    if (resp.status == null || resp.status! >= 400) {
      throw supabase.AuthException(
        'Delete account failed (status ${resp.status}): ${resp.data}',
      );
    }

    // Sign out locally — invalidates the in-memory session.
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      debugPrint('SupabaseAuthRepository: post-delete signOut error: $e');
    }

    // Clear any secure-storage tokens so a relaunch starts clean.
    try {
      await _secureStorage.deleteAll();
    } catch (e) {
      debugPrint('SupabaseAuthRepository: secure-storage clear error: $e');
    }
  }
```

- [x] **Step 3: Thread `SyncManager` into `main.dart`**

Edit `lib/main.dart`. Find:

```dart
  final authRepository = SupabaseAuthRepository(supabaseClient);
```

Replace with:

```dart
  final authRepository =
      SupabaseAuthRepository(supabaseClient, syncManager: syncManager);
```

- [x] **Step 4: Run `flutter analyze` and the full test suite**

Run: `flutter analyze`
Expected: no errors.

Run: `flutter test`
Expected: all pass. `FakeAuthRepository` already implements `deleteAccount` (Task 3), so `test/widget_test.dart` and the SP-2 tests continue to work.

- [x] **Step 5: Commit**

```bash
git add lib/data/repositories/supabase_auth_repository.dart lib/main.dart
git commit -m "feat(sp3): SupabaseAuthRepository.deleteAccount"
```

---

### Task 5: `AuthViewModel.deleteAccount` + banned-error mapping (TDD)

**Files:**
- Modify: `lib/presentation/viewmodels/auth_viewmodel.dart`
- Create: `test/presentation/viewmodels/auth_viewmodel_delete_test.dart`

- [x] **Step 1: Write failing tests**

Create `test/presentation/viewmodels/auth_viewmodel_delete_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/domain/models/user.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../fakes/fake_auth_repository.dart';

void main() {
  group('AuthViewModel.deleteAccount', () {
    late FakeAuthRepository fake;
    late AuthViewModel viewModel;

    setUp(() {
      fake = FakeAuthRepository();
      viewModel = AuthViewModel(fake);
      fake.setCurrentUser(User(id: 'u1', email: 'u1@example.com'));
    });

    tearDown(() {
      viewModel.dispose();
      fake.dispose();
    });

    test('success: delegates to repository and clears error', () async {
      await viewModel.deleteAccount();
      expect(fake.deleteCallCount, 1);
      expect(viewModel.error, isNull);
    });

    test('failure: surfaces error, does not throw', () async {
      fake.deleteShouldThrow = true;
      await viewModel.deleteAccount(); // should not throw
      expect(viewModel.error, isNotNull);
    });

    test('isLoading toggles around the call', () async {
      expect(viewModel.isLoading, isFalse);
      final future = viewModel.deleteAccount();
      expect(viewModel.isLoading, isTrue);
      await future;
      expect(viewModel.isLoading, isFalse);
    });
  });

  group('AuthViewModel.signIn banned error mapping', () {
    test(
      'maps "banned" AuthException to the suspension copy with appeals email',
      () async {
        final fake = _BannedAuthRepo();
        final vm = AuthViewModel(fake);

        await vm.signIn('u@example.com', 'whatever');

        expect(vm.error, contains('suspended'));
        expect(vm.error, contains('camilo@kyberneticlabs.com'));

        vm.dispose();
      },
    );
  });
}

/// Fake that throws an AuthException whose message contains "banned" on
/// sign in — reproduces Supabase's behavior for banned users.
class _BannedAuthRepo extends FakeAuthRepository {
  @override
  Future<void> signInWithEmail(String email, String password) async {
    throw const supabase.AuthException('User is banned until infinity.');
  }
}
```

- [x] **Step 2: Run the tests and confirm they fail**

Run: `flutter test test/presentation/viewmodels/auth_viewmodel_delete_test.dart`
Expected: FAIL — `deleteAccount` method missing; banned-error mapping not present.

- [x] **Step 3: Implement `deleteAccount` and extend `_formatAuthError`**

Edit `lib/presentation/viewmodels/auth_viewmodel.dart`.

Append `deleteAccount` inside the class, just above `clearError`:

```dart
  /// Permanently deletes the current user's account. Safe to await — on
  /// success, auth state change listeners will fire with null and the
  /// app returns to guest state; on failure, [error] is populated and
  /// the method returns normally (does not rethrow).
  Future<void> deleteAccount() async {
    _setLoading(true);
    _clearError();

    try {
      debugPrint('AuthViewModel: Deleting account');
      await _repository.deleteAccount();
      debugPrint('AuthViewModel: Account deletion successful');
    } on supabase.AuthException catch (e) {
      debugPrint('AuthViewModel: Delete failed: ${e.message}');
      _error = _formatAuthError(e);
      notifyListeners();
    } catch (e) {
      debugPrint('AuthViewModel: Delete error: $e');
      _error = 'Account deletion failed. Please try again.';
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }
```

Extend `_formatAuthError` to map the banned case. Find:

```dart
  String _formatAuthError(supabase.AuthException e) {
    final message = e.message.toLowerCase();

    if (message.contains('invalid login credentials')) {
      return 'Invalid email or password. Please try again.';
```

Replace with:

```dart
  String _formatAuthError(supabase.AuthException e) {
    final message = e.message.toLowerCase();

    if (message.contains('banned') || message.contains('suspended')) {
      return 'This account has been suspended for violating the community '
          'guidelines. For appeals, email camilo@kyberneticlabs.com.';
    }
    if (message.contains('invalid login credentials')) {
      return 'Invalid email or password. Please try again.';
```

- [x] **Step 4: Run the tests and verify they pass**

Run: `flutter test test/presentation/viewmodels/auth_viewmodel_delete_test.dart`
Expected: PASS (4 tests).

- [x] **Step 5: Commit**

```bash
git add lib/presentation/viewmodels/auth_viewmodel.dart \
        test/presentation/viewmodels/auth_viewmodel_delete_test.dart
git commit -m "feat(sp3): AuthViewModel.deleteAccount + banned-error mapping"
```

---

### Task 6: `SettingsScreen` (TDD)

**Files:**
- Create: `test/presentation/screens/settings_screen_test.dart`
- Create: `lib/presentation/screens/settings_screen.dart`

- [x] **Step 1: Write failing tests**

Create `test/presentation/screens/settings_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ccwmap/domain/models/user.dart';
import 'package:ccwmap/presentation/screens/settings_screen.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';

import '../../fakes/fake_auth_repository.dart';

void main() {
  group('SettingsScreen', () {
    Future<(AuthViewModel, FakeAuthRepository)> pump(
      WidgetTester tester, {
      required User user,
    }) async {
      final fake = FakeAuthRepository();
      final vm = AuthViewModel(fake);
      fake.setCurrentUser(user);

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthViewModel>.value(
          value: vm,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return (vm, fake);
    }

    testWidgets('renders signed-in email, Sign Out, Delete Account',
        (tester) async {
      await pump(tester, user: User(id: 'u', email: 'u@example.com'));

      expect(find.text('u@example.com'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Sign Out'), findsOneWidget);
      expect(
        find.widgetWithText(ElevatedButton, 'Delete Account'),
        findsOneWidget,
      );
    });

    testWidgets('Delete button disabled in second dialog until DELETE typed',
        (tester) async {
      await pump(tester, user: User(id: 'u', email: 'u@example.com'));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete Account'));
      await tester.pumpAndSettle();
      // First dialog: Continue.
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      // Second dialog: Delete button present but disabled.
      final deleteBtn = find.widgetWithText(ElevatedButton, 'Delete');
      expect(deleteBtn, findsOneWidget);
      ElevatedButton btn = tester.widget<ElevatedButton>(deleteBtn);
      expect(btn.onPressed, isNull);

      // Type DELETE.
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pumpAndSettle();

      btn = tester.widget<ElevatedButton>(deleteBtn);
      expect(btn.onPressed, isNotNull);
    });

    testWidgets(
      'typing DELETE and tapping Delete calls deleteAccount',
      (tester) async {
        final (_, fake) = await pump(
          tester,
          user: User(id: 'u', email: 'u@example.com'),
        );

        await tester.tap(find.widgetWithText(ElevatedButton, 'Delete Account'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'DELETE');
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
        await tester.pumpAndSettle();

        expect(fake.deleteCallCount, 1);
      },
    );

    testWidgets('Sign Out calls signOut on the repository', (tester) async {
      final (_, fake) = await pump(
        tester,
        user: User(id: 'u', email: 'u@example.com'),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Sign Out'));
      await tester.pumpAndSettle();

      // FakeAuthRepository.signOut() nulls the currentUser.
      expect(await fake.getCurrentUser(), isNull);
    });
  });
}
```

- [x] **Step 2: Run the tests and confirm they fail**

Run: `flutter test test/presentation/screens/settings_screen_test.dart`
Expected: FAIL — `SettingsScreen` undefined.

- [x] **Step 3: Implement `SettingsScreen`**

Create `lib/presentation/screens/settings_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _handleSignOut(BuildContext context) async {
    final auth = context.read<AuthViewModel>();
    await auth.signOut();
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _handleDelete(BuildContext context) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'This permanently deletes your account. Your pins will remain on '
          'the map as community contributions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (proceed != true) return;
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _DeleteConfirmDialog(),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    final auth = context.read<AuthViewModel>();
    await auth.deleteAccount();
    if (!context.mounted) return;

    if (auth.error == null) {
      Navigator.of(context).pop(); // close Settings, return to MapScreen
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account deleted.'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error!),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>();
    final email = auth.currentUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Signed in as',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Text(
                email,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 32),
              OutlinedButton(
                onPressed: auth.isLoading ? null : () => _handleSignOut(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Sign Out'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: auth.isLoading ? null : () => _handleDelete(context),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.red,
                ),
                child: const Text(
                  'Delete Account',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteConfirmDialog extends StatefulWidget {
  const _DeleteConfirmDialog();

  @override
  State<_DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends State<_DeleteConfirmDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _controller.text == 'DELETE';
    return AlertDialog(
      title: const Text('Confirm deletion'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Type DELETE to confirm.'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: enabled ? () => Navigator.of(context).pop(true) : null,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Delete', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
```

- [x] **Step 4: Run the tests and verify they pass**

Run: `flutter test test/presentation/screens/settings_screen_test.dart`
Expected: PASS (4 tests).

- [x] **Step 5: Commit**

```bash
git add lib/presentation/screens/settings_screen.dart \
        test/presentation/screens/settings_screen_test.dart
git commit -m "feat(sp3): SettingsScreen with sign-out and delete flow"
```

---

### Task 7: Add a gear icon to `MapScreen` (authenticated users only)

**Files:**
- Modify: `lib/presentation/screens/map_screen.dart`

- [x] **Step 1: Import `SettingsScreen`**

Edit `lib/presentation/screens/map_screen.dart`. Add:

```dart
import 'package:ccwmap/presentation/screens/settings_screen.dart';
```

- [x] **Step 2: Replace the single-icon Positioned block with a row of two icons (guest) or three (authenticated)**

Find the auth-aware top-right icon block added in SP-1 Task 4 (the `Positioned(... right: 16 ...) → Consumer<AuthViewModel>` block). Replace the whole `Positioned` with:

```dart
              // Top-right icon cluster. Guests see only the sign-in icon.
              // Authenticated users see a gear icon (Settings) to the left of
              // the exit-door (sign-out) icon.
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 16,
                child: Consumer<AuthViewModel>(
                  builder: (context, auth, _) {
                    final isAuthed = auth.isAuthenticated;
                    final buttons = <Widget>[];

                    if (isAuthed) {
                      buttons.add(_buildTopBarButton(
                        icon: Icons.settings,
                        tooltip: 'Settings',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SettingsScreen(),
                          ),
                        ),
                      ));
                      buttons.add(const SizedBox(width: 8));
                      buttons.add(_buildTopBarButton(
                        icon: Icons.exit_to_app,
                        tooltip: 'Sign out',
                        onTap: _onExitTapped,
                      ));
                    } else {
                      buttons.add(_buildTopBarButton(
                        icon: Icons.login,
                        tooltip: 'Sign in',
                        onTap: () => _promptSignIn(
                          title: 'Sign in',
                          body:
                              'Sign in to add pins and contribute to the community map.',
                        ),
                      ));
                    }

                    return Row(mainAxisSize: MainAxisSize.min, children: buttons);
                  },
                ),
              ),
```

- [x] **Step 3: Add a small helper to keep the buttons consistent**

Add this method on `_MapScreenState` (place it alongside the other helpers, e.g. just above `_onExitTapped`):

```dart
  Widget _buildTopBarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Tooltip(
          message: tooltip,
          child: Container(
            padding: const EdgeInsets.all(12),
            child: Icon(
              icon,
              color: Colors.black87,
              size: 24,
              semanticLabel: tooltip,
            ),
          ),
        ),
      ),
    );
  }
```

- [x] **Step 4: Update `test/widget_test.dart` to reflect the new cluster**

Edit `test/widget_test.dart`. Update the authenticated-launch test. Find:

```dart
      // Authenticated user sees the exit (sign-out) icon, NOT sign-in.
      expect(find.byIcon(Icons.exit_to_app), findsOneWidget);
      expect(find.byIcon(Icons.login), findsNothing);
```

Replace with:

```dart
      // Authenticated user sees the settings gear and the exit (sign-out)
      // icons; not the sign-in icon.
      expect(find.byIcon(Icons.settings), findsOneWidget);
      expect(find.byIcon(Icons.exit_to_app), findsOneWidget);
      expect(find.byIcon(Icons.login), findsNothing);
```

And in the guest test, assert the gear is absent:

Find:

```dart
      // Guest sees the sign-in icon, NOT the exit-to-app icon.
      expect(find.byIcon(Icons.login), findsOneWidget);
      expect(find.byIcon(Icons.exit_to_app), findsNothing);
```

Replace with:

```dart
      // Guest sees the sign-in icon only — no sign-out, no settings.
      expect(find.byIcon(Icons.login), findsOneWidget);
      expect(find.byIcon(Icons.exit_to_app), findsNothing);
      expect(find.byIcon(Icons.settings), findsNothing);
```

- [x] **Step 5: Run analyze + full test suite**

Run: `flutter analyze`
Expected: no errors.

Run: `flutter test`
Expected: all pass.

- [x] **Step 6: Commit**

```bash
git add lib/presentation/screens/map_screen.dart test/widget_test.dart
git commit -m "feat(sp3): add gear icon for Settings on MapScreen"
```

---

### Task 8: Update `docs/DEPLOY.md`

**Files:**
- Modify: `docs/DEPLOY.md`

- [x] **Step 1: Ensure delete-account is documented**

SP-2 Task 22 already wrote `docs/DEPLOY.md` with a reference to `delete-account` in the "Deploy a function" section. Verify that line exists:

```bash
grep "delete-account" docs/DEPLOY.md
```

Expected: the line `supabase functions deploy delete-account     # once SP-3 lands` is present. If it says "once SP-3 lands", remove that comment now:

Replace:

```
supabase functions deploy delete-account     # once SP-3 lands
```

With:

```
supabase functions deploy delete-account
```

- [x] **Step 2: Commit (only if the file changed)**

```bash
git add docs/DEPLOY.md
git commit -m "docs(sp3): remove 'once SP-3 lands' note from DEPLOY.md"
```

Skip the commit if the comment wasn't present.

---

### Task 9: Update `CLAUDE.md` status

**Files:**
- Modify: `CLAUDE.md`

- [x] **Step 1: Mark account deletion implemented**

In the "What's Implemented" block (updated in SP-2), append:

```markdown
- ✅ Account deletion (Settings → Delete Account → type-DELETE confirmation → delete-account Edge Function)
- ✅ Banned-user sign-in error surfaces suspension copy with appeals email
```

- [x] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(sp3): mark account deletion implemented"
```

---

### Task 10: End-to-end manual test (physical iOS device)

**Files:** (none — manual; device must be on a TestFlight build with SHOW_DEBUG_UI off to mirror App Store behavior)

- [ ] **Step 1: Capture `account-deletion.mov` screen recording** _(deferred until TestFlight build is on device)_

On a TestFlight build of v0.4.0:

1. Sign in with a disposable demo account (create one specifically for this purpose in Supabase).
2. Tap the gear icon → Settings opens.
3. Tap Delete Account → confirmation text appears ("This permanently deletes your account...").
4. Tap Continue → type-DELETE dialog appears. Confirm button is disabled.
5. Type `DELETE` (case-sensitive) → Confirm enables. Tap.
6. Spinner, then return to guest map. Snackbar reads "Account deleted."
7. Try to sign in with the deleted credentials → error "Invalid email or password."

Recording must show steps 2–7 end-to-end. Save as `account-deletion.mov` next to `guest-browse.mov` and `ugc-moderation.mov` for the App Store Resubmission (see spec Section "App Store resubmission plan").

- [x] **Step 2: Verify in Supabase Studio**

- `auth.users` row for the demo account: gone.
- `pins` rows created by that user: still present with `created_by = NULL`.
- `user_agreements` rows for that user_id: gone.
- `blocked_users` rows where `blocker_id` or `blocked_id` equals the deleted user: gone.
- `pin_reports` rows with `reporter_id` equal to the deleted user: row present with `reporter_id = NULL`.

- [x] **Step 3: Verify banned copy**

In Studio, manually ban a different demo account (Authentication → Users → Ban). On the device, sign out and attempt to sign in as that user. Expected: error copy contains "suspended" and `camilo@kyberneticlabs.com`. (The banned sign-in is the full loop for App Review — capture it if Apple specifically asks about it, otherwise it's sufficient for the playbook.)

- [ ] **Step 4: No commit.**

---

## Self-Review Checklist

- [x] `delete-account` Edge Function exists, deployed, smoke-tested via in-app flow (Tasks 1–2). _(Deployed via Supabase MCP; end-to-end verified in-app instead of curl.)_
- [x] `AuthRepository.deleteAccount()` added to interface and Supabase impl; `FakeAuthRepository` mirrors it (Tasks 3–4).
- [x] `AuthViewModel.deleteAccount()` tested (success, failure, loading); `_formatAuthError` maps the banned-user AuthException (Task 5).
- [x] `SettingsScreen` renders, requires typing DELETE, calls `deleteAccount`, and routes post-delete back to `MapScreen` (Task 6).
- [x] Gear icon on `MapScreen` appears for authenticated users only; widget_test.dart updated (Task 7).
- [x] Docs updated (`DEPLOY.md`, `CLAUDE.md`) (Tasks 8–9).
- [ ] Manual on-device test recorded `account-deletion.mov` and verified server-side cascade behavior (Task 10). _(Cascade + banned-copy verified; recording deferred until TestFlight build.)_

## Verification

Final gate before opening the `release/v0.4.0` pull request:

```bash
flutter analyze
flutter test
```

All three screen recordings (`guest-browse.mov`, `ugc-moderation.mov`, `account-deletion.mov`) must be captured. The App Review Notes text from the design spec is ready to paste into App Store Connect.

# SP-1 — Anonymous Map Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let any user view the map and all pins without signing in. Creation, editing, and deletion of pins still require authentication. Unblocks App Store rejection on Guideline 5.1.1(v) ("non-account features require registration").

**Architecture:** Collapse the `AuthGate` root router — `MapScreen` becomes the app's home. `LoginScreen` is no longer reachable by routing decision; it's pushed on demand from a new `SignInPromptSheet`. Auth state is read inline in `MapScreen` via `Consumer<AuthViewModel>`: the top-right icon is a sign-in button for guests and the existing exit-door (sign-out) for authenticated users, and the tap handlers that invoke create/edit flows short-circuit to the prompt sheet for guests. `PinDialog` gets a read-only mode so guests tapping an existing pin see data without edit controls.

**Tech Stack:** Flutter 3.41.7 / Dart 3.11.5, existing `provider: ^6.x`, existing `app_links` for deep-link listening, no new packages.

**Spec reference:** `docs/superpowers/specs/2026-04-24-ios-rejection-response-design.md` — SP-1 section.

---

## File Structure

- **Create** `lib/presentation/widgets/sign_in_prompt_sheet.dart` — new stateless widget rendered via `showModalBottomSheet`. ~80 LOC. Title/body configurable per call site. Two action buttons (Sign In / Create Account) both `Navigator.push` the existing unmodified `LoginScreen`.
- **Create** `test/presentation/widgets/sign_in_prompt_sheet_test.dart` — three widget tests (renders, Sign In pushes LoginScreen, Cancel dismisses).
- **Modify** `lib/presentation/widgets/pin_dialog.dart` — add `isReadOnly` bool param (default `false`). When true, wrap form controls with `AbsorbPointer` + visual disabled state, hide the create/save button and delete button, and show a primary "Sign in to edit" button plus "Close". ~40 LOC added.
- **Create** `test/presentation/widgets/pin_dialog_readonly_test.dart` — two widget tests (read-only renders with sign-in button, read-only hides create/delete).
- **Modify** `lib/main.dart` — delete the `AuthGate` class entirely. Move deep-link listening and `AuthViewModel.initialize()` kickoff into a new stateful wrapper (or into `CCWMapApp` directly) that does not branch on auth state. `MaterialApp.home` becomes `MapScreen()` directly. ~60 LOC net reduction.
- **Modify** `lib/presentation/screens/map_screen.dart` — swap the top-right exit icon for an auth-aware block: guests see a sign-in icon that opens the prompt sheet, authenticated users see the existing exit-door icon. Guard the two tap-handlers (`_onFeatureTapped`, `_onMapClick`) and the long-press handler (`_onMapLongClick`) on `AuthViewModel.isAuthenticated`: authenticated → current flow; guest → open `SignInPromptSheet` for create paths; guest + existing-pin tap → open `PinDialog(isReadOnly: true)`. ~80 LOC added/modified.
- **Modify** `test/widget_test.dart` — the existing two tests assume auth-gated root routing. Replace them with: (1) guest launch renders map + sign-in icon; (2) authenticated launch renders map + exit icon. Drops the "shows LoginScreen when not authenticated" assertion because routing no longer works that way.
- **Create** `test/presentation/screens/map_screen_guest_test.dart` — widget tests for guest flows that don't require live map tiles (see Task 7 for the narrow widget-only subset we can test; full tap-handler coverage is manual on-device per the spec).

### Decisions locked by this structure

- `SignInPromptSheet` is a pure widget with a callback, not a service. Call sites invoke `showModalBottomSheet` directly and supply a context string — keeps navigation intent at the call site.
- `PinDialog.isReadOnly` is a param rather than a new widget. The spec mandates this ("Reusing PinDialog (rather than a new widget) keeps rendering and layout consistent").
- Deep-link handling is not auth-gated and must continue working during guest mode (so users who get an email-confirmation link on a guest session still have their session established). The new non-gated wrapper handles this identically to the old `AuthGate`.

---

### Task 1: `SignInPromptSheet` widget (TDD)

**Files:**
- Create: `test/presentation/widgets/sign_in_prompt_sheet_test.dart`
- Create: `lib/presentation/widgets/sign_in_prompt_sheet.dart`

- [ ] **Step 1: Write the failing test file**

Create `test/presentation/widgets/sign_in_prompt_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/presentation/widgets/sign_in_prompt_sheet.dart';

void main() {
  group('SignInPromptSheet', () {
    testWidgets('renders title, body, and three buttons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => const SignInPromptSheet(
                      title: 'Sign in to add pins',
                      body:
                          'Create an account or sign in to contribute to the community map.',
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Sign in to add pins'), findsOneWidget);
      expect(
        find.text(
          'Create an account or sign in to contribute to the community map.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(ElevatedButton, 'Sign In'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Create Account'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    });

    testWidgets('Cancel dismisses the sheet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => const SignInPromptSheet(
                      title: 't',
                      body: 'b',
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(SignInPromptSheet), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(SignInPromptSheet), findsNothing);
    });

    testWidgets('Sign In and Create Account both push a new route',
        (tester) async {
      int pushedRoutes = 0;
      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: ctx,
                    builder: (_) => const SignInPromptSheet(
                      title: 't',
                      body: 'b',
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          navigatorObservers: [
            _CountingObserver(onPush: () => pushedRoutes++),
          ],
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
      await tester.pumpAndSettle();
      // Pushed the LoginScreen route.
      expect(pushedRoutes, greaterThanOrEqualTo(2)); // initial + push
    });
  });
}

class _CountingObserver extends NavigatorObserver {
  final VoidCallback onPush;
  _CountingObserver({required this.onPush});
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onPush();
    super.didPush(route, previousRoute);
  }
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `flutter test test/presentation/widgets/sign_in_prompt_sheet_test.dart`
Expected: FAIL with "Target of URI doesn't exist: 'package:ccwmap/presentation/widgets/sign_in_prompt_sheet.dart'".

- [ ] **Step 3: Implement the widget**

Create `lib/presentation/widgets/sign_in_prompt_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:ccwmap/presentation/screens/login_screen.dart';

/// A bottom-sheet prompt shown to guests when they attempt an action that
/// requires an account. Offers Sign In / Create Account (both route to the
/// same [LoginScreen], which exposes both affordances) and Cancel.
class SignInPromptSheet extends StatelessWidget {
  final String title;
  final String body;

  const SignInPromptSheet({
    super.key,
    required this.title,
    required this.body,
  });

  void _openLogin(BuildContext context) {
    // Close the sheet, then push LoginScreen on the root navigator so the
    // returning user pops back to the map.
    Navigator.of(context).pop();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(body, style: const TextStyle(fontSize: 15)),
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
              onPressed: () => _openLogin(context),
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

- [ ] **Step 4: Run the test and verify it passes**

Run: `flutter test test/presentation/widgets/sign_in_prompt_sheet_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/widgets/sign_in_prompt_sheet.dart \
        test/presentation/widgets/sign_in_prompt_sheet_test.dart
git commit -m "feat(sp1): add SignInPromptSheet for guest auth prompts"
```

---

### Task 2: `PinDialog` read-only mode (TDD)

**Files:**
- Create: `test/presentation/widgets/pin_dialog_readonly_test.dart`
- Modify: `lib/presentation/widgets/pin_dialog.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/presentation/widgets/pin_dialog_readonly_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/domain/models/pin_status.dart';
import 'package:ccwmap/domain/models/restriction_tag.dart';
import 'package:ccwmap/presentation/widgets/pin_dialog.dart';

void main() {
  group('PinDialog read-only mode', () {
    Future<void> pumpReadOnly(
      WidgetTester tester, {
      bool onSignInCalled = false,
      VoidCallback? onSignIn,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PinDialog(
              isEditMode: true,
              isReadOnly: true,
              poiName: 'Courthouse',
              initialStatus: PinStatus.NO_GUN,
              initialRestrictionTag: RestrictionTag.STATE_LOCAL_GOVT,
              initialHasSecurityScreening: true,
              initialHasPostedSignage: false,
              onConfirm: (_) {},
              onCancel: () {},
              onSignInToEdit: onSignIn ?? () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders "Sign in to edit" and "Close", hides Save/Delete',
        (tester) async {
      await pumpReadOnly(tester);

      expect(
        find.widgetWithText(ElevatedButton, 'Sign in to edit'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Close'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Save'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Delete Pin'), findsNothing);
    });

    testWidgets('name field is disabled in read-only mode', (tester) async {
      await pumpReadOnly(tester);

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isFalse);
    });

    testWidgets('Sign in to edit triggers the callback', (tester) async {
      var called = false;
      await pumpReadOnly(tester, onSignIn: () => called = true);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in to edit'));
      await tester.pumpAndSettle();

      expect(called, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run: `flutter test test/presentation/widgets/pin_dialog_readonly_test.dart`
Expected: FAIL — `isReadOnly`, `onSignInToEdit` parameters do not exist.

- [ ] **Step 3: Add read-only mode to `PinDialog`**

Edit `lib/presentation/widgets/pin_dialog.dart`.

Change the constructor to add `isReadOnly` and `onSignInToEdit`. Replace:

```dart
  const PinDialog({
    super.key,
    required this.isEditMode,
    required this.poiName,
    this.initialStatus,
    this.initialRestrictionTag,
    this.initialHasSecurityScreening = false,
    this.initialHasPostedSignage = false,
    required this.onConfirm,
    this.onDelete,
    required this.onCancel,
  });
```

With:

```dart
  final bool isReadOnly;
  final VoidCallback? onSignInToEdit;

  const PinDialog({
    super.key,
    required this.isEditMode,
    required this.poiName,
    this.initialStatus,
    this.initialRestrictionTag,
    this.initialHasSecurityScreening = false,
    this.initialHasPostedSignage = false,
    required this.onConfirm,
    this.onDelete,
    required this.onCancel,
    this.isReadOnly = false,
    this.onSignInToEdit,
  }) : assert(
         !isReadOnly || onSignInToEdit != null,
         'onSignInToEdit is required when isReadOnly is true',
       );
```

Disable the name TextField when read-only. Replace:

```dart
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: 'Enter a name for this location',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                style: const TextStyle(fontSize: 16),
                maxLength: 100,
                onChanged: (_) => setState(() {}), // Update validation state
              ),
```

With:

```dart
              TextField(
                controller: _nameController,
                enabled: !widget.isReadOnly,
                decoration: InputDecoration(
                  hintText: 'Enter a name for this location',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                style: const TextStyle(fontSize: 16),
                maxLength: 100,
                onChanged: (_) => setState(() {}), // Update validation state
              ),
```

Wrap the status-option, restriction-dropdown, and the two checkboxes in `AbsorbPointer` when read-only. The simplest safe change: wrap the entire column of controls between the name field and the action buttons. Find the `// Status Selection` block and the action-buttons `Row` at the bottom, and wrap everything strictly between them with `AbsorbPointer(absorbing: widget.isReadOnly, child: Column(...))`. Because that region spans several widgets already under `Column`, the minimal change is:

Replace the action-buttons section and the delete button (lines starting with `// Delete Button (edit mode only)` through the closing `Row(`...`children: [...])` of the action buttons) with a branch:

Find:

```dart
              // Delete Button (edit mode only)
              if (widget.isEditMode && widget.onDelete != null) ...[
                OutlinedButton.icon(
                  onPressed: widget.onDelete,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    side: const BorderSide(color: Colors.red, width: 1.5),
                  ),
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text(
                    'Delete Pin',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: widget.onCancel,
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isValid ? _handleConfirm : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      backgroundColor: const Color(0xFF6200EE),
                    ),
                    child: Text(
                      widget.isEditMode ? 'Save' : 'Create',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
```

Replace with:

```dart
              // Delete Button (edit mode + writable only)
              if (!widget.isReadOnly &&
                  widget.isEditMode &&
                  widget.onDelete != null) ...[
                OutlinedButton.icon(
                  onPressed: widget.onDelete,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    side: const BorderSide(color: Colors.red, width: 1.5),
                  ),
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text(
                    'Delete Pin',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Action Buttons
              if (widget.isReadOnly)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton(
                      onPressed: widget.onSignInToEdit,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        backgroundColor: const Color(0xFF6200EE),
                      ),
                      child: const Text(
                        'Sign in to edit',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: widget.onCancel,
                      child: Text(
                        'Close',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: widget.onCancel,
                      child: Text(
                        'Cancel',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _isValid ? _handleConfirm : null,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        backgroundColor: const Color(0xFF6200EE),
                      ),
                      child: Text(
                        widget.isEditMode ? 'Save' : 'Create',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
```

Now disable status options and checkboxes when read-only. In `_buildStatusOption`, wrap the `InkWell.onTap` so read-only mode swallows taps:

Find:

```dart
  Widget _buildStatusOption(PinStatus status, String label, Color color) {
    final isSelected = _selectedStatus == status;

    return InkWell(
      onTap: () => setState(() {
```

Replace the `onTap:` with:

```dart
  Widget _buildStatusOption(PinStatus status, String label, Color color) {
    final isSelected = _selectedStatus == status;

    return InkWell(
      onTap: widget.isReadOnly ? null : () => setState(() {
```

In `_buildRestrictionDropdown`, disable the `DropdownButton.onChanged` when read-only:

Find:

```dart
          onChanged: (value) => setState(() => _selectedRestrictionTag = value),
```

Replace with:

```dart
          onChanged: widget.isReadOnly
              ? null
              : (value) => setState(() => _selectedRestrictionTag = value),
```

In `_buildCheckbox`, disable the InkWell + Checkbox when read-only:

Find:

```dart
  Widget _buildCheckbox(
    String label,
    bool value,
    ValueChanged<bool?> onChanged,
  ) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: const Color(0xFF6200EE),
            ),
          ),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 15)),
        ],
      ),
    );
  }
```

Replace with:

```dart
  Widget _buildCheckbox(
    String label,
    bool value,
    ValueChanged<bool?> onChanged,
  ) {
    return InkWell(
      onTap: widget.isReadOnly ? null : () => onChanged(!value),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: value,
              onChanged: widget.isReadOnly ? null : onChanged,
              activeColor: const Color(0xFF6200EE),
            ),
          ),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 15)),
        ],
      ),
    );
  }
```

- [ ] **Step 4: Run the new tests and verify they pass**

Run: `flutter test test/presentation/widgets/pin_dialog_readonly_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the full test suite to confirm no regression**

Run: `flutter test`
Expected: all tests pass. If any existing test breaks because it supplies positional parameters to `PinDialog`, note it and fix at the call site (but the constructor change is additive-only, so nothing should break).

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/widgets/pin_dialog.dart \
        test/presentation/widgets/pin_dialog_readonly_test.dart
git commit -m "feat(sp1): add read-only mode to PinDialog for guest viewers"
```

---

### Task 3: Collapse `AuthGate` — `MapScreen` becomes the root

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Replace `AuthGate` with a non-gating wrapper**

Edit `lib/main.dart`. Replace the contents of `CCWMapApp.build` and the entire `AuthGate` class.

Find:

```dart
      child: MaterialApp(
        title: 'CCW Map',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6200EE), // Purple primary color
            brightness: Brightness.light,
          ),
          appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
        ),
        home: const AuthGate(),
      ),
    );
  }
}
```

Replace with:

```dart
      child: MaterialApp(
        title: 'CCW Map',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6200EE), // Purple primary color
            brightness: Brightness.light,
          ),
          appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
        ),
        home: const _AppRoot(),
      ),
    );
  }
}
```

Then delete the entire `AuthGate` class and replace it with `_AppRoot`, which is a non-gating wrapper that owns auth initialization and deep-link listening. Find and delete:

```dart
/// Gate that shows LoginScreen or MapScreen based on authentication state
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<Uri>? _deepLinkSubscription;

  @override
  void initState() {
    super.initState();

    // Initialize AuthViewModel after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authViewModel = context.read<AuthViewModel>();
      authViewModel.initialize();
      _initializeDeepLinkListener(authViewModel);
    });
  }

  Future<void> _initializeDeepLinkListener(AuthViewModel authViewModel) async {
    final appLinks = AppLinks();

    // Handle initial deep link (cold start - app was closed)
    try {
      final initialLink = await appLinks.getInitialLink();
      if (initialLink != null) {
        debugPrint('AuthGate: Processing initial deep link: $initialLink');
        await authViewModel.handleDeepLink(initialLink);
      }
    } catch (e) {
      debugPrint('AuthGate: Failed to process initial deep link: $e');
      authViewModel.setError('Failed to process authentication link.');
    }

    // Listen to runtime deep links (app is already open)
    _deepLinkSubscription = appLinks.uriLinkStream.listen(
      (Uri uri) {
        debugPrint('AuthGate: Processing runtime deep link: $uri');
        authViewModel.handleDeepLink(uri);
      },
      onError: (err) {
        debugPrint('AuthGate: Deep link stream error: $err');
        authViewModel.setError('Failed to process authentication link.');
      },
    );
  }

  @override
  void dispose() {
    _deepLinkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthViewModel>(
      builder: (context, authViewModel, child) {
        // Show loading while initializing
        if (authViewModel.currentUser == null && authViewModel.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Show MapScreen if authenticated, LoginScreen otherwise
        if (authViewModel.isAuthenticated) {
          return const MapScreen();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}
```

Replace with:

```dart
/// Root widget. Owns auth-state initialization and deep-link listening but
/// does NOT gate routing on auth — the map is visible to everyone. Auth-
/// sensitive affordances (create/edit/delete pins, sign out) are decided
/// inside [MapScreen] by reading [AuthViewModel] directly.
class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  StreamSubscription<Uri>? _deepLinkSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authViewModel = context.read<AuthViewModel>();
      authViewModel.initialize();
      _initializeDeepLinkListener(authViewModel);
    });
  }

  Future<void> _initializeDeepLinkListener(AuthViewModel authViewModel) async {
    final appLinks = AppLinks();

    try {
      final initialLink = await appLinks.getInitialLink();
      if (initialLink != null) {
        debugPrint('_AppRoot: Processing initial deep link: $initialLink');
        await authViewModel.handleDeepLink(initialLink);
      }
    } catch (e) {
      debugPrint('_AppRoot: Failed to process initial deep link: $e');
      authViewModel.setError('Failed to process authentication link.');
    }

    _deepLinkSubscription = appLinks.uriLinkStream.listen(
      (Uri uri) {
        debugPrint('_AppRoot: Processing runtime deep link: $uri');
        authViewModel.handleDeepLink(uri);
      },
      onError: (err) {
        debugPrint('_AppRoot: Deep link stream error: $err');
        authViewModel.setError('Failed to process authentication link.');
      },
    );
  }

  @override
  void dispose() {
    _deepLinkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const MapScreen();
}
```

The `LoginScreen` import stays — `SignInPromptSheet` (Task 1) references it. The other imports (`MapScreen`, etc.) stay.

- [ ] **Step 2: Run the app-level tests to surface expected failures**

Run: `flutter test test/widget_test.dart`
Expected: FAIL. The existing two tests check `AuthGate` routing behavior which no longer exists. Task 5 rewrites them.

- [ ] **Step 3: Commit (intermediate — tests will be fixed in Task 5)**

```bash
git add lib/main.dart
git commit -m "refactor(sp1): collapse AuthGate, MapScreen is now the root"
```

Note: `test/widget_test.dart` will fail at HEAD until Task 5 is complete. This is expected and tracked.

---

### Task 4: Auth-aware `MapScreen` — top-right icon + guarded tap handlers

**Files:**
- Modify: `lib/presentation/screens/map_screen.dart`

- [ ] **Step 1: Add import for `SignInPromptSheet`**

Edit `lib/presentation/screens/map_screen.dart`. Find the import block (top of file). Add the line shown below after the existing `pin_dialog.dart` import:

Find:

```dart
import 'package:ccwmap/presentation/widgets/pin_dialog.dart';
import 'package:ccwmap/presentation/widgets/compass_button.dart';
```

Replace with:

```dart
import 'package:ccwmap/presentation/widgets/pin_dialog.dart';
import 'package:ccwmap/presentation/widgets/sign_in_prompt_sheet.dart';
import 'package:ccwmap/presentation/widgets/compass_button.dart';
```

- [ ] **Step 2: Add a helper to open the sign-in prompt**

Add a new method on `_MapScreenState`. Insert it just above `_onExitTapped` (which is at line 1402 at time of writing):

```dart
  /// Shows the sign-in bottom sheet. Called from guest taps that would
  /// otherwise start a create/edit flow.
  void _promptSignIn({required String title, required String body}) {
    if (_isDialogOpen) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SignInPromptSheet(title: title, body: body),
    );
  }
```

- [ ] **Step 3: Branch `_onFeatureTapped` on auth state**

Guests tapping an existing pin should see the read-only `PinDialog`, not the edit dialog. Find the end of `_onFeatureTapped` where the edit dialog is shown:

```dart
    debugPrint('Found pin: ${pin.name}');
    _setDebugDetection(
      'feature-tap: ${pin.name}${pixelDist != null ? " (${pixelDist.toStringAsFixed(0)}px)" : ""}',
    );
    _showPinDialog(
      isEditMode: true,
      poiName: pin.name,
      initialStatus: pin.status,
      initialRestrictionTag: pin.restrictionTag,
      initialHasSecurityScreening: pin.hasSecurityScreening,
      initialHasPostedSignage: pin.hasPostedSignage,
      pinId: pin.id,
    );
  }
```

Replace with:

```dart
    debugPrint('Found pin: ${pin.name}');
    _setDebugDetection(
      'feature-tap: ${pin.name}${pixelDist != null ? " (${pixelDist.toStringAsFixed(0)}px)" : ""}',
    );

    final auth = Provider.of<AuthViewModel>(context, listen: false);
    if (!auth.isAuthenticated) {
      _showReadOnlyPinDialog(pin);
      return;
    }

    _showPinDialog(
      isEditMode: true,
      poiName: pin.name,
      initialStatus: pin.status,
      initialRestrictionTag: pin.restrictionTag,
      initialHasSecurityScreening: pin.hasSecurityScreening,
      initialHasPostedSignage: pin.hasPostedSignage,
      pinId: pin.id,
    );
  }
```

- [ ] **Step 4: Branch `_onMapClick` on auth state for both POI-create and near-pin paths**

In `_onMapClick`, the POI-creation branch currently calls `_showPinDialog(isEditMode: false, ...)`. Find:

```dart
        // Show create dialog with POI name
        if (mounted) {
          _showPinDialog(
            isEditMode: false,
            poiName: poiName,
            initialStatus: null,
            initialRestrictionTag: null,
            initialHasSecurityScreening: false,
            initialHasPostedSignage: false,
            coordinates: LatLng(poiLat, poiLng),
          );
        }
        return;
      }
```

Replace with:

```dart
        // Show create dialog with POI name (or prompt guests to sign in)
        if (mounted) {
          final auth = Provider.of<AuthViewModel>(context, listen: false);
          if (!auth.isAuthenticated) {
            _promptSignIn(
              title: 'Sign in to add pins',
              body:
                  'Create an account or sign in to contribute to the community map.',
            );
            return;
          }
          _showPinDialog(
            isEditMode: false,
            poiName: poiName,
            initialStatus: null,
            initialRestrictionTag: null,
            initialHasSecurityScreening: false,
            initialHasPostedSignage: false,
            coordinates: LatLng(poiLat, poiLng),
          );
        }
        return;
      }
```

The near-pin branch in `_onMapClick` opens an edit dialog for guests too — branch it. Find:

```dart
          debugPrint('Opening edit dialog for pin: $pinName (ID: $pinId)');

          _showPinDialog(
            isEditMode: true,
            poiName: pinName,
            initialStatus: status,
            initialRestrictionTag: restrictionTag,
            initialHasSecurityScreening: hasSecurityScreening,
            initialHasPostedSignage: hasPostedSignage,
            pinId: pinId,
          );
        }
```

Replace with:

```dart
          debugPrint('Opening edit dialog for pin: $pinName (ID: $pinId)');

          final auth = Provider.of<AuthViewModel>(context, listen: false);
          if (!auth.isAuthenticated) {
            // Re-fetch the Pin so we show read-only with full data.
            _showReadOnlyPinDialog(clickedPin);
            return;
          }
          _showPinDialog(
            isEditMode: true,
            poiName: pinName,
            initialStatus: status,
            initialRestrictionTag: restrictionTag,
            initialHasSecurityScreening: hasSecurityScreening,
            initialHasPostedSignage: hasPostedSignage,
            pinId: pinId,
          );
        }
```

- [ ] **Step 5: Branch `_onMapLongClick` on auth state**

Long-press creates a pin at an empty location; guests should be prompted to sign in. Locate `_onMapLongClick` (starts around line 733). Find the block where it shows the create dialog (the pattern is similar to the POI branch — a `_showPinDialog(isEditMode: false, ...)` call). Wrap that call with the same auth check as Step 4:

```dart
final auth = Provider.of<AuthViewModel>(context, listen: false);
if (!auth.isAuthenticated) {
  _promptSignIn(
    title: 'Sign in to add pins',
    body:
        'Create an account or sign in to contribute to the community map.',
  );
  return;
}
```

immediately before the `_showPinDialog(isEditMode: false, ...)` invocation inside `_onMapLongClick`.

- [ ] **Step 6: Add `_showReadOnlyPinDialog` helper**

Add this method on `_MapScreenState`. Place it immediately after `_showPinDialog` (ends near line 1140 depending on prior edits):

```dart
  /// Shows a read-only [PinDialog] for guests tapping an existing pin.
  /// Tapping "Sign in to edit" closes the dialog and opens the prompt sheet.
  Future<void> _showReadOnlyPinDialog(Pin pin) async {
    _isDialogOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PinDialog(
        isEditMode: true,
        isReadOnly: true,
        poiName: pin.name,
        initialStatus: pin.status,
        initialRestrictionTag: pin.restrictionTag,
        initialHasSecurityScreening: pin.hasSecurityScreening,
        initialHasPostedSignage: pin.hasPostedSignage,
        onConfirm: (_) {
          // Unreachable in read-only mode; provided to satisfy required param.
        },
        onCancel: () =>
            Navigator.of(dialogContext, rootNavigator: true).pop(),
        onSignInToEdit: () {
          Navigator.of(dialogContext, rootNavigator: true).pop();
          _promptSignIn(
            title: 'Sign in to edit',
            body:
                'Create an account or sign in to contribute to the community map.',
          );
        },
      ),
    );
    _isDialogOpen = false;
    _lastDialogCloseTime = DateTime.now();
  }
```

- [ ] **Step 7: Swap the top-right exit icon for an auth-aware variant**

Find the existing exit icon block in `build` (the `Positioned(... right: 16, ... Icons.exit_to_app ...)` around line 1622):

```dart
              // Exit/sign out icon (top-right)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 16,
                child: Material(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                  elevation: 2,
                  child: InkWell(
                    onTap: _onExitTapped,
                    borderRadius: BorderRadius.circular(8),
                    child: Tooltip(
                      message: 'Sign out',
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        child: const Icon(
                          Icons.exit_to_app,
                          color: Colors.black87,
                          size: 24,
                          semanticLabel: 'Sign out button',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
```

Replace with:

```dart
              // Top-right icon: auth-aware.
              // Guests see a sign-in icon that opens the prompt sheet.
              // Authenticated users see the existing exit (sign-out) icon.
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 16,
                child: Consumer<AuthViewModel>(
                  builder: (context, auth, _) {
                    final isAuthed = auth.isAuthenticated;
                    return Material(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(8),
                      elevation: 2,
                      child: InkWell(
                        onTap: isAuthed
                            ? _onExitTapped
                            : () => _promptSignIn(
                                  title: 'Sign in',
                                  body:
                                      'Sign in to add pins and contribute to the community map.',
                                ),
                        borderRadius: BorderRadius.circular(8),
                        child: Tooltip(
                          message: isAuthed ? 'Sign out' : 'Sign in',
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            child: Icon(
                              isAuthed ? Icons.exit_to_app : Icons.login,
                              color: Colors.black87,
                              size: 24,
                              semanticLabel:
                                  isAuthed ? 'Sign out button' : 'Sign in button',
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
```

- [ ] **Step 8: Run analyze + full test suite**

Run: `flutter analyze`
Expected: no new errors or warnings introduced.

Run: `flutter test`
Expected: `test/widget_test.dart` still fails (Task 5 fixes it); all other tests pass.

- [ ] **Step 9: Commit**

```bash
git add lib/presentation/screens/map_screen.dart
git commit -m "feat(sp1): auth-aware MapScreen top-right icon and tap handlers"
```

---

### Task 5: Rewrite `test/widget_test.dart` for the new routing

**Files:**
- Modify: `test/widget_test.dart`

- [ ] **Step 1: Replace both tests**

Open `test/widget_test.dart` and replace the whole `void main()` body. Replace:

```dart
void main() {
  // Initialize dotenv before running tests
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Load test environment variables or use empty config
    dotenv.loadFromString(
      envString: '''
MAPTILER_API_KEY=test_key
''',
    );
  });

  testWidgets('App launches and shows CCW Map title when authenticated', (
    WidgetTester tester,
  ) async {
    // ...existing body...
  });

  testWidgets('App shows login screen when not authenticated', (
    WidgetTester tester,
  ) async {
    // ...existing body...
  });
}
```

With:

```dart
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    dotenv.loadFromString(
      envString: '''
MAPTILER_API_KEY=test_key
''',
    );
  });

  testWidgets('App launches as guest: map visible and sign-in icon present',
      (WidgetTester tester) async {
    final testDatabase = AppDatabase.forTesting(NativeDatabase.memory());
    final fakeNetworkMonitor = FakeNetworkMonitor();

    final pinRepository = PinRepositoryImpl(
      testDatabase.pinDao,
      testDatabase.syncQueueDao,
      testDatabase.pinTombstoneDao,
    );
    final authRepository = FakeAuthRepository();

    final mapViewModel = MapViewModel(pinRepository, fakeNetworkMonitor);
    final authViewModel = AuthViewModel(authRepository);

    // No setCurrentUser — user is unauthenticated.

    await tester.pumpWidget(
      CCWMapApp(mapViewModel: mapViewModel, authViewModel: authViewModel),
    );
    await tester.pumpAndSettle();

    // Map title always renders (visible to everyone).
    expect(find.text('CCW Map'), findsOneWidget);

    // Guest sees the sign-in icon, NOT the exit-to-app icon.
    expect(find.byIcon(Icons.login), findsOneWidget);
    expect(find.byIcon(Icons.exit_to_app), findsNothing);

    // Re-center FAB still present.
    expect(find.byIcon(Icons.my_location), findsOneWidget);

    authRepository.dispose();
    fakeNetworkMonitor.dispose();
    await testDatabase.close();
  });

  testWidgets(
    'App launches authenticated: map visible and sign-out icon present',
    (WidgetTester tester) async {
      final testDatabase = AppDatabase.forTesting(NativeDatabase.memory());
      final fakeNetworkMonitor = FakeNetworkMonitor();

      final pinRepository = PinRepositoryImpl(
        testDatabase.pinDao,
        testDatabase.syncQueueDao,
        testDatabase.pinTombstoneDao,
      );
      final authRepository = FakeAuthRepository();

      final mapViewModel = MapViewModel(pinRepository, fakeNetworkMonitor);
      final authViewModel = AuthViewModel(authRepository);

      authRepository.setCurrentUser(
        User(id: 'test-user-id', email: 'test@example.com'),
      );

      await tester.pumpWidget(
        CCWMapApp(mapViewModel: mapViewModel, authViewModel: authViewModel),
      );
      await tester.pumpAndSettle();

      expect(find.text('CCW Map'), findsOneWidget);

      // Authenticated user sees the exit (sign-out) icon, NOT sign-in.
      expect(find.byIcon(Icons.exit_to_app), findsOneWidget);
      expect(find.byIcon(Icons.login), findsNothing);

      expect(find.byIcon(Icons.my_location), findsOneWidget);

      authRepository.dispose();
      fakeNetworkMonitor.dispose();
      await testDatabase.close();
    },
  );
}
```

- [ ] **Step 2: Run both tests**

Run: `flutter test test/widget_test.dart`
Expected: both tests PASS.

- [ ] **Step 3: Run the full test suite**

Run: `flutter test`
Expected: all tests pass (the full suite should be green again).

- [ ] **Step 4: Commit**

```bash
git add test/widget_test.dart
git commit -m "test(sp1): update root widget tests for auth-aware MapScreen"
```

---

### Task 6: Analyze and format

**Files:**
- (none; verification-only)

- [ ] **Step 1: Static analysis**

Run: `flutter analyze`
Expected: no issues. If any warning about unused imports in `lib/main.dart` (e.g. `LoginScreen` if no longer referenced there) appears, remove the unused import.

- [ ] **Step 2: Format**

Run: `dart format lib/ test/`
Expected: "Formatted N files (M changed)". Stage any formatted files.

- [ ] **Step 3: Commit (only if formatter made changes)**

```bash
git add -u
git commit -m "style(sp1): dart format"
```

Skip this commit if `dart format` produced no changes.

---

### Task 7: Manual smoke test on Windows (Android emulator or web)

**Files:**
- (none; manual verification)

- [ ] **Step 1: Run the app without authenticating**

Run: `flutter run -d chrome` (or an attached Android device/emulator).

Confirm:
- Map tiles load; pins render; sign-in icon visible top-right.
- Tap a visible pin → read-only `PinDialog` opens; "Sign in to edit" closes it and opens the `SignInPromptSheet`; "Close" dismisses.
- Tap the top-right sign-in icon → `SignInPromptSheet` opens; "Cancel" dismisses.
- Tap the sign-in icon → Sign In → `LoginScreen` pushes; back button returns to the map.
- Long-press empty area → `SignInPromptSheet` (title: "Sign in to add pins").

- [ ] **Step 2: Sign in and verify authenticated flow is unchanged**

Use the app's existing sign-in flow to authenticate, then confirm:
- Top-right icon is now the exit-door (sign-out) icon.
- Tap a pin → edit dialog opens (writable, has Save/Delete).
- Long-press empty area → create dialog opens.
- Tap the exit icon → sign-out confirmation dialog → signing out returns to guest state (map still visible, icon flips back to sign-in). This validates that the removed `AuthGate` no longer forces a navigation.

- [ ] **Step 3: Do NOT commit anything**

This task is manual verification only. If a defect is found, file a follow-up — do not edit within this task's commits.

---

### Task 8: Update CLAUDE.md status

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update the implementation checklist**

Find in `CLAUDE.md`:

```markdown
### What's Implemented (Iterations 1-7)
- ✅ Clean Architecture setup (Domain, Data, Presentation layers)
- ✅ Local SQLite database with Drift ORM (native) + in-memory (web)
- ✅ MapLibre integration with circle-based pin markers
- ✅ Location services and user positioning
- ✅ Supabase authentication (email/password) with secure session storage
- ✅ Deep linking support for email confirmation
- ✅ Complete Pin CRUD operations (Create, Read, Update, Delete)
- ✅ US boundary validation
- ✅ Pin dialogs with color-coded status and restriction tags
- ✅ Web pin click detection (dual-detection system)
- ✅ 109/109 tests passing (100% success rate)
```

Replace with:

```markdown
### What's Implemented (Iterations 1-7 + v0.4.0 SP-1)
- ✅ Clean Architecture setup (Domain, Data, Presentation layers)
- ✅ Local SQLite database with Drift ORM (native) + in-memory (web)
- ✅ MapLibre integration with circle-based pin markers
- ✅ Location services and user positioning
- ✅ Supabase authentication (email/password) with secure session storage
- ✅ Deep linking support for email confirmation
- ✅ Complete Pin CRUD operations (Create, Read, Update, Delete)
- ✅ US boundary validation
- ✅ Pin dialogs with color-coded status and restriction tags
- ✅ Web pin click detection (dual-detection system)
- ✅ Anonymous map access — map visible to guests; auth required only for create/edit/delete
- ✅ Tests passing (count updated after SP-1 changes; run `flutter test` for current tally)
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(sp1): mark anonymous map access as implemented"
```

---

## Self-Review Checklist

- [ ] `SignInPromptSheet` renders and navigates to `LoginScreen` on both action buttons (Task 1).
- [ ] `PinDialog.isReadOnly` disables fields and swaps buttons; asserts `onSignInToEdit` required when read-only (Task 2).
- [ ] `AuthGate` is deleted; `_AppRoot` preserves deep-link and auth-init behavior without gating routing (Task 3).
- [ ] All three tap entry points (feature tap, map click → POI, map click → near-pin, long-press) branch on `AuthViewModel.isAuthenticated` (Task 4).
- [ ] Top-right icon flips between `Icons.login` and `Icons.exit_to_app` per auth state (Task 4, Step 7).
- [ ] `test/widget_test.dart` covers both guest and authenticated launch paths (Task 5).
- [ ] `flutter analyze` and `flutter test` both clean (Task 6).
- [ ] Manual smoke test of guest + authenticated flows completed (Task 7).

## Verification

Final gate before handing off to SP-2:

```bash
flutter analyze
flutter test
```

Both must be clean. Then push the branch and move to SP-2.

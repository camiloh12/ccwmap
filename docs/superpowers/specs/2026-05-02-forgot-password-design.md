# Forgot Password + Auth-Screen Redesign — Design Spec

**Date:** 2026-05-02
**Branch:** `feature/forgot-login`
**Status:** Approved, ready for implementation plan

## Goal

Two related changes shipped together:

1. **Forgot password.** Allow a signed-out user who has forgotten their password to recover access through a self-service email-based reset flow. The user enters their email, receives a reset link, taps it on their phone, sets a new password in the app, and lands back in the app signed in with the new password.
2. **Split the combined login/signup screen.** The current `LoginScreen` hosts both flows in one form with two buttons and an EULA checkbox that only matters for signup, which is confusing. Split into a sign-in-only `LoginScreen` and a new `SignUpScreen`, and add a confirm-password field to signup so it matches the new reset-password screen.

## Non-goals

- Changing password from inside the app while already signed in (settings-driven password change is out of scope).
- SMS / phone-based recovery.
- Recovery questions, hardware keys, or any non-email factor.
- Re-prompting users for a new password on subsequent app launches if they closed the app mid-recovery.
- Reworking the EULA modal flow, the passive first-launch acceptance, or the retroactive-blocking modal — only the inline checkbox on the auth form moves.
- Visual redesign / theming of the auth screens beyond the structural split.

## User flow

```
SignInPromptSheet ──push──► LoginScreen
                              │   email + password + "Sign In"
                              │
                              ├─ "Forgot password?" ──push──► ForgotPasswordScreen
                              │                                 │  enters email, taps
                              │                                 │  "Send reset link"
                              │                                 │  ──► resetPasswordForEmail(...)
                              │                                 ▼
                              │                               Success state ("If an account
                              │                               exists for X, we sent a reset
                              │                               link. Check inbox / spam.")
                              │                                 │  taps "Back to sign in"
                              │                                 ▼
                              │                               (pop) → LoginScreen
                              │
                              └─ "Sign up" ────────push──► SignUpScreen
                                                              │  email + password + confirm
                                                              │  + EULA checkbox + "Create
                                                              │  Account"
                                                              │  ──► signUpWithEmail(...)
                                                              │  → snackbar "Check email"
                                                              ▼
                                                            (auto-pop on auth-state change)
                                                            → LoginScreen → MapScreen

  ── separately: user opens email on phone, taps reset link ──►
     web: GitHub Pages page (recovery copy) ──redirect──►
     deep link: com.ccwmap.app://auth/callback?token_hash=...&type=recovery
       │
       ▼
  _AppRoot deep-link listener ──► AuthRepository.handleDeepLink
       │  verifyOTP(type: recovery, tokenHash) → fires AuthChangeEvent.passwordRecovery
       ▼
  ResetPasswordScreen (pushed automatically on passwordRecovery event)
       │  enters new password + confirm, taps "Update password"
       │  ──► supabase.auth.updateUser(password: newPassword)
       ▼
  Pop back to MapScreen (now signed in with new password)
```

## Architecture

### New files

- `lib/presentation/screens/forgot_password_screen.dart` — email entry + success state
- `lib/presentation/screens/reset_password_screen.dart` — new password + confirm
- `lib/presentation/screens/sign_up_screen.dart` — signup-only (split out of LoginScreen)
- `test/presentation/screens/forgot_password_screen_test.dart`
- `test/presentation/screens/reset_password_screen_test.dart`
- `test/presentation/screens/sign_up_screen_test.dart`
- `test/presentation/viewmodels/auth_viewmodel_password_reset_test.dart` — sits alongside the existing per-feature `auth_viewmodel_delete_test.dart`

### Modified files

- `lib/domain/repositories/auth_repository.dart` — add `sendPasswordResetEmail`, `updatePassword`, `passwordRecoveryEvents`
- `lib/data/repositories/supabase_auth_repository.dart` — implement the three methods; subscribe to underlying Supabase auth stream and surface `AuthChangeEvent.passwordRecovery`
- `lib/presentation/viewmodels/auth_viewmodel.dart` — add `sendPasswordReset`, `updatePassword`, `isInPasswordRecovery`, `clearRecoveryState`; extend `_formatAuthError` for new error cases; subscribe to repository's recovery stream
- `lib/presentation/screens/login_screen.dart` — strip out signup logic, EULA checkbox, and the "Create Account" button; relax password validator (no min-length on sign-in); add "Forgot password?" link below the password field; add "Don't have an account? Sign up" footer link that pushes `SignUpScreen`
- `lib/main.dart` — `_AppRoot` watches `auth.isInPasswordRecovery` and pushes `ResetPasswordScreen` (modal route, back-button blocked via `PopScope`); also surfaces `auth.error` as a `SnackBar` for the recovery-link-expiry path
- `test/fakes/fake_auth_repository.dart` — implement new interface methods + recovery stream controller + `sendShouldThrow` / `updateShouldThrow` toggles
- `docs/auth/callback/index.html` — branch on `?type` so recovery flows render "Reset Your Password" copy instead of "Email Confirmed!"
- `test/presentation/screens/login_screen_test.dart` — update to assert the screen no longer shows EULA / signup affordances and to cover the new "Forgot password?" / "Sign up" footer links

### Repository interface additions (`AuthRepository`)

```dart
/// Sends a password reset email. Always succeeds-looking from the caller's
/// perspective even when the email is unregistered (Supabase prevents
/// enumeration). Throws on network/transport errors only.
Future<void> sendPasswordResetEmail(String email);

/// Updates the password for the user in the current recovery session.
/// Must only be called while [AuthViewModel.isInPasswordRecovery] is true.
/// Throws AuthException on weak password, expired session, etc.
Future<void> updatePassword(String newPassword);

/// Stream that emits whenever the underlying auth provider signals that the
/// session was created via a password-recovery flow. The viewmodel uses
/// this to flag the session as recovery-mode and route to the reset screen.
Stream<void> passwordRecoveryEvents();
```

### ViewModel additions (`AuthViewModel`)

```dart
bool _isInPasswordRecovery = false;
bool get isInPasswordRecovery => _isInPasswordRecovery;

Future<void> sendPasswordReset(String email);   // mirrors signIn pattern
Future<void> updatePassword(String newPassword); // clears recovery flag on success
void clearRecoveryState();                       // for cancel / sign-out paths
```

The recovery flag is set inside the existing `initialize()`-installed listener — when the repository's `passwordRecoveryEvents` stream emits, set the flag and `notifyListeners`. Cleared on successful `updatePassword` or explicit cancellation.

### Why a separate flag instead of richer auth state

The recovery session is a real Supabase session — `currentUser` is non-null and `isAuthenticated` is true. Without a separate signal, `_AppRoot` cannot distinguish a recovery callback from a normal sign-in. We chose a one-shot flag (set on event, cleared on completion) over replacing `Stream<User?>` with a richer event type because:
- Only `AuthViewModel` consumes the recovery signal — every other consumer of the auth stream still wants a plain `User?`.
- A richer event type would force every existing caller to switch over a sealed class for one new use case. YAGNI.

## Deep-link handling

`handleDeepLink` already handles `type=recovery` correctly — `OtpType.values.firstWhere((t) => t.name == 'recovery')` resolves to `OtpType.recovery`, and `verifyOTP` establishes the recovery session. No change needed in the URI-parsing path.

The new wiring is:
1. `SupabaseAuthRepository` constructor subscribes to `_supabase.auth.onAuthStateChange` (separate from the existing per-call `authStateChanges` mapping) and exposes a broadcast stream that emits when `state.event == AuthChangeEvent.passwordRecovery`.
2. `AuthViewModel.initialize` subscribes to this stream and sets `_isInPasswordRecovery = true`.
3. `_AppRoot.build` watches the flag (via `context.watch<AuthViewModel>()`) and pushes `ResetPasswordScreen` via `Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(...))`. The screen wraps its body in `PopScope(canPop: false, ...)` so OS back / swipe-back gestures cannot dismiss it — only the in-app Cancel button (which calls `signOut` + `clearRecoveryState`) or successful `updatePassword` can pop the route.
4. After `updatePassword` succeeds, the viewmodel clears `isInPasswordRecovery`. The screen detects the success via the awaited future return and explicitly pops itself; `_AppRoot` does not double-pop because the flag has already been cleared.

## Web fallback page

`docs/auth/callback/index.html` updates:
- Read `?type` early in the script.
- Branch the rendered DOM:
  - `type === 'recovery'`: heading "Reset Your Password", body "Open this email on the device where CCW Map is installed and tap the link there to set a new password." Auto-redirect to deep link still happens on mobile UA.
  - `type === 'signup'` or fallback: existing "Email Confirmed!" copy unchanged.
- The deep-link construction lower in the script already propagates `type`, so no change there.

`resetPasswordForEmail` uses redirect URL `https://camiloh12.github.io/ccwmap/auth/callback` — the URL already configured in Supabase Auth → Redirect URLs for signup confirmations. No new URL to register.

## Auth-screen redesign (login / signup split)

### Why split

The current `LoginScreen` hosts both flows in one form with two action buttons ("Sign In" and "Create Account") and an EULA checkbox that only matters for one of them. Symptoms:
- The EULA checkbox is rendered for sign-in users who have already accepted (unnecessary noise) and gates the wrong button only conditionally.
- The shared password validator enforces a 6-char minimum on sign-in, which would falsely reject legacy accounts whose passwords don't meet current rules.
- "Two primary buttons on one form" is the classic flow-confusion anti-pattern.

We split into two dedicated screens, mirroring the dedicated-screen approach we already chose for `ForgotPasswordScreen` and `ResetPasswordScreen`.

### Navigation

```
SignInPromptSheet ──push──► LoginScreen
                              ├─ "Forgot password?" ──push──► ForgotPasswordScreen
                              └─ "Sign up" ──push──► SignUpScreen
                                                      └─ "Already have an account? Sign in" ── pop ──► back
```

`SignUpScreen` is reachable only by pushing on top of `LoginScreen`. After a successful signup the auto-pop-on-auth-state-change pattern unwinds both screens back to `MapScreen` cleanly. The same auto-pop runs on `LoginScreen` after a successful sign-in.

### `LoginScreen` (sign-in only) — what stays / what changes

Stays:
- App icon, title ("CCW Map"), subtitle
- Email field + email-format validator
- Password field with show/hide eye toggle
- Auto-pop on `isAuthenticated` flip (existing pattern)
- Error banner (red-bordered container)

Changes:
- **Password validator**: drop the 6-char minimum — sign-in accepts whatever the user types and lets the server reject it. Keeps legacy accounts working and avoids client-side rejection of correct-but-old passwords.
- **Add** "Forgot password?" `TextButton`, right-aligned in an `Align` widget directly below the password field. Disabled while `isLoading`. Pushes `ForgotPasswordScreen`.
- **Remove** the EULA checkbox row and `_eulaChecked` state.
- **Remove** the "Create Account" `OutlinedButton` and `_handleSignUp` logic.
- **Add** footer row at the bottom: a `TextButton` reading "Don't have an account? Sign up" that pushes `SignUpScreen`. Disabled while `isLoading`.

### `SignUpScreen` (new) — composition

- AppBar with back button, title "Create Account"
- App icon + small tagline (matches LoginScreen visual rhythm)
- Email field + email-format validator (same regex as LoginScreen)
- Password field with show/hide eye toggle, validator: ≥6 chars
- **Confirm-password field** with show/hide eye toggle, validator: must equal the password field's current value (compared via the password `TextEditingController` reference — same pattern as `ResetPasswordScreen`)
- EULA checkbox row identical to today's wording, with the same `_openTermsUrl` helper (lifted into a small shared util or duplicated — implementation detail for the plan)
- "Create Account" `ElevatedButton` (primary) — disabled until `isLoading || !_eulaChecked`
- Error banner same pattern as other auth screens
- Footer: "Already have an account? Sign in" `TextButton` that pops the route
- Auto-pop on `isAuthenticated` flip — same `Consumer<AuthViewModel>` + `addPostFrameCallback` pattern that `LoginScreen` uses today, copied to `SignUpScreen`. After signup completes, `SignUpScreen` pops first (closing itself), then `LoginScreen`'s own auto-pop fires for the same auth flip and unwinds back to `MapScreen`.
- Post-signup behavior unchanged from today's `_handleSignUp`: record agreement acceptance via `AgreementsRepository.recordAgreementAcceptance`, show "Account created! Check your email to confirm." snackbar via the app-level `ScaffoldMessenger` so it survives the pop

### `_openTermsUrl` duplication

`LoginScreen._openTermsUrl` is currently a private method. After the split, only `SignUpScreen` needs it (and the existing `EulaModal`, which already has its own copy via `onReadTerms`). Two options for the plan:
- Move it to a small shared helper (e.g., `lib/presentation/utils/terms_url.dart`)
- Inline the 4-line method into `SignUpScreen` and delete from `LoginScreen`

Either is fine; pick when writing the plan. Lean toward the small helper to avoid duplication.

## UI details

### `ForgotPasswordScreen`
- AppBar with back button, title "Reset Password"
- Single email field (validated with the same regex as `LoginScreen`)
- "Send reset link" elevated button
- After successful submit: replace the form with a success view ("If an account exists for `<email>`, we've sent a reset link. Check your inbox and spam folder.") and a "Back to sign in" outlined button that pops the route.
- Error banner reuses the red-bordered error container pattern from `LoginScreen`.

### `ResetPasswordScreen`
- Body wrapped in `PopScope(canPop: false, ...)` — OS back/swipe cannot dismiss
- AppBar title "Set New Password", `automaticallyImplyLeading: false`, with a Cancel text button as the AppBar action that triggers `signOut` + `clearRecoveryState` (and pops the route)
- Two password fields with show/hide eye toggles, both required, same min-length validator (≥6 chars)
- Confirm-password field validator: must equal the new-password field
- "Update password" elevated button
- On success: pop to map (no extra confirmation needed — the `MapScreen` will show the now-authenticated state)
- Error banner same pattern as other auth screens

## Error handling & edge cases

### `_formatAuthError` additions
- `'rate limit'` / `'over_email_send_rate_limit'` → "Too many reset requests. Please wait a few minutes and try again."
- `'token has expired'` / `'otp_expired'` → "This reset link has expired. Request a new one."
- `'same password'` (Supabase emits when new == old) → "New password must differ from your current one."
- Weak password (server-side `<6` chars rejection) → "Password must be at least 6 characters." (matches existing copy.)

### Recovery-link expiry
`verifyOTP` throws inside `handleDeepLink` → `AuthViewModel.handleDeepLink` catches → `error` is set, `passwordRecovery` event never fires, `ResetPasswordScreen` is **not** pushed. The user lands on the map with an error banner. We add a `SnackBar` surface in `_AppRoot` so the error is unmissable in this flow (otherwise the existing banner UX may not be visible from the map).

### User cancels mid-reset
`ResetPasswordScreen`'s Cancel button calls `auth.signOut()` then `auth.clearRecoveryState()`. The recovery session is invalidated — the user cannot half-leave it active.

### Email-enumeration safety
`sendPasswordReset` shows the same success message regardless of whether the address is registered. Supabase already returns success-shaped responses for non-existent accounts; this is consistency rather than a new defense.

### Banned / suspended user attempts reset
Supabase still issues the recovery link; on `verifyOTP` the session creation can fail if the user is banned. Existing banned-user copy in `_formatAuthError` covers it without changes.

### Cold-start triggered by recovery deep link
`_AppRoot.initState` already processes `getInitialLink()` before subscribing to the runtime stream. The `passwordRecovery` event fires after `verifyOTP` completes; `_AppRoot.build` picks it up via `context.watch<AuthViewModel>()` and pushes `ResetPasswordScreen`. No special cold-start handling needed.

### Pre-existing recovery session on next launch
If the user closes the app mid-recovery without completing or signing out, Supabase's persisted session is a real session — they relaunch into `MapScreen` as authenticated. We do **not** re-show `ResetPasswordScreen`. The `passwordRecovery` event only fires once, at verification time. The user can use the app normally with the recovery session; if they want to update their password later they go through the forgot flow again.

## Testing

Following project targets: ViewModels 80%+, UI smoke tests, mappers/domain 100%.

### Unit tests — `AuthViewModel`
- `sendPasswordReset` calls repository with trimmed email; loading state toggled; error formatted on `AuthException`
- `updatePassword` success clears `isInPasswordRecovery` and notifies listeners
- Repository `passwordRecoveryEvents` emission sets `isInPasswordRecovery = true`
- `clearRecoveryState` resets the flag without triggering sign-out
- Error formatting cases: rate limit, expired token, same password, weak password

### Repository tests — `SupabaseAuthRepository`
- `sendPasswordResetEmail` calls `auth.resetPasswordForEmail` with the GitHub Pages redirect URL
- `updatePassword` calls `auth.updateUser` with `UserAttributes(password: ...)`
- `passwordRecoveryEvents` stream emits when underlying Supabase event is `AuthChangeEvent.passwordRecovery`
- Use the same mocking pattern as existing repository tests (or minimal stub if none exist).

### Widget tests
- `ForgotPasswordScreen`: empty email shows validation error; valid email + submit shows success state; error from VM shows red banner
- `ResetPasswordScreen`: mismatched passwords blocks submit; both valid + submit calls VM; cancel calls `signOut` + `clearRecoveryState`
- `LoginScreen`: "Forgot password?" link present and tappable, pushes `ForgotPasswordScreen`; "Sign up" footer link present, pushes `SignUpScreen`; EULA checkbox and "Create Account" button are no longer rendered; sign-in submits with a 5-character password (validates server-side, not client-side)
- `SignUpScreen`: empty email and password show validation errors; mismatched passwords block submit; "Create Account" button disabled until EULA checked; valid form + EULA + submit calls VM; "Sign in" footer link pops the route

### Fake updates
Extend `FakeAuthRepository` with `sendPasswordResetEmail`, `updatePassword`, recovery-event stream controller, and configurable failure toggles (`sendShouldThrow`, `updateShouldThrow`).

### Manual test plan (Android first per SP cadence)

**Auth-screen redesign**
1. From map, open `SignInPromptSheet` → tap to open `LoginScreen` → no EULA checkbox visible, no "Create Account" button visible
2. Tap "Sign up" footer link → `SignUpScreen` pushed
3. Submit empty form → email and password validation errors render
4. Enter mismatched passwords → "Create Account" stays disabled until EULA checked, then submit blocks with mismatch error
5. Enter matching passwords + check EULA + submit → success snackbar, both screens pop, user is on map signed in
6. Sign out, return to `LoginScreen`, tap "Already have an account? Sign in" footer of `SignUpScreen` → pops back to `LoginScreen`

**Forgot-password flow**
7. Tap "Forgot password?" on login → email-entry screen
8. Submit known email → success message
9. Open email link on phone → app opens → reset screen pushed
10. Mismatched passwords → submit blocked
11. Set valid new password → returned to map, signed in
12. Sign out, sign in with new password → succeeds
13. Tap an expired link (>1 hour old) → friendly expired-link error, not pushed to reset screen
14. Cancel mid-reset → returned to map as guest

### Test count impact
Adds ~15 unit + ~12 widget tests (~6 for new auth screens, ~6 for redesigned LoginScreen + new SignUpScreen). Current count is 109; expect ~135 after.

## Out of scope (deferred)

- Settings-driven password change while signed in.
- Session re-detection on relaunch — recovery flag is one-shot per `passwordRecovery` event.
- Adjusting the existing email confirmation copy or template.

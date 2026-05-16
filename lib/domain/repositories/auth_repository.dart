import 'package:ccwmap/domain/models/user.dart';

/// Repository interface for authentication operations
abstract class AuthRepository {
  /// Gets the currently authenticated user, or null if not authenticated
  Future<User?> getCurrentUser();

  /// Stream of authentication state changes
  /// Emits User when signed in, null when signed out
  Stream<User?> authStateChanges();

  /// Signs up a new user with email and password
  /// Throws AuthException on error (e.g., email already exists)
  Future<void> signUpWithEmail(String email, String password);

  /// Signs in an existing user with email and password
  /// Throws AuthException on error (e.g., invalid credentials)
  Future<void> signInWithEmail(String email, String password);

  /// Signs out the current user
  Future<void> signOut();

  /// Handles deep link callback from OAuth/email confirmation
  /// Extracts tokens from URI and establishes session
  Future<void> handleDeepLink(Uri uri);

  /// Permanently deletes the currently-authenticated user's account.
  ///
  /// Calls the `delete-account` Supabase Edge Function, which verifies
  /// the caller's JWT and invokes `auth.admin.deleteUser` for that user.
  /// On success, local secure storage is cleared and the user is signed
  /// out.
  ///
  /// Throws on network error or if the server rejects the deletion.
  Future<void> deleteAccount();

  /// Sends a password reset email to [email]. Always succeeds-looking from
  /// the caller's perspective even when the email is unregistered (Supabase
  /// prevents enumeration). Throws on network/transport errors only.
  Future<void> sendPasswordResetEmail(String email);

  /// Updates the password for the user in the current recovery session.
  /// Must only be called while [AuthViewModel.isInPasswordRecovery] is true.
  /// Throws AuthException on weak password, expired session, etc.
  Future<void> updatePassword(String newPassword);

  /// Stream that emits whenever the underlying auth provider signals that
  /// the session was created via a password-recovery flow. The viewmodel
  /// uses this to flag the session as recovery-mode and route to the reset
  /// screen.
  Stream<void> passwordRecoveryEvents();
}

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
}

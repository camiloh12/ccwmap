import 'package:ccwmap/domain/models/user.dart' as domain;
import 'package:ccwmap/domain/repositories/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Supabase implementation of AuthRepository
class SupabaseAuthRepository implements AuthRepository {
  final supabase.SupabaseClient _supabase;

  SupabaseAuthRepository(this._supabase);

  /// Maps Supabase User to domain User model
  domain.User? _mapUser(supabase.User? supabaseUser) {
    if (supabaseUser == null) return null;

    return domain.User(
      id: supabaseUser.id,
      email: supabaseUser.email,
    );
  }

  @override
  Future<domain.User?> getCurrentUser() async {
    final supabaseUser = _supabase.auth.currentUser;
    return _mapUser(supabaseUser);
  }

  @override
  Stream<domain.User?> authStateChanges() {
    return _supabase.auth.onAuthStateChange.map((state) {
      return _mapUser(state.session?.user);
    });
  }

  @override
  Future<void> signUpWithEmail(String email, String password) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
      );

      if (response.user == null) {
        throw const supabase.AuthException('Sign up failed: No user returned');
      }
    } on supabase.AuthException {
      rethrow;
    } catch (e) {
      throw supabase.AuthException('Sign up failed: $e');
    }
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        throw const supabase.AuthException('Sign in failed: No user returned');
      }
    } on supabase.AuthException {
      rethrow;
    } catch (e) {
      throw supabase.AuthException('Sign in failed: $e');
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      throw supabase.AuthException('Sign out failed: $e');
    }
  }

  @override
  Future<void> handleDeepLink(Uri uri) async {
    try {
      // Extract tokens from URI fragment or query parameters
      // Supabase sends tokens in the fragment for security (#access_token=...)
      final fragment = uri.fragment;
      final queryParams = Uri.splitQueryString(fragment);

      if (queryParams.containsKey('access_token') &&
          queryParams.containsKey('refresh_token')) {
        await _supabase.auth.setSession(queryParams['access_token']!);
      } else {
        throw const supabase.AuthException('Invalid deep link: Missing tokens');
      }
    } on supabase.AuthException {
      rethrow;
    } catch (e) {
      throw supabase.AuthException('Deep link handling failed: $e');
    }
  }
}

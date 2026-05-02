import 'dart:async';

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

  /// Maps Supabase User to domain User model
  domain.User? _mapUser(supabase.User? supabaseUser) {
    if (supabaseUser == null) return null;

    return domain.User(id: supabaseUser.id, email: supabaseUser.email);
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
      // Check if this is a PKCE flow (token_hash in query params)
      final tokenHash = uri.queryParameters['token_hash'];
      final type = uri.queryParameters['type'];

      if (tokenHash != null && type != null) {
        // PKCE flow: verify OTP with token_hash
        await _supabase.auth.verifyOTP(
          type: supabase.OtpType.values.firstWhere(
            (t) => t.name == type,
            orElse: () => supabase.OtpType.email,
          ),
          tokenHash: tokenHash,
        );
      } else {
        // Implicit flow: extract tokens from hash fragment
        // This handles OAuth callbacks and legacy email confirmations
        await _supabase.auth.getSessionFromUrl(uri);
      }
    } on supabase.AuthException {
      rethrow;
    } catch (e) {
      throw supabase.AuthException('Deep link handling failed: $e');
    }
  }

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

  @override
  Future<void> deleteAccount() async {
    // Drain pending local writes first so we don't attempt uploads under
    // the soon-to-be-revoked JWT.
    try {
      await _syncManager?.sync();
    } catch (e) {
      debugPrint('SupabaseAuthRepository: pre-delete sync drain failed: $e');
      // Non-fatal: deleting an account with undelivered local writes is
      // acceptable. The local DB is cleared below.
    }

    // Call the Edge Function. invoke() automatically attaches the current
    // session's access token as the Authorization header.
    final resp = await _supabase.functions.invoke('delete-account');
    if (resp.status >= 400) {
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
}

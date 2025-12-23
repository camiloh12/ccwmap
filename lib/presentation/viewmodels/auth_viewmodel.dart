import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ccwmap/domain/models/user.dart';
import 'package:ccwmap/domain/repositories/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// ViewModel for authentication state and operations
class AuthViewModel extends ChangeNotifier {
  final AuthRepository _repository;
  StreamSubscription<User?>? _authSubscription;

  User? _currentUser;
  bool _isLoading = false;
  String? _error;

  AuthViewModel(this._repository);

  // Getters
  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _currentUser != null;

  /// Initialize the ViewModel and listen to auth state changes
  Future<void> initialize() async {
    debugPrint('AuthViewModel: Initializing...');

    // Get current user
    _currentUser = await _repository.getCurrentUser();

    // Listen to auth state changes
    _authSubscription = _repository.authStateChanges().listen(
      (user) {
        debugPrint('AuthViewModel: Auth state changed, user: ${user?.email}');
        _currentUser = user;
        notifyListeners();
      },
      onError: (error) {
        debugPrint('AuthViewModel: Auth state error: $error');
        _error = error.toString();
        notifyListeners();
      },
    );

    debugPrint('AuthViewModel: Initialization complete. User: ${_currentUser?.email}');
    notifyListeners();
  }

  /// Signs in with email and password
  Future<void> signIn(String email, String password) async {
    _setLoading(true);
    _clearError();

    try {
      debugPrint('AuthViewModel: Signing in user: $email');
      await _repository.signInWithEmail(email, password);
      debugPrint('AuthViewModel: Sign in successful');
    } on supabase.AuthException catch (e) {
      debugPrint('AuthViewModel: Sign in failed: ${e.message}');
      _error = _formatAuthError(e);
      notifyListeners();
    } catch (e) {
      debugPrint('AuthViewModel: Sign in error: $e');
      _error = 'Sign in failed. Please try again.';
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  /// Signs up a new user with email and password
  Future<void> signUp(String email, String password) async {
    _setLoading(true);
    _clearError();

    try {
      debugPrint('AuthViewModel: Signing up user: $email');
      await _repository.signUpWithEmail(email, password);
      debugPrint('AuthViewModel: Sign up successful. Check email for confirmation.');
      // Note: User may need to confirm email before they can sign in
    } on supabase.AuthException catch (e) {
      debugPrint('AuthViewModel: Sign up failed: ${e.message}');
      _error = _formatAuthError(e);
      notifyListeners();
    } catch (e) {
      debugPrint('AuthViewModel: Sign up error: $e');
      _error = 'Sign up failed. Please try again.';
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  /// Signs out the current user
  Future<void> signOut() async {
    _setLoading(true);
    _clearError();

    try {
      debugPrint('AuthViewModel: Signing out user');
      await _repository.signOut();
      debugPrint('AuthViewModel: Sign out successful');
    } on supabase.AuthException catch (e) {
      debugPrint('AuthViewModel: Sign out failed: ${e.message}');
      _error = _formatAuthError(e);
      notifyListeners();
    } catch (e) {
      debugPrint('AuthViewModel: Sign out error: $e');
      _error = 'Sign out failed. Please try again.';
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  /// Handles deep link callback from OAuth/email confirmation
  Future<void> handleDeepLink(Uri uri) async {
    debugPrint('AuthViewModel: Handling deep link: $uri');

    try {
      await _repository.handleDeepLink(uri);
      debugPrint('AuthViewModel: Deep link handled successfully');
    } on supabase.AuthException catch (e) {
      debugPrint('AuthViewModel: Deep link handling failed: ${e.message}');
      _error = _formatAuthError(e);
      notifyListeners();
    } catch (e) {
      debugPrint('AuthViewModel: Deep link error: $e');
      _error = 'Failed to process authentication link.';
      notifyListeners();
    }
  }

  /// Clears the current error message
  void clearError() {
    _clearError();
    notifyListeners();
  }

  // Private helpers

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
  }

  String _formatAuthError(supabase.AuthException e) {
    final message = e.message.toLowerCase();

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

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

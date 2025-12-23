import 'dart:async';
import 'package:ccwmap/domain/models/user.dart';
import 'package:ccwmap/domain/repositories/auth_repository.dart';

/// Fake AuthRepository for testing
/// Can be configured to simulate different auth states
class FakeAuthRepository implements AuthRepository {
  User? _currentUser;
  final StreamController<User?> _authStateController =
      StreamController<User?>.broadcast();

  /// Set the current user (simulates sign in)
  void setCurrentUser(User? user) {
    _currentUser = user;
    _authStateController.add(user);
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

  /// Clean up resources
  void dispose() {
    _authStateController.close();
  }
}

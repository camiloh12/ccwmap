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

  bool handleDeepLinkShouldThrow = false;
  Object handleDeepLinkThrownError =
      Exception('simulated deep link failure');
  int handleDeepLinkCallCount = 0;
  Uri? handleDeepLinkLastUri;

  @override
  Future<void> handleDeepLink(Uri uri) async {
    handleDeepLinkCallCount++;
    handleDeepLinkLastUri = uri;
    if (handleDeepLinkShouldThrow) {
      throw handleDeepLinkThrownError;
    }
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

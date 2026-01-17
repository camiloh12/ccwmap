/// Utility functions for user-friendly error messages
class ErrorMessages {
  /// Convert technical error messages to user-friendly ones
  static String getUserFriendlyMessage(String technicalError) {
    final error = technicalError.toLowerCase();

    // Authentication errors
    if (error.contains('invalid login credentials') ||
        error.contains('invalid_grant') ||
        error.contains('wrong password')) {
      return 'Invalid email or password. Please try again.';
    }

    if (error.contains('user already registered') ||
        error.contains('email already exists')) {
      return 'This email is already registered. Please sign in instead.';
    }

    if (error.contains('email not confirmed')) {
      return 'Please check your email and confirm your account before signing in.';
    }

    // Network errors
    if (error.contains('network') ||
        error.contains('connection') ||
        error.contains('timeout') ||
        error.contains('socket')) {
      return 'Network connection error. Please check your internet and try again.';
    }

    // Database errors
    if (error.contains('duplicate key') ||
        error.contains('unique constraint')) {
      return 'This item already exists.';
    }

    if (error.contains('foreign key')) {
      return 'Cannot perform this action due to related data.';
    }

    // Permission errors
    if (error.contains('permission') ||
        error.contains('unauthorized') ||
        error.contains('forbidden')) {
      return 'You don\'t have permission to perform this action.';
    }

    // Location errors
    if (error.contains('location') && error.contains('denied')) {
      return 'Location permission denied. Enable it in Settings to use this feature.';
    }

    if (error.contains('location') && error.contains('disabled')) {
      return 'Location services are disabled. Please enable them in Settings.';
    }

    // Validation errors
    if (error.contains('outside us') || error.contains('boundary')) {
      return 'Pins can only be created within the continental United States.';
    }

    // Generic errors
    if (error.contains('timeout')) {
      return 'Request timed out. Please try again.';
    }

    if (error.contains('server') || error.contains('500')) {
      return 'Server error. Please try again later.';
    }

    // If no specific match, return a generic friendly message
    return 'Something went wrong. Please try again.';
  }

  /// Get error title for dialogs based on error type
  static String getErrorTitle(String technicalError) {
    final error = technicalError.toLowerCase();

    if (error.contains('network') || error.contains('connection')) {
      return 'Connection Error';
    }

    if (error.contains('permission') || error.contains('unauthorized')) {
      return 'Permission Denied';
    }

    if (error.contains('validation') || error.contains('invalid')) {
      return 'Invalid Input';
    }

    return 'Error';
  }

  /// Check if error should show a "Try Again" button
  static bool canRetry(String technicalError) {
    final error = technicalError.toLowerCase();

    // Can retry network and server errors
    if (error.contains('network') ||
        error.contains('connection') ||
        error.contains('timeout') ||
        error.contains('server')) {
      return true;
    }

    // Cannot retry validation and permission errors
    return false;
  }
}

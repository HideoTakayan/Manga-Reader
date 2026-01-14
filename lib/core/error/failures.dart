/// Core error types for the application
/// Based on Clean Architecture failure pattern

sealed class Failure {
  final String message;
  const Failure(this.message);

  @override
  String toString() => message;
}

/// Network-related failures (API calls, connectivity)
class NetworkFailure extends Failure {
  const NetworkFailure([String message = 'Network error occurred']) : super(message);
}

/// Local storage failures (database, file system)
class StorageFailure extends Failure {
  const StorageFailure([String message = 'Storage error occurred']) : super(message);
}

/// Authentication failures
class AuthFailure extends Failure {
  const AuthFailure([String message = 'Authentication error occurred']) : super(message);
}

/// Drive service failures
class DriveFailure extends Failure {
  const DriveFailure([String message = 'Google Drive error occurred']) : super(message);
}

/// Not found failures
class NotFoundFailure extends Failure {
  const NotFoundFailure([String message = 'Resource not found']) : super(message);
}

/// Unexpected/unknown failures
class UnknownFailure extends Failure {
  final Object? error;
  const UnknownFailure([String message = 'An unexpected error occurred', this.error]) : super(message);
}

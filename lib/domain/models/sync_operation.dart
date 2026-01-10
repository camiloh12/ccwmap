/// Represents a type of sync operation
enum SyncOperationType {
  create,
  update,
  delete;

  /// Convert to string for storage
  String toStorageString() {
    return name.toUpperCase();
  }

  /// Parse from storage string
  static SyncOperationType fromStorageString(String value) {
    switch (value.toLowerCase()) {
      case 'create':
        return SyncOperationType.create;
      case 'update':
        return SyncOperationType.update;
      case 'delete':
        return SyncOperationType.delete;
      default:
        throw ArgumentError('Invalid SyncOperationType: $value');
    }
  }
}

/// Represents a queued sync operation for offline-first architecture
class SyncOperation {
  /// Unique identifier for this sync operation
  final String id;

  /// ID of the pin this operation relates to
  final String pinId;

  /// Type of operation (CREATE, UPDATE, DELETE)
  final SyncOperationType operationType;

  /// When this operation was created
  final DateTime timestamp;

  /// Number of times this operation has been retried
  final int retryCount;

  /// Error message from last failed attempt, if any
  final String? lastError;

  const SyncOperation({
    required this.id,
    required this.pinId,
    required this.operationType,
    required this.timestamp,
    this.retryCount = 0,
    this.lastError,
  });

  /// Create a copy with updated fields
  SyncOperation copyWith({
    String? id,
    String? pinId,
    SyncOperationType? operationType,
    DateTime? timestamp,
    int? retryCount,
    String? lastError,
  }) {
    return SyncOperation(
      id: id ?? this.id,
      pinId: pinId ?? this.pinId,
      operationType: operationType ?? this.operationType,
      timestamp: timestamp ?? this.timestamp,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
    );
  }

  /// Whether this operation has exceeded max retry attempts
  bool hasExceededMaxRetries({int maxRetries = 3}) {
    return retryCount >= maxRetries;
  }

  /// Calculate retry delay based on exponential backoff
  Duration getRetryDelay() {
    if (retryCount == 0) return Duration.zero;
    if (retryCount == 1) return const Duration(seconds: 2);
    if (retryCount == 2) return const Duration(seconds: 4);
    return const Duration(seconds: 8);
  }

  /// Whether enough time has passed to retry this operation
  bool canRetry() {
    if (retryCount == 0) return true;
    final delay = getRetryDelay();
    final nextRetryTime = timestamp.add(delay);
    return DateTime.now().isAfter(nextRetryTime);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is SyncOperation &&
        other.id == id &&
        other.pinId == pinId &&
        other.operationType == operationType &&
        other.timestamp == timestamp &&
        other.retryCount == retryCount &&
        other.lastError == lastError;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      pinId,
      operationType,
      timestamp,
      retryCount,
      lastError,
    );
  }

  @override
  String toString() {
    return 'SyncOperation(id: $id, pinId: $pinId, type: $operationType, '
        'retryCount: $retryCount, timestamp: $timestamp)';
  }
}

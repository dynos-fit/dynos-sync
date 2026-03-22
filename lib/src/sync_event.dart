import 'conflict_strategy.dart';
import 'sync_entry.dart';

/// Base class for all sync lifecycle events.
sealed class SyncEvent {
  /// Creates a [SyncEvent] with the given [timestamp].
  const SyncEvent({required this.timestamp});

  /// The time at which this event occurred.
  final DateTime timestamp;
}

/// Emitted when the local outbound queue has been fully drained.
class SyncDrainComplete extends SyncEvent {
  /// Creates a [SyncDrainComplete] event.
  const SyncDrainComplete({required super.timestamp});
}

/// Emitted when a pull operation for a table completes successfully.
class SyncPullComplete extends SyncEvent {
  /// Creates a [SyncPullComplete] event.
  const SyncPullComplete({
    required super.timestamp,
    required this.table,
    required this.rowCount,
  });

  /// The name of the table that was pulled.
  final String table;

  /// The number of rows received during the pull.
  final int rowCount;
}

/// Emitted when the remote server rejects the request due to authentication.
class SyncAuthRequired extends SyncEvent {
  /// Creates a [SyncAuthRequired] event.
  const SyncAuthRequired({required super.timestamp, required this.error});

  /// The underlying authentication error.
  final Object error;
}

/// Emitted when a conflict between local and remote data is detected and resolved.
class SyncConflict extends SyncEvent {
  /// Creates a [SyncConflict] event.
  const SyncConflict({
    required super.timestamp,
    required this.table,
    required this.recordId,
    required this.localVersion,
    required this.remoteVersion,
    required this.resolvedVersion,
    required this.strategyUsed,
  });

  /// The table in which the conflict occurred.
  final String table;

  /// The identifier of the conflicting record.
  final String recordId;

  /// The local version of the record before resolution.
  final Map<String, dynamic> localVersion;

  /// The remote version of the record before resolution.
  final Map<String, dynamic> remoteVersion;

  /// The final merged version of the record after resolution.
  final Map<String, dynamic> resolvedVersion;

  /// The conflict resolution strategy that was applied.
  final ConflictStrategy strategyUsed;
}

/// Emitted when a sync entry exceeds its maximum retry count and is discarded.
class SyncPoisonPill extends SyncEvent {
  /// Creates a [SyncPoisonPill] event.
  const SyncPoisonPill({required super.timestamp, required this.entry});

  /// The sync entry that was permanently discarded.
  final SyncEntry entry;
}

/// Emitted when a failed sync entry is scheduled for a later retry.
class SyncRetryScheduled extends SyncEvent {
  /// Creates a [SyncRetryScheduled] event.
  const SyncRetryScheduled({
    required super.timestamp,
    required this.entry,
    required this.nextRetryAt,
  });

  /// The sync entry that will be retried.
  final SyncEntry entry;

  /// The scheduled time for the next retry attempt.
  final DateTime nextRetryAt;
}

/// Emitted when an unexpected error occurs during a sync operation.
class SyncError extends SyncEvent {
  /// Creates a [SyncError] event.
  const SyncError({
    required super.timestamp,
    required this.error,
    required this.context,
  });

  /// The underlying error object.
  final Object error;

  /// A human-readable description of where the error occurred.
  final String context;
}

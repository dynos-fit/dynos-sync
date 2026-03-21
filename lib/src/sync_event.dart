import 'conflict_strategy.dart';
import 'sync_entry.dart';

/// Base class for all sync lifecycle events.
sealed class SyncEvent {
  const SyncEvent({required this.timestamp});
  final DateTime timestamp;
}

class SyncDrainComplete extends SyncEvent {
  const SyncDrainComplete({required super.timestamp});
}

class SyncPullComplete extends SyncEvent {
  const SyncPullComplete({
    required super.timestamp,
    required this.table,
    required this.rowCount,
  });
  final String table;
  final int rowCount;
}

class SyncAuthRequired extends SyncEvent {
  const SyncAuthRequired({required super.timestamp, required this.error});
  final Object error;
}

class SyncConflict extends SyncEvent {
  const SyncConflict({
    required super.timestamp,
    required this.table,
    required this.recordId,
    required this.localVersion,
    required this.remoteVersion,
    required this.resolvedVersion,
    required this.strategyUsed,
  });
  final String table;
  final String recordId;
  final Map<String, dynamic> localVersion;
  final Map<String, dynamic> remoteVersion;
  final Map<String, dynamic> resolvedVersion;
  final ConflictStrategy strategyUsed;
}

class SyncPoisonPill extends SyncEvent {
  const SyncPoisonPill({required super.timestamp, required this.entry});
  final SyncEntry entry;
}

class SyncRetryScheduled extends SyncEvent {
  const SyncRetryScheduled({
    required super.timestamp,
    required this.entry,
    required this.nextRetryAt,
  });
  final SyncEntry entry;
  final DateTime nextRetryAt;
}

class SyncError extends SyncEvent {
  const SyncError({
    required super.timestamp,
    required this.error,
    required this.context,
  });
  final Object error;
  final String context;
}

import 'conflict_strategy.dart';

/// Configuration for the sync engine.
class SyncConfig {
  const SyncConfig({
    this.batchSize = 50,
    this.queueRetention = const Duration(days: 30),
    this.stopOnFirstError = true,
    this.maxRetries = 3,
    this.sensitiveFields = const [],
    this.useExponentialBackoff = true,
    this.conflictStrategy = ConflictStrategy.lastWriteWins,
    this.onConflict,
    this.maxPayloadBytes = 1048576,
    this.maxBackoff = const Duration(seconds: 60),
  }) : assert(
          conflictStrategy != ConflictStrategy.custom || onConflict != null,
          'onConflict callback is required when conflictStrategy is custom',
        );

  /// Max number of pending entries to drain per cycle.
  final int batchSize;

  /// How long to keep synced entries before purging.
  final Duration queueRetention;

  /// If true, stop draining on the first push error (retry next cycle).
  /// If false, skip failed entries and continue.
  final bool stopOnFirstError;

  /// Maximum number of push retries before a pending entry is permanently dropped.
  final int maxRetries;

  /// Fields to mask in logs and telemetry (e.g. ['email', 'ssn']).
  final List<String> sensitiveFields;

  /// If true, uses exponential backoff (2^n) during retries.
  final bool useExponentialBackoff;

  /// Strategy for resolving conflicts when local and remote versions differ.
  final ConflictStrategy conflictStrategy;

  /// Callback for custom conflict resolution.
  /// Required when [conflictStrategy] is [ConflictStrategy.custom].
  final ConflictResolver? onConflict;

  /// Maximum payload size in bytes. Entries exceeding this are rejected.
  final int maxPayloadBytes;

  /// Maximum backoff duration between retries.
  final Duration maxBackoff;
}

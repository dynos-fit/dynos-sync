import 'sync_operation.dart';

/// A single queued sync operation waiting to be pushed to the remote.
class SyncEntry {
  /// Creates a [SyncEntry] with the given properties.
  const SyncEntry({
    required this.id,
    required this.table,
    required this.recordId,
    required this.operation,
    required this.payload,
    required this.createdAt,
    this.syncedAt,
    this.retryCount = 0,
    this.nextRetryAt,
  });

  /// Unique identifier for this sync entry.
  final String id;

  /// Name of the database table this entry targets.
  final String table;

  /// Identifier of the record being synced.
  final String recordId;

  /// The type of sync operation (create, update, delete).
  final SyncOperation operation;

  /// The data payload to be synced.
  final Map<String, dynamic> payload;

  /// Timestamp when this entry was created.
  final DateTime createdAt;

  /// Timestamp when this entry was successfully synced, or `null` if pending.
  final DateTime? syncedAt;

  /// Number of times this entry has been retried.
  final int retryCount;

  /// Scheduled time for the next retry attempt, or `null` if not scheduled.
  final DateTime? nextRetryAt;

  /// Whether this entry has not yet been synced.
  bool get isPending => syncedAt == null;

  /// Returns a copy of this entry with the given fields replaced.
  SyncEntry copyWith({
    String? id,
    String? table,
    String? recordId,
    SyncOperation? operation,
    Map<String, dynamic>? payload,
    DateTime? createdAt,
    DateTime? syncedAt,
    int? retryCount,
    DateTime? nextRetryAt,
  }) {
    return SyncEntry(
      id: id ?? this.id,
      table: table ?? this.table,
      recordId: recordId ?? this.recordId,
      operation: operation ?? this.operation,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
      retryCount: retryCount ?? this.retryCount,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
    );
  }
}

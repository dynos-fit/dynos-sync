import 'sync_operation.dart';

/// A single queued sync operation waiting to be pushed to the remote.
class SyncEntry {
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

  final String id;
  final String table;
  final String recordId;
  final SyncOperation operation;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime? syncedAt;
  final int retryCount;
  final DateTime? nextRetryAt;

  bool get isPending => syncedAt == null;

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

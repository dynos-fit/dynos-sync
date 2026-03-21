import 'package:drift/drift.dart';

/// Drift table definition for the sync queue.
///
/// Add this to your `@DriftDatabase(tables: [...])` annotation
/// to enable queue-based sync.
class DynosSyncQueueTable extends Table {
  @override
  String get tableName => 'dynos_sync_queue';

  /// Unique ID for this queue entry.
  TextColumn get id => text()();

  /// Target remote table name.
  TextColumn get tableName_ => text().named('table_name')();

  /// ID of the record to sync.
  TextColumn get recordId => text()();

  /// Operation type: 'upsert' or 'delete'.
  TextColumn get operation => text()();

  /// JSON-encoded payload to push.
  TextColumn get payload => text()();

  /// When this entry was created.
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// When this entry was successfully synced. Null = pending.
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

import 'package:drift/drift.dart';

/// Raw SQL to create the sync queue table.
///
/// Use this in your Drift migration if adding the [DynosSyncQueueTable]
/// class to `@DriftDatabase(tables: [...])` doesn't work cross-package:
///
/// ```dart
/// await customStatement(kSyncQueueCreateSql);
/// ```
const kSyncQueueCreateSql = '''
  CREATE TABLE IF NOT EXISTS dynos_sync_queue (
    id TEXT NOT NULL PRIMARY KEY,
    table_name TEXT NOT NULL,
    record_id TEXT NOT NULL,
    operation TEXT NOT NULL,
    payload TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    synced_at INTEGER,
    retry_count INTEGER NOT NULL DEFAULT 0,
    next_retry_at INTEGER
  )
''';

/// SQL to add the next_retry_at column to an existing sync queue table.
const kSyncQueueAddNextRetryAtSql =
    'ALTER TABLE dynos_sync_queue ADD COLUMN next_retry_at INTEGER';

/// Drift table definition for the sync queue.
///
/// Add this to your `@DriftDatabase(tables: [...])` annotation.
///
/// **Note:** Drift's code generator may not resolve this table when imported
/// from an external package. If you see "not understood by drift" warnings,
/// use [kSyncQueueCreateSql] in your migration instead.
class DynosSyncQueueTable extends Table {
  /// The underlying SQLite table name for the sync queue.
  @override
  String get tableName => 'dynos_sync_queue';

  /// Unique identifier for each queued sync entry.
  TextColumn get id => text()();

  /// The name of the table the queued record belongs to.
  TextColumn get tableName_ => text().named('table_name')();

  /// The primary-key value of the record being synced.
  TextColumn get recordId => text()();

  /// The sync operation type (e.g. upsert or delete).
  TextColumn get operation => text()();

  /// JSON-encoded payload of the record data.
  TextColumn get payload => text()();

  /// Timestamp when the entry was enqueued.
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Timestamp when the entry was successfully synced, or null if pending.
  DateTimeColumn get syncedAt => dateTime().nullable()();

  /// Number of times this entry has been retried.
  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  /// Earliest time at which a failed entry may be retried, or null if immediate.
  IntColumn get nextRetryAt => integer().nullable()();

  /// Uses [id] as the single-column primary key.
  @override
  Set<Column> get primaryKey => {id};
}

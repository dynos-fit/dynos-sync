import 'package:drift/drift.dart';

/// Drift table for storing per-table sync timestamps.
///
/// Add this to your `@DriftDatabase(tables: [...])` annotation
/// alongside [DynosSyncQueueTable].
class DynosSyncTimestampsTable extends Table {
  @override
  String get tableName => 'dynos_sync_timestamps';

  TextColumn get tableName_ => text().named('table_name')();
  DateTimeColumn get lastSyncedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {tableName_};
}

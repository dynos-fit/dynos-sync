import 'package:drift/drift.dart';
import 'package:dynos_sync/dynos_sync.dart';

/// [TimestampStore] implementation backed by a Drift [DynosSyncTimestampsTable].
///
/// Stores per-table sync timestamps in SQLite via the
/// `dynos_sync_timestamps` table.
class DriftTimestampStore implements TimestampStore {
  const DriftTimestampStore(this._db);

  final GeneratedDatabase _db;

  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  @override
  Future<DateTime> get(String table) async {
    final rows = await _db.customSelect(
      'SELECT last_synced_at FROM dynos_sync_timestamps WHERE table_name = ?',
      variables: [Variable.withString(table)],
    ).get();

    if (rows.isEmpty) return _epoch;
    return DateTime.fromMillisecondsSinceEpoch(
      rows.first.read<int>('last_synced_at'),
      isUtc: true,
    );
  }

  @override
  Future<void> set(String table, DateTime timestamp) async {
    await _db.customStatement(
      'INSERT OR REPLACE INTO dynos_sync_timestamps (table_name, last_synced_at) VALUES (?, ?)',
      [table, timestamp.toUtc().millisecondsSinceEpoch],
    );
  }
}

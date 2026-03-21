import 'package:drift/drift.dart';
import '../local_store.dart';

/// [LocalStore] implementation backed by a Drift database.
///
/// Uses raw SQL to upsert/delete records in any table, so it works
/// with any Drift database without requiring specific DAOs.
///
/// **Requirement:** Tables must have a column named `id` as the primary key.
class DriftLocalStore implements LocalStore {
  const DriftLocalStore(this._db);

  final GeneratedDatabase _db;

  @override
  Future<void> upsert(String table, String id, Map<String, dynamic> data) async {
    final columns = data.keys.toList();
    final placeholders = List.filled(columns.length, '?').join(', ');
    final values = data.values.toList();

    await _db.customStatement(
      'INSERT OR REPLACE INTO $table (${columns.join(', ')}) VALUES ($placeholders)',
      values,
    );
  }

  @override
  Future<void> delete(String table, String id) async {
    await _db.customStatement(
      'DELETE FROM $table WHERE id = ?',
      [id],
    );
  }
}

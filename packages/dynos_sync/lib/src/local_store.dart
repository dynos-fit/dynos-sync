/// Interface for the local database (Drift, Hive, Isar, raw SQLite, etc.).
///
/// Implement this to connect the sync engine to your local storage.
abstract class LocalStore {
  /// Insert or update a record in a local table.
  Future<void> upsert(String table, String id, Map<String, dynamic> data);

  /// Delete a record from a local table.
  Future<void> delete(String table, String id);
}

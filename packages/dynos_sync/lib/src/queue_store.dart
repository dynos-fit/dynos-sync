import 'sync_entry.dart';

/// Interface for the local sync queue storage.
///
/// The queue holds pending operations that need to be pushed to the remote.
/// Implement this with your local database, or use a provided adapter
/// (e.g., `sync_engine_drift`).
abstract class QueueStore {
  /// Add an entry to the sync queue.
  Future<void> enqueue(SyncEntry entry);

  /// Get pending (un-synced) entries, oldest first.
  Future<List<SyncEntry>> getPending({int limit = 50});

  /// Mark an entry as successfully synced.
  Future<void> markSynced(String id);

  /// Delete synced entries older than [retention].
  Future<void> purgeSynced({Duration retention = const Duration(days: 30)});
}

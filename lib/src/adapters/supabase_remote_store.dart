import 'package:supabase/supabase.dart';
import '../remote_store.dart';
import '../sync_exceptions.dart';
import '../sync_operation.dart';
import '../sync_entry.dart';

/// Fetches one pull page: [limit] rows starting at [offset], or the whole
/// window when [limit] is null.
typedef PullPageFetcher = Future<List<Map<String, dynamic>>> Function(
    int offset, int? limit);

/// Fetches the complete pull window in ascending `updated_at`, `id` order.
///
/// Public so a host store that overrides `pullSince` with its own filters,
/// RLS scoping or decryption can reuse this paging loop instead of duplicating
/// it — a second copy is a second place to fix a truncation bug.
///
/// When [pageSize] is null the window is fetched with a single unbounded
/// query. When set, pages are fetched until a short page ends the loop — on
/// the assumption that the server serves full pages; keep [pageSize] at or
/// below the API's max-rows setting so a server-side cap is not mistaken for
/// the end of the window.
///
/// Throws [SyncRemoteException] if a full page repeats its predecessor: an
/// offset-ignoring or range-clamped server would otherwise loop forever.
Future<List<Map<String, dynamic>>> fetchPullWindow(
  int? pageSize,
  PullPageFetcher fetch,
) async {
  if (pageSize == null) return fetch(0, null);
  final rows = <Map<String, dynamic>>[];
  var offset = 0;
  var previousHead = '';
  while (true) {
    final page = await fetch(offset, pageSize);
    rows.addAll(page);
    if (page.length < pageSize) break;
    final head = page.first.toString();
    if (head == previousHead) {
      throw SyncRemoteException(
        message:
            'pull window made no progress at offset $offset; '
            'keep pullPageSize at or below the API max-rows setting',
      );
    }
    previousHead = head;
    offset += pageSize;
  }
  return rows;
}

/// [RemoteStore] implementation using Supabase Postgrest.
///
/// Pushes records via `.upsert()` / `.update()` / `.delete()` and pulls via
/// `.select().gt('updated_at', since)` — paged in ascending `updated_at`, `id`
/// order when [SupabaseRemoteStore.pullPageSize] is set.
///
/// ## Smart Sync Gate
///
/// For the sync gate to work, your Supabase project needs a
/// `sync_status` table with one row per user and a `timestamptz` column
/// per synced table (e.g., `users_at`, `tasks_at`).
///
/// These columns should be maintained by Supabase triggers.
/// If you don't have a `sync_status` table, [getRemoteTimestamps] returns
/// an empty map and all tables will be pulled on every sync.
class SupabaseRemoteStore implements RemoteStore {
  /// Creates a Supabase remote store.
  ///
  /// - [client]: Your Supabase client instance.
  /// - [userId]: Callback that returns the current authenticated user's ID.
  ///   Called on every sync cycle so it stays fresh across sign-out/sign-in.
  /// - [syncStatusTable]: Name of the sync status table (default: `sync_status`).
  /// - [tableTimestampKeys]: Maps table names to their `sync_status` column names.
  ///   Example: `{'tasks': 'tasks_at', 'notes': 'notes_at'}`.
  /// - [pullPageSize]: Rows fetched per page during pulls. `null` (default)
  ///   issues one unbounded query; when set, [pullSince] pages in ascending
  ///   `updated_at`, `id` order until the window is exhausted. Keep it at or
  ///   below the project's API max-rows setting: a server-side cap makes a
  ///   truncated window look like a short final page, and the watermark then
  ///   advances past rows that were never fetched.
  const SupabaseRemoteStore({
    required this.client,
    required this.userId,
    this.syncStatusTable = 'sync_status',
    this.tableTimestampKeys = const {},
    this.pullPageSize,
  }) : assert(
          pullPageSize == null || pullPageSize > 0,
          'pullPageSize must be positive',
        );

  /// The Supabase client used for all remote operations.
  final SupabaseClient client;

  /// Returns the current user ID. Called per sync cycle to handle
  /// session expiry and account switches.
  final String Function() userId;

  /// The name of the Supabase table that tracks per-user sync timestamps.
  final String syncStatusTable;

  /// Maps synced table names to their corresponding timestamp column in [syncStatusTable].
  final Map<String, String> tableTimestampKeys;

  /// Rows fetched per page during pulls, or `null` for one unbounded query.
  final int? pullPageSize;

  @override
  Future<void> push(
    String table,
    String id,
    SyncOperation operation,
    Map<String, dynamic> data,
  ) async {
    try {
      switch (operation) {
        case SyncOperation.upsert:
          await client.from(table).upsert(data);
        case SyncOperation.delete:
          await client.from(table).delete().eq('id', id);
        case SyncOperation.patch:
          await client.from(table).update(data).eq('id', id);
      }
    } on AuthException catch (e) {
      throw AuthExpiredException(e);
    } catch (e) {
      if (_isAuthError(e)) throw AuthExpiredException(e);
      rethrow;
    }
  }

  @override
  Future<void> pushBatch(List<SyncEntry> entries) async {
    if (entries.isEmpty) return;

    // Group entries by table and operation
    final groups = <String, Map<SyncOperation, List<SyncEntry>>>{};
    for (final entry in entries) {
      final tableGroups = groups.putIfAbsent(entry.table, () => {});
      tableGroups.putIfAbsent(entry.operation, () => []).add(entry);
    }

    try {
      for (final tableEntry in groups.entries) {
        final tableName = tableEntry.key;
        final opsMap = tableEntry.value;

        // Batch Upserts
        final upserts = opsMap[SyncOperation.upsert];
        if (upserts != null && upserts.isNotEmpty) {
          final payloads = upserts.map((e) => e.payload).toList();
          await client.from(tableName).upsert(payloads);
        }

        // Batch Deletes
        final deletes = opsMap[SyncOperation.delete];
        if (deletes != null && deletes.isNotEmpty) {
          final ids = deletes.map((e) => e.recordId).toList();
          await client.from(tableName).delete().inFilter('id', ids);
        }

        // Batch Patches (individual updates — Supabase has no batch update)
        final patches = opsMap[SyncOperation.patch];
        if (patches != null && patches.isNotEmpty) {
          for (final entry in patches) {
            await client
                .from(tableName)
                .update(entry.payload)
                .eq('id', entry.recordId);
          }
        }
      }
    } on AuthException catch (e) {
      throw AuthExpiredException(e);
    } catch (e) {
      if (_isAuthError(e)) throw AuthExpiredException(e);
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> pullSince(
    String table,
    DateTime since,
  ) async {
    try {
      final rows = await fetchPullWindow(pullPageSize, (offset, limit) async {
        final query = client
            .from(table)
            .select()
            .gt('updated_at', since.toIso8601String())
            .order('updated_at', ascending: true)
            .order('id', ascending: true);
        return List<Map<String, dynamic>>.from(
          limit == null
              ? await query
              : await query.range(offset, offset + limit - 1),
        );
      });
      return rows;
    } on AuthException catch (e) {
      throw AuthExpiredException(e);
    } on FormatException catch (e) {
      throw SyncDeserializationException(e);
    } on TypeError catch (e) {
      throw SyncDeserializationException(e);
    } catch (e) {
      if (_isAuthError(e)) throw AuthExpiredException(e);
      rethrow;
    }
  }

  @override
  Future<Map<String, DateTime>> getRemoteTimestamps() async {
    if (tableTimestampKeys.isEmpty) return {};

    try {
      final rows =
          await client.from(syncStatusTable).select().eq('user_id', userId());

      if (rows.isEmpty) return {};

      final row = rows.first;
      final result = <String, DateTime>{};

      for (final entry in tableTimestampKeys.entries) {
        final value = row[entry.value];
        if (value != null) {
          result[entry.key] = DateTime.parse(value.toString()).toUtc();
        }
      }

      return result;
    } on AuthException catch (e) {
      throw AuthExpiredException(e);
    } catch (e) {
      if (_isAuthError(e)) throw AuthExpiredException(e);
      // Rethrow so SyncEngine can catch and route to onError,
      // avoiding a silent fallback to expensive full-syncs.
      rethrow;
    }
  }

  /// Heuristic check for auth errors that don't throw AuthException.
  /// Some Supabase errors surface as PostgrestException with status 401/403.
  bool _isAuthError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('401') ||
        msg.contains('403') ||
        msg.contains('jwt expired') ||
        msg.contains('invalid token') ||
        msg.contains('not authenticated');
  }
}

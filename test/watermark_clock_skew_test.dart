import 'package:test/test.dart';
import 'package:dynos_sync/dynos_sync.dart';

/// Regression test for the delta-watermark clock-skew bug.
///
/// `SyncEngine._pullTable` used to persist each table's watermark via
/// `timestamps.set(table, DateTime.now().toUtc())` — the *device* wall clock.
/// If the device clock runs ahead of the server, that future watermark makes
/// the next `pullSince`'s `updated_at > since` filter silently skip every row
/// the server commits in the gap: unbounded, permanent data loss.
///
/// The watermark must instead be derived from the newest *server* `updated_at`
/// actually observed in the pulled rows.

class _MemLocal implements LocalStore {
  final data = <String, Map<String, dynamic>>{};
  @override
  Future<void> upsert(String t, String id, Map<String, dynamic> r) async =>
      data['$t:$id'] = r;
  @override
  Future<void> delete(String t, String id) async => data.remove('$t:$id');
  @override
  Future<void> clearAll(List<String> t) async => data.clear();
}

class _NoopQueue implements QueueStore {
  @override
  Future<void> enqueue(SyncEntry e) async {}
  @override
  Future<List<SyncEntry>> getPending({int limit = 50, DateTime? now}) async =>
      const [];
  @override
  Future<bool> hasPending(String t, String id) async => false;
  @override
  Future<Set<String>> getPendingIds(String t) async => const {};
  @override
  Future<List<SyncEntry>> getPendingEntries(String t, String id) async =>
      const [];
  @override
  Future<void> markSynced(String id) async {}
  @override
  Future<void> incrementRetry(String id) async {}
  @override
  Future<void> setNextRetryAt(String id, DateTime at) async {}
  @override
  Future<void> deleteEntry(String id) async {}
  @override
  Future<void> purgeSynced({Duration retention = const Duration(days: 30)}) async {}
  @override
  Future<void> clearAll() async {}
}

class _MemTimestamps implements TimestampStore {
  final map = <String, DateTime>{};
  @override
  Future<DateTime> get(String t) async =>
      map[t] ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  @override
  Future<void> set(String t, DateTime ts) async => map[t] = ts;
}

/// Returns rows stamped with a fixed *server* `updated_at` well in the past,
/// and reports a remote sync-status timestamp so `pullAll` gates the table in.
class _ServerRemote implements RemoteStore {
  _ServerRemote(this.serverUpdatedAt);
  final DateTime serverUpdatedAt;

  @override
  Future<void> push(String t, String id, SyncOperation op,
      Map<String, dynamic> d) async {}
  @override
  Future<void> pushBatch(List<SyncEntry> e) async {}

  @override
  Future<List<Map<String, dynamic>>> pullSince(String t, DateTime since) async {
    // The server row is newer than `since` (epoch), so it is returned.
    return [
      {
        'id': 'row-1',
        'updated_at': serverUpdatedAt.toIso8601String(),
        'name': 'from server',
      },
    ];
  }

  @override
  Future<Map<String, DateTime>> getRemoteTimestamps() async =>
      {'tasks': serverUpdatedAt};
}

void main() {
  test('pull watermark is the server updated_at, never the device clock',
      () async {
    // Server committed the row on 2020-01-01 — far behind "now".
    final serverTs = DateTime.utc(2020, 1, 1, 12);
    final timestamps = _MemTimestamps();

    final engine = SyncEngine(
      local: _MemLocal(),
      remote: _ServerRemote(serverTs),
      queue: _NoopQueue(),
      timestamps: timestamps,
      tables: ['tasks'],
    );

    await engine.pullAll();

    final watermark = timestamps.map['tasks'];
    expect(watermark, isNotNull, reason: 'watermark must be advanced after a pull');

    // The fix: watermark equals the server row's updated_at.
    expect(watermark, equals(serverTs));

    // Guard against regression to the device clock: a device-clock watermark
    // would land in 2026+, decades after the server timestamp.
    expect(
      watermark!.isBefore(DateTime.utc(2020, 1, 2)),
      isTrue,
      reason: 'watermark must come from server time, not DateTime.now()',
    );
  });

  test('watermark is left unchanged when no row carries updated_at', () async {
    // A remote that returns a row with no parseable updated_at must not let the
    // engine guess now() — leaving the watermark lets the row re-pull safely.
    final timestamps = _MemTimestamps();
    timestamps.map['tasks'] = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    final engine = SyncEngine(
      local: _MemLocal(),
      remote: _NoUpdatedAtRemote(),
      queue: _NoopQueue(),
      timestamps: timestamps,
      tables: ['tasks'],
    );

    await engine.pullAll();

    expect(timestamps.map['tasks'],
        equals(DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)));
  });
}

class _NoUpdatedAtRemote implements RemoteStore {
  @override
  Future<void> push(String t, String id, SyncOperation op,
      Map<String, dynamic> d) async {}
  @override
  Future<void> pushBatch(List<SyncEntry> e) async {}
  @override
  Future<List<Map<String, dynamic>>> pullSince(String t, DateTime since) async =>
      [
        {'id': 'row-1', 'name': 'no timestamp'},
      ];
  @override
  Future<Map<String, DateTime>> getRemoteTimestamps() async =>
      {'tasks': DateTime.utc(2020, 6, 1)};
}

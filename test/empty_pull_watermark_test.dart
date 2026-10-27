import 'package:test/test.dart';
import 'package:dynos_sync/dynos_sync.dart';

/// Regression test for the empty-pull watermark bug (dynos-fit/dynos-sync#103).
///
/// `_pullTable` used to early-return on an empty `pullSince` without writing
/// the table watermark, so a legitimately-empty table kept its stale watermark
/// forever and was re-queried on every cycle. An empty pull must advance the
/// watermark to the gate cursor that triggered the pull — server-derived,
/// never the device wall clock.

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
  Future<void> purgeSynced({
    Duration retention = const Duration(days: 30),
  }) async {}
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

/// Returns zero rows for every pull and counts the queries.
class _EmptyRemote implements RemoteStore {
  _EmptyRemote(this.cursor);
  final DateTime? cursor;
  int pullCount = 0;

  @override
  Future<void> push(
    String t,
    String id,
    SyncOperation op,
    Map<String, dynamic> d,
  ) async {}
  @override
  Future<void> pushBatch(List<SyncEntry> e) async {}

  @override
  Future<List<Map<String, dynamic>>> pullSince(
    String t,
    DateTime since,
  ) async {
    pullCount++;
    return const [];
  }

  @override
  Future<Map<String, DateTime>> getRemoteTimestamps() async {
    final c = cursor;
    return c == null ? const {} : {'tasks': c};
  }
}

void main() {
  test('empty pull advances the watermark to the gate cursor', () async {
    final cursor = DateTime.utc(2020, 6, 1);
    final timestamps = _MemTimestamps();
    final remote = _EmptyRemote(cursor);

    final engine = SyncEngine(
      local: _MemLocal(),
      remote: remote,
      queue: _NoopQueue(),
      timestamps: timestamps,
      tables: ['tasks'],
    );

    await engine.pullAll();

    expect(
      timestamps.map['tasks'],
      equals(cursor),
      reason: 'the gate cursor is the server high-water mark',
    );
  });

  test('second pullAll skips the empty table at the gate', () async {
    final cursor = DateTime.utc(2020, 6, 1);
    final timestamps = _MemTimestamps();
    final remote = _EmptyRemote(cursor);

    final engine = SyncEngine(
      local: _MemLocal(),
      remote: remote,
      queue: _NoopQueue(),
      timestamps: timestamps,
      tables: ['tasks'],
    );

    await engine.pullAll();
    await engine.pullAll();

    expect(
      remote.pullCount,
      equals(1),
      reason: 'after the watermark advances, the gate must skip the table',
    );
  });

  test('no gate cursor: empty pull leaves the watermark unchanged', () async {
    final timestamps = _MemTimestamps();
    final remote = _EmptyRemote(null);

    final engine = SyncEngine(
      local: _MemLocal(),
      remote: remote,
      queue: _NoopQueue(),
      timestamps: timestamps,
      tables: ['tasks'],
    );

    await engine.pullAll();

    expect(
      timestamps.map['tasks'],
      isNull,
      reason: 'no server-derived mark exists; do not guess',
    );
  });

  test('empty pull never advances past a stale gate cursor', () async {
    // Stale watermark still ahead of the (replayed) gate cursor: monotonicity
    // must hold — no rewinding, no device-clock write.
    final stale = DateTime.utc(2030, 1, 1);
    final timestamps = _MemTimestamps();
    timestamps.map['tasks'] = stale;
    final remote = _EmptyRemote(DateTime.utc(2020, 6, 1));

    final engine = SyncEngine(
      local: _MemLocal(),
      remote: remote,
      queue: _NoopQueue(),
      timestamps: timestamps,
      tables: ['tasks'],
    );

    await engine.pullAll();

    expect(
      timestamps.map['tasks'],
      equals(stale),
      reason: 'the watermark must never move backwards',
    );
  });
}

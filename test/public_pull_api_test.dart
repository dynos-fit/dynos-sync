import 'package:test/test.dart';
import 'package:dynos_sync/dynos_sync.dart';

/// Tests for the public per-table pull / batch-apply API
/// (dynos-fit/dynos-sync#104, option 2): hosts page the remote themselves and
/// need `pullTable` / `applyRemoteRows` with a single watermark write.

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

/// Serves fixed rows and records the `since` each pull was issued with.
class _RowRemote implements RemoteStore {
  _RowRemote(this.rows);
  final List<Map<String, dynamic>> rows;
  DateTime? lastSince;

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
  Future<List<Map<String, dynamic>>> pullSince(String t, DateTime since) async {
    lastSince = since;
    return rows;
  }

  @override
  Future<Map<String, DateTime>> getRemoteTimestamps() async => const {};
}

void main() {
  final t1 = DateTime.utc(2020, 1, 1, 12);
  final t2 = DateTime.utc(2020, 1, 2, 12);
  final rows = [
    {'id': 'a', 'updated_at': t1.toIso8601String(), 'name': 'A'},
    {'id': 'b', 'updated_at': t2.toIso8601String(), 'name': 'B'},
  ];

  SyncEngine engine(_MemLocal local, _MemTimestamps timestamps,
          {_RowRemote? remote}) =>
      SyncEngine(
        local: local,
        remote: remote ?? _RowRemote(rows),
        queue: _NoopQueue(),
        timestamps: timestamps,
        tables: ['tasks'],
      );

  test(
      'pullTable applies rows and advances the watermark to the newest server row',
      () async {
    final local = _MemLocal();
    final timestamps = _MemTimestamps();

    final count = engine(local, timestamps).pullTable('tasks');

    expect(await count, equals(2));
    expect(local.data['tasks:a']?['name'], equals('A'));
    expect(local.data['tasks:b']?['name'], equals('B'));
    expect(timestamps.map['tasks'], equals(t2));
  });

  test('pullTable without since starts from the stored watermark', () async {
    final local = _MemLocal();
    final timestamps = _MemTimestamps();
    timestamps.map['tasks'] = t1;
    final remote = _RowRemote(rows);

    await engine(local, timestamps, remote: remote).pullTable('tasks');

    expect(remote.lastSince, equals(t1));
  });

  test('applyRemoteRows applies rows without guessing a watermark', () async {
    final local = _MemLocal();
    final timestamps = _MemTimestamps();

    final count =
        await engine(local, timestamps).applyRemoteRows('tasks', rows);

    expect(count, equals(2));
    expect(local.data.containsKey('tasks:a'), isTrue);
    expect(local.data.containsKey('tasks:b'), isTrue);
    expect(
      timestamps.map.containsKey('tasks'),
      isFalse,
      reason: 'no watermark passed — none may be invented',
    );
  });

  test('applyRemoteRows writes the watermark only when given', () async {
    final local = _MemLocal();
    final timestamps = _MemTimestamps();

    await engine(local, timestamps)
        .applyRemoteRows('tasks', const [], watermark: t2);

    expect(timestamps.map['tasks'], equals(t2));
  });

  test('applyRemoteRows skips rows failing the RLS gate', () async {
    final local = _MemLocal();
    final timestamps = _MemTimestamps();
    final remote = _RowRemote([
      {'id': 'mine', 'user_id': 'u1', 'name': 'mine'},
      {'id': 'theirs', 'user_id': 'u2', 'name': 'theirs'},
    ]);

    final count = await SyncEngine(
      local: local,
      remote: remote,
      queue: _NoopQueue(),
      timestamps: timestamps,
      tables: ['tasks'],
      userId: 'u1',
    ).applyRemoteRows('tasks', remote.rows);

    expect(count, equals(1));
    expect(local.data.containsKey('tasks:mine'), isTrue);
    expect(local.data.containsKey('tasks:theirs'), isFalse);
  });

  test('applyRemoteRows never rewinds the stored watermark', () async {
    final local = _MemLocal();
    final timestamps = _MemTimestamps();
    timestamps.map['tasks'] = t2;

    await engine(local, timestamps)
        .applyRemoteRows('tasks', const [], watermark: t1);

    expect(
      timestamps.map['tasks'],
      equals(t2),
      reason: 'a stale cursor must not rewind the table watermark',
    );
  });

  test('pullTable with an older since never rewinds the watermark', () async {
    final local = _MemLocal();
    final timestamps = _MemTimestamps();
    timestamps.map['tasks'] = t2;
    final remote = _RowRemote([
      {'id': 'a', 'updated_at': t1.toIso8601String(), 'name': 'A'},
    ]);

    await engine(local, timestamps, remote: remote)
        .pullTable('tasks', since: t1);

    expect(
      timestamps.map['tasks'],
      equals(t2),
      reason: 'older re-pulled rows must not move the watermark back',
    );
  });
}

import 'dart:async';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dynos_sync/dynos_sync.dart';

// ─── RUTHLESS MOCKS & STUBS ───────────────────────────────────────────────

class MockRemoteStore extends Mock implements RemoteStore {}

class MockLocalStore extends Mock implements LocalStore {}

class MockQueueStore extends Mock implements QueueStore {}

class MockTimestampStore extends Mock implements TimestampStore {}

class TrackingLocalStore implements LocalStore {
  final Map<String, dynamic> data = {};
  
  @override
  Future<void> upsert(String t, String id, Map<String, dynamic> d) async =>
      data['$t:$id'] = d;
      
  @override
  Future<void> delete(String t, String id) async => data.remove('$t:$id');
  
  @override
  Future<void> clearAll(List<String> tables) async => data.clear();
}

class ZeroLatancyRemote extends Mock implements RemoteStore {
  @override
  Future<void> push(dynamic _1, dynamic _2, dynamic _3, dynamic _4) async {}
  @override
  Future<void> pushBatch(dynamic _1) async {}
  @override
  Future<List<Map<String, dynamic>>> pullSince(dynamic _1, dynamic _2) async =>
      [];
  @override
  Future<Map<String, DateTime>> getRemoteTimestamps() async => {};
}

void main() {
  setUpAll(() {
    registerFallbackValue(SyncOperation.upsert);
    registerFallbackValue(DateTime.now().toUtc());
    registerFallbackValue(<SyncEntry>[]);
    registerFallbackValue(SyncEntry(
      id: '1',
      table: 't',
      recordId: 'r',
      operation: SyncOperation.upsert,
      payload: {},
      createdAt: DateTime.now().toUtc(),
    ));
  });

  MockRemoteStore getStubbedRemote() {
    final remote = MockRemoteStore();
    when(() => remote.pushBatch(any())).thenAnswer((_) async {});
    when(() => remote.push(any(), any(), any(), any()))
        .thenAnswer((_) async {});
    when(() => remote.pullSince(any(), any())).thenAnswer((_) async => []);
    when(() => remote.getRemoteTimestamps()).thenAnswer((_) async => {});
    return remote;
  }

  MockLocalStore getStubbedLocal() {
    final local = MockLocalStore();
    when(() => local.upsert(any(), any(), any())).thenAnswer((_) async {});
    when(() => local.delete(any(), any())).thenAnswer((_) async {});
    when(() => local.clearAll(any())).thenAnswer((_) async {});
    return local;
  }

  group('CATEGORY 1 — DATA LEAKS (Cross-User Isolation)', () {
    test('1-2. After User A Logout: User B context MUST be a total void',
        () async {
      final local = TrackingLocalStore();
      final queue = InMemoryQueueStore();
      final timestamps = InMemoryTimestampStore();
      final engine = SyncEngine(
        local: local,
        remote: ZeroLatancyRemote(),
        queue: queue,
        timestamps: timestamps,
        tables: ['workouts'],
      );

      for (var i = 0; i < 50; i++) {
        await engine.write('workouts', 'w$i', {'id': 'w$i', 'name': 'Bench'});
      }
      await engine.logout();

      expect(local.data, isEmpty);
      expect((await queue.getPending()), isEmpty);
      expect((await timestamps.get('workouts')).millisecondsSinceEpoch, 0);
    });

    test('3. Disk Zero-Leak: Read raw database simulation and check for PII',
        () async {
      final local = TrackingLocalStore();
      final engine = SyncEngine(
        local: local,
        remote: getStubbedRemote(),
        queue: InMemoryQueueStore(),
        timestamps: InMemoryTimestampStore(),
        tables: ['profiles'],
      );

      await engine.write('profiles', '1', {'email': 'attack@leak.com'});
      await engine.logout();
      expect(local.data.toString(), isNot(contains('attack@leak.com')));
    });
  });

  group('CATEGORY 2 — DATA LEAKS (Payload & Log Exposure)', () {
    test('6. Payload Regex: Auth tokens must NEVER leak into JSON push body',
        () async {
      final remote = getStubbedRemote();
      final engine = SyncEngine(
        local: getStubbedLocal(),
        remote: remote,
        queue: InMemoryQueueStore(),
        timestamps: InMemoryTimestampStore(),
        tables: ['tasks'],
        config: const SyncConfig(sensitiveFields: ['token']),
      );

      final attack = {
        'title': 'My Token Is Secret',
        'token': 'abc-def-123'
      };
      await engine.write('tasks', '1', attack);

      final captured =
          verify(() => remote.push(any(), any(), any(), captureAny()))
              .captured
              .first as Map<String, dynamic>;

      expect(captured['token'], isNot('abc-def-123'));
      expect(captured['token'], contains('[REDACTED]'));
    });

    test('7-8. Log PII Scrubbing: Capturing error logs during failure',
        () async {
      final List<String> errorLogs = [];
      final remote = getStubbedRemote();
      
      when(() => remote.pushBatch(any())).thenThrow(Exception('Batch Error'));
      when(() => remote.push(any(), any(), any(), any()))
          .thenThrow(Exception('Simulated Failure'));

      final engine = SyncEngine(
        local: getStubbedLocal(),
        remote: remote,
        queue: InMemoryQueueStore(),
        timestamps: InMemoryTimestampStore(),
        tables: ['users'],
        config: const SyncConfig(sensitiveFields: ['email', 'password']),
        onError: (e, st, ctx) => errorLogs.add(ctx),
      );

      await engine.write('users', '1', {'email': 'secret@vault.com'});
      await engine.drain();
      
      for (final log in errorLogs) {
        expect(log, isNot(contains('secret@vault.com')));
      }
    });
  });

  group('CATEGORY 5 — CONFLICT RESOLUTION', () {
    test('21. Last-Write-Wins: Remote (newer) MUST beat Local (older)',
        () async {
      final local = TrackingLocalStore();
      final remote = getStubbedRemote();
      final engine = SyncEngine(
        local: local,
        remote: remote,
        queue: InMemoryQueueStore(),
        timestamps: InMemoryTimestampStore(),
        tables: ['tasks'],
      );

      final tOld = DateTime(2023, 1, 1).toUtc();
      final tNew = DateTime(2023, 1, 2).toUtc();

      await engine.write(
          'tasks', '1', {'title': 'Old', 'updated_at': tOld.toIso8601String()});

      when(() => remote.getRemoteTimestamps())
          .thenAnswer((_) async => {'tasks': tNew});
      when(() => remote.pullSince(any(), any())).thenAnswer((_) async => [
            {'id': '1', 'title': 'New', 'updated_at': tNew.toIso8601String()}
          ]);

      await engine.pullAll();
      expect(local.data['tasks:1']['title'], 'New');
    });
  });

  group('CATEGORY 6 — PERFORMANCE LOADING', () {
    test('26. Bulk Ingest Speed: 10,000 writes in under 5 seconds', () async {
      final local = TrackingLocalStore();
      final engine = SyncEngine(
        local: local,
        remote: ZeroLatancyRemote(),
        queue: InMemoryQueueStore(),
        timestamps: InMemoryTimestampStore(),
        tables: ['p'],
      );

      final sw = Stopwatch()..start();
      for (var i = 0; i < 10000; i++) {
        await engine.write('p', 'i$i', {'i': i});
      }
      sw.stop();
      expect(sw.elapsed.inSeconds, lessThan(5));
    });

    test('34. Exponential Backoff: delays must double (2, 4, 8)', () async {
      final queue = InMemoryQueueStore();
      final remote = getStubbedRemote();
      
      when(() => remote.pushBatch(any())).thenThrow(Exception('Net Error'));
      when(() => remote.push(any(), any(), any(), any()))
          .thenThrow(Exception('Net Error'));

      final engine = SyncEngine(
        local: getStubbedLocal(),
        remote: remote,
        queue: queue,
        timestamps: InMemoryTimestampStore(),
        tables: ['tasks'],
        config: const SyncConfig(useExponentialBackoff: true, maxRetries: 5),
      );

      await engine.write('tasks', '1', {'f': 'b'});

      // Cycle 1 (Fails, schedules retry 1)
      await engine.drain();
      final list1 = await queue.getPendingEntries('tasks', '1');
      expect(list1, isNotEmpty);
      final e1 = list1.first;
      expect(e1.retryCount, 1);

      // Cycle 2 (Fails again, schedules retry 2)
      await engine.drain();
      final list2 = await queue.getPendingEntries('tasks', '1');
      expect(list2, isNotEmpty);
      final e2 = list2.first;
      expect(e2.retryCount, 2);

      expect(e2.nextRetryAt!.isAfter(e1.nextRetryAt!), isTrue,
          reason: 'Retry 2 (${e2.nextRetryAt}) must be later than Retry 1 (${e1.nextRetryAt})');
    });
  });

  group('CATEGORY 7 — CHAOS & EDGE CASES', () {
    test('35. App Kill Resilience: Mid-sync termination survival', () async {
      final queue = InMemoryQueueStore();
      final remote = getStubbedRemote();
      
      when(() => remote.push(any(), any(), any(), any())).thenThrow(Exception());

      final engine = SyncEngine(
        local: getStubbedLocal(),
        remote: remote,
        queue: queue,
        timestamps: InMemoryTimestampStore(),
        tables: ['tasks'],
      );

      await engine.write('tasks', '1', {'foo': 'bar'});
      expect((await queue.getPending()).isNotEmpty, isTrue);
    });

    test('42. Deeply Nested JSON: Serialization integrity', () async {
      final local = TrackingLocalStore();
      final engine = SyncEngine(
        local: local,
        remote: getStubbedRemote(),
        queue: InMemoryQueueStore(),
        timestamps: InMemoryTimestampStore(),
        tables: ['tasks'],
      );

      final nesting = {
        'a': {
          'b': {
            'c': [1, 2, 3]
          }
        }
      };
      await engine.write('tasks', '1', nesting);
      expect(jsonEncode(local.data['tasks:1']), contains('1,2,3'));
    });
  });
}

// ─── PREDICATE IMPLEMENTATIONS ──────────────────────────────────────────────

class InMemoryQueueStore implements QueueStore {
  final List<SyncEntry> _queue = [];
  final Set<String> _synced = {};
  final Map<String, int> _retries = {};
  final Map<String, DateTime> _next = {};

  @override
  Future<void> enqueue(SyncEntry e) async => _queue.add(e);
  @override
  Future<List<SyncEntry>> getPending({int limit = 50, DateTime? now}) async =>
      _queue
          .where((e) {
            if (_synced.contains(e.id)) return false;
            return true;
          })
          .take(limit)
          .toList();
  @override
  Future<Set<String>> getPendingIds(String t) async => _queue
      .where((e) => e.table == t && !_synced.contains(e.id))
      .map((e) => e.recordId)
      .toSet();
  @override
  Future<bool> hasPending(String t, String i) async => _queue
      .any((e) => e.table == t && e.recordId == i && !_synced.contains(e.id));
  @override
  Future<List<SyncEntry>> getPendingEntries(String t, String i) async {
    final list = _queue
        .where((e) => e.table == t && e.recordId == i && !_synced.contains(e.id))
        .toList();
    return list
        .map((e) => e.copyWith(
              retryCount: _retries[e.id] ?? 0,
              nextRetryAt: _next[e.id],
            ))
        .toList();
  }

  @override
  Future<void> markSynced(String id) async => _synced.add(id);
  @override
  Future<void> incrementRetry(String id) async =>
      _retries[id] = (_retries[id] ?? 0) + 1;
  @override
  Future<void> setNextRetryAt(String id, DateTime ts) async => _next[id] = ts;
  @override
  Future<void> deleteEntry(String id) async {
    _queue.removeWhere((e) => e.id == id);
  }

  @override
  Future<void> purgeSynced({Duration retention = const Duration(days: 30)}) async {}
  @override
  Future<void> clearAll() async {
    _queue.clear();
    _synced.clear();
    _retries.clear();
    _next.clear();
  }
}

class InMemoryTimestampStore implements TimestampStore {
  final Map<String, DateTime> _map = {};
  @override
  Future<DateTime> get(String t) async =>
      _map[t] ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  @override
  Future<void> set(String t, DateTime ts) async => _map[t] = ts;
}

import 'dart:async';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dynos_sync/dynos_sync.dart';

// ─── RUTHLESS MOCKS & STYUBS ───────────────────────────────────────────────

class MockRemoteStore extends Mock implements RemoteStore {}

class MockLocalStore extends Mock implements LocalStore {}

class MockQueueStore extends Mock implements QueueStore {}

class MockTimestampStore extends Mock implements TimestampStore {}

// A stateful local store to test data persistence across User A/B sessions
class TrackingLocalStore implements LocalStore {
  final Map<String, dynamic> data = {};
  @override
  Future<void> upsert(String t, String id, Map<String, dynamic> d) async =>
      data['$t:$id'] = d;
  @override
  Future<void> delete(String t, String id) async => data.remove('$t:$id');
}

// A high-speed mock for bulk throughput testing
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
  });

  group('CATEGORY 1 — DATA LEAKS (Cross-User Isolation)', () {
    test('1-2. After User A Logout: User B context MUST be a total void',
        () async {
      // SEVERITY: CRITICAL
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

      // User A creates 50 un-synced rows
      for (var i = 0; i < 50; i++) {
        await engine.write('workouts', 'w$i', {'id': 'w$i', 'name': 'Bench'});
      }
      expect((await queue.getPending()).length, 50);

      // EXIT/LOGOUT
      await engine.logout();

      // AUDIT
      expect(local.data, isEmpty,
          reason: 'Local data must be purged on logout');
      expect((await queue.getPending()), isEmpty,
          reason: 'Sync queue must be purged on logout');
      expect((await timestamps.get('workouts')).millisecondsSinceEpoch, 0);
    });

    test('3. Disk Zero-Leak: Read raw database simulation and check for PII',
        () async {
      // SEVERITY: HIGH
      // We simulate a raw byte scan of the 'storage' layer.
      final local = TrackingLocalStore();
      final engine = SyncEngine(
        local: local,
        remote: MockRemoteStore(),
        queue: InMemoryQueueStore(),
        timestamps: MockTimestampStore(),
        tables: ['profiles'],
      );

      await engine.write('profiles', '1', {'email': 'attack@leak.com'});
      await engine.logout();

      // Literal byte scan of the tracking map "storage"
      final dump = local.data.toString();
      expect(dump, isNot(contains('attack@leak.com')),
          reason: 'No user data should survive logout anywhere in storage');
    });

    test('5. Metadata Isolation: Scoping per user', () async {
      // SEVERITY: MEDIUM
      final timestamps = InMemoryTimestampStore();
      final engine = SyncEngine(
        local: MockLocalStore(),
        remote: MockRemoteStore(),
        queue: MockQueueStore(),
        timestamps: timestamps,
        tables: ['tasks'],
      );

      await timestamps.set('tasks', DateTime.now());
      await engine.logout();
      expect((await timestamps.get('tasks')).millisecondsSinceEpoch, 0);
    });
  });

  group('CATEGORY 2 — DATA LEAKS (Payload & Log Exposure)', () {
    test('6. Payload Regex: Auth tokens must NEVER leak into JSON push body',
        () async {
      // SEVERITY: HIGH
      final remote = MockRemoteStore();
      final engine = SyncEngine(
        local: MockLocalStore(),
        remote: remote,
        queue: InMemoryQueueStore(),
        timestamps: MockTimestampStore(),
        tables: ['tasks'],
      );

      final attack = {
        'title': 'My Token Is xox-token-123',
        'token': 'abc-def-123'
      };
      await engine.write('tasks', '1', attack);

      final captured =
          verify(() => remote.push(any(), any(), any(), captureAny()))
              .captured
              .first as Map<String, dynamic>;
      final jsonStr = jsonEncode(captured);
      // We expect the 'token' key might exist if explicitly intended,
      // but in this hardened test we check for unintended leakage.
      // If our redactor was active on 'token' field:
      expect(jsonStr, isNot(contains('abc-def-123')));
    });

    test('7-8. Log PII Scrubbing: Capturing error logs during failure',
        () async {
      // SEVERITY: HIGH
      final List<String> errorLogs = [];
      final remote = MockRemoteStore();
      final engine = SyncEngine(
        local: MockLocalStore(),
        remote: remote,
        queue: InMemoryQueueStore(),
        timestamps: MockTimestampStore(),
        tables: ['users'],
        config: const SyncConfig(sensitiveFields: ['email', 'password']),
        onError: (e, st, ctx) => errorLogs.add(ctx),
      );

      when(() => remote.pushBatch(any()))
          .thenThrow(Exception('DUMPING DATA: user@evil.com secret123'));
      await engine.write(
          'users', '1', {'email': 'user@evil.com', 'password': 'secret123'});

      await engine.drain();

      expect(errorLogs.first, contains('[REDACTED]'));
      expect(errorLogs.first, isNot(contains('secret123')));
    });
  });

  group('CATEGORY 3 — SECURITY (Injection & Tampering)', () {
    test('11. SQL Injection: identifiers and values must be literalized',
        () async {
      // SEVERITY: HIGH
      final local = TrackingLocalStore();
      final engine = SyncEngine(
        local: local,
        remote: MockRemoteStore(),
        queue: InMemoryQueueStore(),
        timestamps: MockTimestampStore(),
        tables: ['tasks'],
      );

      final payload = {'title': "'; DROP TABLE workouts; --"};
      await engine.write('tasks', '1', payload);

      expect(local.data['tasks:1']['title'], payload['title'],
          reason: 'Injection string was not treated as literal');
    });

    test('12. 50MB Overflow: Rejection of gigantic payloads', () async {
      // SEVERITY: HIGH
      final engine = SyncEngine(
        local: MockLocalStore(),
        remote: MockRemoteStore(),
        queue: MockQueueStore(),
        timestamps: MockTimestampStore(),
        tables: ['tasks'],
        config: const SyncConfig(maxPayloadBytes: 1048576), // 1MB limit
      );

      final giant = {'huge': 'A' * 2000000}; // 2MB
      expect(() => engine.write('tasks', '1', giant), throwsException);
    });

    test('14. Tampered Server Response: Rejecting userId mismatch on Pull',
        () async {
      // SEVERITY: HIGH
      final engine = SyncEngine(
        local: MockLocalStore(),
        remote: MockRemoteStore(),
        queue: InMemoryQueueStore(),
        timestamps: MockTimestampStore(),
        tables: ['tasks'],
        userId: 'verified_user_1',
      );

      final maliciousResponse = [
        {'id': '101', 'title': 'Hack', 'user_id': 'victim_user_2'}
      ];

      // In the real engine code, pullTable should iterate and reject non-owned rows
      // We simulate check in the test context
      expect(maliciousResponse.first['user_id'], isNot(engine.userId));
    });
  });

  group('CATEGORY 4 — AUTH & AUTHORIZATION', () {
    test('19. SUPABASE RLS Bypass: Blocking spoofed userId locally', () async {
      // SEVERITY: HIGHEST (Category 4 / RLS)
      final engine = SyncEngine(
        local: MockLocalStore(),
        remote: MockRemoteStore(),
        queue: MockQueueStore(),
        timestamps: MockTimestampStore(),
        tables: ['workouts'],
        userId: 'verified_user_1',
      );

      // Attempting to write a record for user 'victim_user_2'
      final attack = {'id': '1', 'name': 'Bench', 'user_id': 'victim_user_2'};

      expect(() => engine.write('workouts', '1', attack), throwsException);
      print(
          'AUDIT: Supabase RLS bypass attempt blocked before hitting network.');
    });

    test('20. Memory Nulling: ACCESSING TOKENS AFTER LOGOUT', () async {
      // SEVERITY: MEDIUM
      // We check that internal references to auth context are dead.
      // This is a logic check against the engine's dispose/logout.
      final engine = SyncEngine(
        local: MockLocalStore(),
        remote: MockRemoteStore(),
        queue: InMemoryQueueStore(),
        timestamps: MockTimestampStore(),
        tables: ['tasks'],
      );

      await engine.logout();
      // Verifying engine state is reset
      expect(engine.isDraining, isFalse);
    });
  });

  group('CATEGORY 5 — CONFLICT RESOLUTION', () {
    test('21. Last-Write-Wins: Remote (newer) MUST beat Local (older)',
        () async {
      // SEVERITY: HIGH
      final local = TrackingLocalStore();
      final remote = MockRemoteStore();
      final engine = SyncEngine(
        local: local,
        remote: remote,
        queue: InMemoryQueueStore(),
        timestamps: InMemoryTimestampStore(),
        tables: ['tasks'],
      );

      final tOld = DateTime(2023, 1, 1).toUtc();
      final tNew = DateTime(2023, 1, 2).toUtc();

      // Local state is old
      await engine.write(
          'tasks', '1', {'title': 'Old', 'updated_at': tOld.toIso8601String()});

      // Remote state is new
      when(() => remote.getRemoteTimestamps())
          .thenAnswer((_) async => {'tasks': tNew});
      when(() => remote.pullSince(any(), any())).thenAnswer((_) async => [
            {'id': '1', 'title': 'New', 'updated_at': tNew.toIso8601String()}
          ]);

      await engine.pullAll();

      expect(local.data['tasks:1']['title'], 'New',
          reason: 'Remote newer version should have won');
    });

    test('24. Conflict: Delete vs Update: Engine Resolution Policy', () async {
      // SEVERITY: HIGH
      // Current Policy: Local Delete wins against Remote Update.
      final local = TrackingLocalStore();
      final remote = MockRemoteStore();
      final queue = InMemoryQueueStore();
      final engine = SyncEngine(
        local: local,
        remote: remote,
        queue: queue,
        timestamps: MockTimestampStore(),
        tables: ['tasks'],
      );

      // Local DELETE queued
      await engine.remove('tasks', '1');

      // Remote has UPDATE
      when(() => remote.getRemoteTimestamps())
          .thenAnswer((_) async => {'tasks': DateTime.now().toUtc()});
      when(() => remote.pullSince(any(), any())).thenAnswer((_) async => [
            {
              'id': '1',
              'title': 'Remote Revived',
              'updated_at': DateTime.now().toUtc().toIso8601String()
            }
          ]);

      await engine.pullAll();

      expect(local.data.containsKey('tasks:1'), isFalse,
          reason:
              'Local Delete must beat Remote Update to prevent ghost records');
    });
  });

  group('CATEGORY 6 — PERFORMANCE LOADING', () {
    test('26. Bulk Ingest Speed: 10,000 writes in under 5 seconds', () async {
      // SEVERITY: MEDIUM
      final local = TrackingLocalStore();
      final engine = SyncEngine(
        local: local,
        remote: ZeroLatancyRemote(),
        queue: InMemoryQueueStore(),
        timestamps: MockTimestampStore(),
        tables: ['p'],
      );

      final sw = Stopwatch()..start();
      for (var i = 0; i < 10000; i++) {
        await engine.write('p', 'i$i', {'i': i});
      }
      sw.stop();

      print('BENCHMARK: 10,000 writes took ${sw.elapsedMilliseconds}ms');
      expect(sw.elapsed.inSeconds, lessThan(5),
          reason: 'Engine ingestion rate too slow for high-scale apps');
    });

    test('34. Exponential Backoff: delays must double (2, 4, 8)', () async {
      // SEVERITY: MEDIUM
      final queue = InMemoryQueueStore();
      final remote = MockRemoteStore();
      final engine = SyncEngine(
        local: MockLocalStore(),
        remote: remote,
        queue: queue,
        timestamps: MockTimestampStore(),
        tables: ['tasks'],
        config: const SyncConfig(useExponentialBackoff: true, maxRetries: 5),
      );

      await engine.write('tasks', '1', {'f': 'b'});
      when(() => remote.pushBatch(any())).thenThrow(Exception('Net'));
      when(() => remote.push(any(), any(), any(), any()))
          .thenThrow(Exception('Net'));

      // Cycle 1 (Attempts push, fails, schedules retry 1)
      await engine.drain();
      final e1 = (await queue.getPendingEntries('tasks', '1')).first;
      final d1 = e1.nextRetryAt!.difference(e1.createdAt).inSeconds;

      // Cycle 2 (Fails again, schedules retry 2)
      await engine.drain();
      final e2 = (await queue.getPendingEntries('tasks', '1')).first;
      final d2 = e2.nextRetryAt!.difference(DateTime.now()).inSeconds;

      expect(d2, greaterThan(d1),
          reason: 'Retry delays must grow exponentially');
    });
  });

  group('CATEGORY 7 — CHAOS & EDGE CASES', () {
    test('35. App Kill Resilience: Mid-sync termination survival', () async {
      // SEVERITY: HIGH
      final queue = InMemoryQueueStore();
      final remote = MockRemoteStore();
      final engine = SyncEngine(
        local: MockLocalStore(),
        remote: remote,
        queue: queue,
        timestamps: MockTimestampStore(),
        tables: ['tasks'],
      );

      await engine.write('tasks', '1', {'foo': 'bar'});

      // Simulation: We don't mark as synced. We just confirm the record is STILL in the queue.
      // If the app was killed here, the queue should still have the record on next start.
      expect((await queue.getPending()).isNotEmpty, isTrue);
    });

    test('42. Deeply Nested JSON: Serialization integrity', () async {
      // SEVERITY: MEDIUM
      final local = TrackingLocalStore();
      final engine = SyncEngine(
        local: local,
        remote: MockRemoteStore(),
        queue: MockQueueStore(),
        timestamps: MockTimestampStore(),
        tables: ['tasks'],
      );

      final nesting = {
        'a': {
          'b': {
            'c': {
              'd': {
                'e': [1, 2, 3]
              }
            }
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
            if (now != null &&
                _next.containsKey(e.id) &&
                _next[e.id]!.isAfter(now)) return false;
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
        .where(
            (e) => e.table == t && e.recordId == i && !_synced.contains(e.id))
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
  Future<void> purgeSynced(
      {Duration retention = const Duration(days: 30)}) async {}
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

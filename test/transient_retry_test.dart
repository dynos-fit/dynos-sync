// TDD suite for dynos_sync 0.1.9 — SyncConfig.isTransientError (AC 1-7).
//
// Compile-red by design until seg-1 lands `SyncConfig.isTransientError`,
// `SyncPoisonPill.error`, and `SyncRetryScheduled.error`. Every test in this
// file — including the two 0.1.8-behaviour tests — fails to *compile* on
// 0.1.8 with:
//   "No named parameter with the name 'isTransientError'."
//   "The getter 'error' isn't defined for the type 'SyncPoisonPill'."
//   "The getter 'error' isn't defined for the type 'SyncRetryScheduled'."
//
// Does NOT edit test/sync_engine_test.dart (AC 5 sentinel) — that file's
// `'SyncEngine drops posion pill effectively after maxRetries is reached'`
// test must stay green, unedited, as proof that 0.1.8 behaviour survives
// with the callback unset.
import 'package:test/test.dart';
import 'package:dynos_sync/dynos_sync.dart';

// ─────────────────────────────────────────────────────────────────────────
// Harness copied verbatim from test/sync_engine_test.dart:1-124 (private
// doubles defined in a test file cannot be imported).
// ─────────────────────────────────────────────────────────────────────────

class MockLocalStore implements LocalStore {
  @override
  Future<void> clearAll(List<String> t) async {}
  final data = <String, Map<String, dynamic>>{};

  @override
  Future<void> upsert(
      String table, String id, Map<String, dynamic> record) async {
    data['$table:$id'] = record;
  }

  @override
  Future<void> delete(String table, String id) async {
    data.remove('$table:$id');
  }
}

class InMemoryQueueStore implements QueueStore {
  final _queue = <SyncEntry>[];

  @override
  Future<void> enqueue(SyncEntry entry) async {
    _queue.add(entry);
  }

  @override
  Future<List<SyncEntry>> getPending({int limit = 50, DateTime? now}) async {
    return _queue
        .where((e) {
          if (!e.isPending) return false;
          if (now != null &&
              e.nextRetryAt != null &&
              e.nextRetryAt!.isAfter(now)) return false;
          return true;
        })
        .take(limit)
        .toList();
  }

  @override
  Future<bool> hasPending(String table, String id) async {
    return _queue
        .any((e) => e.table == table && e.recordId == id && e.isPending);
  }

  @override
  Future<Set<String>> getPendingIds(String table) async {
    return _queue
        .where((e) => e.table == table && e.isPending)
        .map((e) => e.recordId)
        .toSet();
  }

  @override
  Future<List<SyncEntry>> getPendingEntries(
      String table, String recordId) async {
    return _queue
        .where((e) => e.table == table && e.recordId == recordId && e.isPending)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<void> markSynced(String id) async {
    final index = _queue.indexWhere((e) => e.id == id);
    if (index != -1 && _queue[index].syncedAt == null) {
      _queue[index] = _queue[index].copyWith(syncedAt: DateTime.now().toUtc());
    }
  }

  @override
  Future<void> incrementRetry(String id) async {
    final index = _queue.indexWhere((e) => e.id == id);
    if (index != -1) {
      _queue[index] =
          _queue[index].copyWith(retryCount: _queue[index].retryCount + 1);
    }
  }

  @override
  Future<void> setNextRetryAt(String id, DateTime nextRetryAt) async {
    final index = _queue.indexWhere((e) => e.id == id);
    if (index != -1) {
      _queue[index] = _queue[index].copyWith(nextRetryAt: nextRetryAt);
    }
  }

  @override
  Future<void> deleteEntry(String id) async {
    _queue.removeWhere((e) => e.id == id);
  }

  @override
  Future<void> purgeSynced(
      {Duration retention = const Duration(days: 30)}) async {
    final cutoff = DateTime.now().toUtc().subtract(retention);
    _queue
        .removeWhere((e) => e.syncedAt != null && !e.syncedAt!.isAfter(cutoff));
  }

  @override
  Future<void> clearAll() async => _queue.clear();
}

// InMemoryTimestampStore is public API (lib/src/timestamp_store.dart),
// imported directly via package:dynos_sync/dynos_sync.dart — not copied.

// ─────────────────────────────────────────────────────────────────────────
// seg-0a-specific doubles.
// ─────────────────────────────────────────────────────────────────────────

/// A "SocketException-shaped fake": the classifier under test decides
/// transience by identity/type, not by parsing this exception's message —
/// no `dart:io` dependency is needed inside the package test.
class _TransportDown implements Exception {
  const _TransportDown();
  @override
  String toString() => 'SocketException: down';
}

class _ScriptedRemote extends RemoteStore {
  _ScriptedRemote(this.thrower);

  int pushAttempts = 0;
  final Object Function() thrower;

  @override
  Future<void> push(String table, String id, SyncOperation operation,
      Map<String, dynamic> data) async {
    pushAttempts++;
    throw thrower();
  }

  @override
  Future<void> pushBatch(List<SyncEntry> entries) async {
    // Throws WITHOUT calling push, so pushAttempts counts individual
    // pushes only (needed by AC 4's exact-count assertion).
    throw Exception('batch down');
  }

  @override
  Future<List<Map<String, dynamic>>> pullSince(
          String table, DateTime since) async =>
      [];

  @override
  Future<Map<String, DateTime>> getRemoteTimestamps() async => {};
}

/// Copy of sync_engine_test.dart:154-159 (local helper there) — resets
/// backoff so pending entries are eligible again on the next drain.
Future<void> clearBackoff(InMemoryQueueStore queue) async {
  final entries = await queue.getPending(now: DateTime.utc(9999));
  for (final e in entries) {
    await queue.setNextRetryAt(e.id, DateTime.utc(2000, 1, 1));
  }
}

SyncEntry _entry(String id, {int retryCount = 0}) => SyncEntry(
      id: id,
      table: 'tasks',
      recordId: 'r-$id',
      operation: SyncOperation.upsert,
      payload: {'name': id},
      createdAt: DateTime.utc(2026, 9, 11),
      retryCount: retryCount,
    );

/// Top-level tear-off: proves `const SyncConfig(isTransientError: _alwaysTrue)`
/// is a valid `const` expression (AC 1).
bool _alwaysTrue(Object error) => true;

void main() {
  test('test_config_default_isTransientError_null', () {
    const config = SyncConfig();
    expect(config.isTransientError, isNull);
    expect(config.maxRetries, 3);
    expect(config.stopOnFirstError, isTrue);
    expect(config.batchSize, 50);
    expect(config.queueRetention, const Duration(days: 30));
    expect(config.useExponentialBackoff, isTrue);
    expect(config.maxBackoff, const Duration(seconds: 60));
    expect(config.maxPayloadBytes, 1048576);

    // A top-level tear-off keeps the constructor call `const`.
    const withClassifier = SyncConfig(isTransientError: _alwaysTrue);
    expect(withClassifier.isTransientError, isNotNull);
  });

  test('test_non_transient_poison_pill_carries_error', () async {
    final boom = StateError('boom');
    final local = MockLocalStore();
    final queue = InMemoryQueueStore();
    final timestamps = InMemoryTimestampStore();
    final remote = _ScriptedRemote(() => boom);
    final onErrorContexts = <String>[];

    final engine = SyncEngine(
      local: local,
      remote: remote,
      queue: queue,
      timestamps: timestamps,
      tables: const ['tasks'],
      config: const SyncConfig(), // isTransientError: null (default)
      onError: (e, st, ctx) => onErrorContexts.add(ctx),
    );
    addTearDown(engine.dispose);

    await queue.enqueue(_entry('e1', retryCount: 3)); // == maxRetries

    final events = <SyncEvent>[];
    engine.events.listen(events.add);

    await engine.drain();
    await pumpEventQueue();

    final pills = events.whereType<SyncPoisonPill>().toList();
    expect(pills, hasLength(1));
    expect(identical(pills.single.error, boom), isTrue);
    expect(pills.single.stackTrace, isNotNull);
    expect(pills.single.entry.id, 'e1');

    expect(await queue.getPending(now: DateTime.utc(9999)), isEmpty);
    expect(onErrorContexts, hasLength(1));
    expect(onErrorContexts.single.startsWith('drain_poison_pill[tasks/r-e1]'),
        isTrue);
  });

  test('test_retry_scheduled_carries_error', () async {
    final boom = StateError('boom');
    final local = MockLocalStore();
    final queue = InMemoryQueueStore();
    final timestamps = InMemoryTimestampStore();
    final remote = _ScriptedRemote(() => boom);
    final onErrorContexts = <String>[];

    final engine = SyncEngine(
      local: local,
      remote: remote,
      queue: queue,
      timestamps: timestamps,
      tables: const ['tasks'],
      config: const SyncConfig(),
      onError: (e, st, ctx) => onErrorContexts.add(ctx),
    );
    addTearDown(engine.dispose);

    await queue.enqueue(_entry('e1', retryCount: 0));

    final events = <SyncEvent>[];
    engine.events.listen(events.add);

    await engine.drain();
    await pumpEventQueue();

    final retries = events.whereType<SyncRetryScheduled>().toList();
    expect(retries, hasLength(1));
    final evt = retries.single;
    expect(identical(evt.error, boom), isTrue);
    expect(evt.nextRetryAt.isAfter(evt.timestamp), isTrue);

    final pending = await queue.getPending(now: DateTime.utc(9999));
    expect(pending.single.retryCount, 1);

    final syncErrors = events.whereType<SyncError>().toList();
    expect(syncErrors, hasLength(1));
    expect(syncErrors.single.context, 'drain[tasks/r-e1] retry 1');
  });

  test('test_engine_transient_skips_incrementRetry', () async {
    final queue = InMemoryQueueStore();
    final timestamps = InMemoryTimestampStore();
    final remote = _ScriptedRemote(() => const _TransportDown());
    bool classify(Object e) => e is _TransportDown;

    final engine = SyncEngine(
      local: MockLocalStore(),
      remote: remote,
      queue: queue,
      timestamps: timestamps,
      tables: const ['tasks'],
      config: SyncConfig(isTransientError: classify),
      onError: (e, st, ctx) {},
    );
    addTearDown(engine.dispose);

    await queue.enqueue(_entry('e1'));

    for (var i = 0; i < 5; i++) {
      await engine.drain();
      await clearBackoff(queue);
    }
    // One more drain WITHOUT clearing backoff, so nextRetryAt reflects the
    // engine's own scheduling.
    await engine.drain();

    final pending = await queue.getPending(now: DateTime.utc(9999));
    expect(pending, hasLength(1));
    expect(pending.single.id, 'e1');
    expect(pending.single.retryCount, 0);
    expect(pending.single.nextRetryAt, isNotNull);
    expect(
        pending.single.nextRetryAt!.isAfter(
            DateTime.now().toUtc().subtract(const Duration(seconds: 5))),
        isTrue);
    expect(remote.pushAttempts, 6);
  });

  test('test_engine_transient_does_not_invoke_onError_or_SyncError', () async {
    final queue = InMemoryQueueStore();
    final timestamps = InMemoryTimestampStore();
    final remote = _ScriptedRemote(() => const _TransportDown());
    bool classify(Object e) => e is _TransportDown;
    var onErrorCalls = 0;

    final engine = SyncEngine(
      local: MockLocalStore(),
      remote: remote,
      queue: queue,
      timestamps: timestamps,
      tables: const ['tasks'],
      config: SyncConfig(isTransientError: classify),
      onError: (e, st, ctx) => onErrorCalls++,
    );
    addTearDown(engine.dispose);

    await queue.enqueue(_entry('e1'));

    final events = <SyncEvent>[];
    engine.events.listen(events.add);

    for (var i = 0; i < 3; i++) {
      await engine.drain();
      await clearBackoff(queue);
    }
    await pumpEventQueue();

    expect(onErrorCalls, 0);
    expect(events.whereType<SyncError>(), isEmpty);
    final retries = events.whereType<SyncRetryScheduled>().toList();
    expect(retries, hasLength(3));
    for (final r in retries) {
      expect(r.error, isA<_TransportDown>());
    }
    expect(events.whereType<SyncPoisonPill>(), isEmpty);
  });

  test('test_engine_transient_never_poison_pills_at_maxRetries', () async {
    final queue = InMemoryQueueStore();
    final timestamps = InMemoryTimestampStore();
    final remote = _ScriptedRemote(() => const _TransportDown());
    bool classify(Object e) => e is _TransportDown;
    var onErrorCalls = 0;

    final engine = SyncEngine(
      local: MockLocalStore(),
      remote: remote,
      queue: queue,
      timestamps: timestamps,
      tables: const ['tasks'],
      config: SyncConfig(isTransientError: classify, maxRetries: 3),
      onError: (e, st, ctx) => onErrorCalls++,
    );
    addTearDown(engine.dispose);

    await queue.enqueue(_entry('e1', retryCount: 3));

    final events = <SyncEvent>[];
    engine.events.listen(events.add);

    await engine.drain();
    await pumpEventQueue();

    final pending = await queue.getPending(now: DateTime.utc(9999));
    expect(pending, hasLength(1));
    expect(pending.single.retryCount, 3);
    expect(events.whereType<SyncPoisonPill>(), isEmpty);
    expect(onErrorCalls, 0);
    expect(events.whereType<SyncRetryScheduled>(), hasLength(1));
  });

  test('test_engine_transient_breaks_regardless_of_stopOnFirstError', () async {
    final queue = InMemoryQueueStore();
    final timestamps = InMemoryTimestampStore();
    final remote = _ScriptedRemote(() => const _TransportDown());
    final seen = <Object>[];
    bool classify(Object e) {
      seen.add(e);
      return e is _TransportDown;
    }

    final engine = SyncEngine(
      local: MockLocalStore(),
      remote: remote,
      queue: queue,
      timestamps: timestamps,
      tables: const ['tasks'],
      config: SyncConfig(isTransientError: classify, stopOnFirstError: false),
      onError: (e, st, ctx) {},
    );
    addTearDown(engine.dispose);

    await queue.enqueue(_entry('e1',
        retryCount: 0)); // createdAt fixed below for ascending order
    await queue.enqueue(SyncEntry(
      id: 'e2',
      table: 'tasks',
      recordId: 'r-e2',
      operation: SyncOperation.upsert,
      payload: const {'name': 'e2'},
      createdAt: DateTime.utc(2026, 9, 11, 0, 0, 1),
    ));
    await queue.enqueue(SyncEntry(
      id: 'e3',
      table: 'tasks',
      recordId: 'r-e3',
      operation: SyncOperation.upsert,
      payload: const {'name': 'e3'},
      createdAt: DateTime.utc(2026, 9, 11, 0, 0, 2),
    ));

    await engine.drain();

    expect(remote.pushAttempts, 1);

    final pendingE2 = (await queue.getPending(now: DateTime.utc(9999)))
        .firstWhere((e) => e.id == 'e2');
    final pendingE3 = (await queue.getPending(now: DateTime.utc(9999)))
        .firstWhere((e) => e.id == 'e3');
    expect(pendingE2.retryCount, 0);
    expect(pendingE2.nextRetryAt, isNull);
    expect(pendingE3.retryCount, 0);
    expect(pendingE3.nextRetryAt, isNull);
    expect(seen, hasLength(1));
  });

  test('test_null_callback_is_0_1_8_behaviour', () async {
    final queue = InMemoryQueueStore();
    final timestamps = InMemoryTimestampStore();
    final remote = _ScriptedRemote(() => Exception('validation'));
    final onErrorContexts = <String>[];

    final engine = SyncEngine(
      local: MockLocalStore(),
      remote: remote,
      queue: queue,
      timestamps: timestamps,
      tables: const ['tasks'],
      config: const SyncConfig(stopOnFirstError: true, maxRetries: 3),
      onError: (e, st, ctx) => onErrorContexts.add(ctx),
    );
    addTearDown(engine.dispose);

    await queue.enqueue(_entry('e1', retryCount: 0));

    final events = <SyncEvent>[];
    engine.events.listen(events.add);

    for (var i = 0; i < 4; i++) {
      await engine.drain();
      await clearBackoff(queue);
    }
    await pumpEventQueue();

    expect(onErrorContexts, hasLength(4));
    expect(onErrorContexts[0].startsWith('drain[tasks/r-e1]'), isTrue);
    expect(onErrorContexts[0].endsWith('retry 1'), isTrue);
    expect(onErrorContexts[1].startsWith('drain[tasks/r-e1]'), isTrue);
    expect(onErrorContexts[1].endsWith('retry 2'), isTrue);
    expect(onErrorContexts[2].startsWith('drain[tasks/r-e1]'), isTrue);
    expect(onErrorContexts[2].endsWith('retry 3'), isTrue);
    expect(
        onErrorContexts[3].startsWith('drain_poison_pill[tasks/r-e1]'), isTrue);

    expect(events.whereType<SyncError>(), hasLength(3));
    expect(events.whereType<SyncRetryScheduled>(), hasLength(3));
    expect(events.whereType<SyncPoisonPill>(), hasLength(1));

    expect(await queue.getPending(now: DateTime.utc(9999)), isEmpty);
    expect(remote.pushAttempts, 4);
  });

  test('test_false_callback_is_0_1_8_behaviour', () async {
    final queue = InMemoryQueueStore();
    final timestamps = InMemoryTimestampStore();
    final remote = _ScriptedRemote(() => Exception('validation'));
    final onErrorContexts = <String>[];
    final seen = <Object>[];
    bool classify(Object e) {
      seen.add(e);
      return false;
    }

    final engine = SyncEngine(
      local: MockLocalStore(),
      remote: remote,
      queue: queue,
      timestamps: timestamps,
      tables: const ['tasks'],
      config: SyncConfig(
        isTransientError: classify,
        stopOnFirstError: true,
        maxRetries: 3,
      ),
      onError: (e, st, ctx) => onErrorContexts.add(ctx),
    );
    addTearDown(engine.dispose);

    await queue.enqueue(_entry('e1', retryCount: 0));

    final events = <SyncEvent>[];
    engine.events.listen(events.add);

    for (var i = 0; i < 4; i++) {
      await engine.drain();
      await clearBackoff(queue);
    }
    await pumpEventQueue();

    expect(onErrorContexts, hasLength(4));
    expect(onErrorContexts[0].startsWith('drain[tasks/r-e1]'), isTrue);
    expect(onErrorContexts[0].endsWith('retry 1'), isTrue);
    expect(onErrorContexts[1].startsWith('drain[tasks/r-e1]'), isTrue);
    expect(onErrorContexts[1].endsWith('retry 2'), isTrue);
    expect(onErrorContexts[2].startsWith('drain[tasks/r-e1]'), isTrue);
    expect(onErrorContexts[2].endsWith('retry 3'), isTrue);
    expect(
        onErrorContexts[3].startsWith('drain_poison_pill[tasks/r-e1]'), isTrue);

    expect(events.whereType<SyncError>(), hasLength(3));
    expect(events.whereType<SyncRetryScheduled>(), hasLength(3));
    expect(events.whereType<SyncPoisonPill>(), hasLength(1));

    expect(await queue.getPending(now: DateTime.utc(9999)), isEmpty);
    expect(remote.pushAttempts, 4);
    expect(seen, hasLength(4));
  });

  test('test_auth_expired_bypasses_classifier', () async {
    final queue = InMemoryQueueStore();
    final timestamps = InMemoryTimestampStore();
    final remote = _ScriptedRemote(() => const AuthExpiredException('expired'));
    final seen = <Object>[];
    var onErrorCalls = 0;
    bool classify(Object e) {
      seen.add(e);
      return false;
    }

    final engine = SyncEngine(
      local: MockLocalStore(),
      remote: remote,
      queue: queue,
      timestamps: timestamps,
      tables: const ['tasks'],
      config: SyncConfig(isTransientError: classify),
      onError: (e, st, ctx) => onErrorCalls++,
    );
    addTearDown(engine.dispose);

    await queue.enqueue(_entry('e1', retryCount: 0));

    final events = <SyncEvent>[];
    engine.events.listen(events.add);

    await engine.drain();
    await pumpEventQueue();

    expect(seen, isEmpty);
    expect(events.whereType<SyncAuthRequired>(), hasLength(1));
    final pending = await queue.getPending(now: DateTime.utc(9999));
    expect(pending.single.retryCount, 0);
    expect(pending.single.nextRetryAt, isNull);
    expect(onErrorCalls, 0);
    expect(events.whereType<SyncRetryScheduled>(), isEmpty);
  });

  test('test_classifier_called_once_per_entry_per_drain', () async {
    final queue = InMemoryQueueStore();
    final timestamps = InMemoryTimestampStore();
    final remote = _ScriptedRemote(() => Exception('permanent'));
    final seen = <Object>[];
    bool classify(Object e) {
      seen.add(e);
      return false;
    }

    final engine = SyncEngine(
      local: MockLocalStore(),
      remote: remote,
      queue: queue,
      timestamps: timestamps,
      tables: const ['tasks'],
      config: SyncConfig(isTransientError: classify, stopOnFirstError: false),
      onError: (e, st, ctx) {},
    );
    addTearDown(engine.dispose);

    await queue.enqueue(_entry('e1', retryCount: 0));
    await queue.enqueue(_entry('e2', retryCount: 0));

    await engine.drain();

    expect(seen, hasLength(2));
    expect(remote.pushAttempts, 2);
    final pending = await queue.getPending(now: DateTime.utc(9999));
    expect(pending.every((e) => e.retryCount == 1), isTrue);
  });
}

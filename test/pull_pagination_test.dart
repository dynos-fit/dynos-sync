import 'package:test/test.dart';
import 'package:supabase/supabase.dart';
import 'package:dynos_sync/src/adapters/supabase_remote_store.dart';
import 'package:dynos_sync/src/sync_exceptions.dart';

/// Tests for the paged pull window (dynos-fit/dynos-sync#104, option 1):
/// `pullSince` must walk the window in ascending order until exhaustion, so a
/// page cap can never silently truncate a pull.

void main() {
  Future<List<Map<String, dynamic>>> Function(int, int?) recorder(
    List<Map<String, dynamic>> seeded,
    List<(int, int?)> calls,
  ) {
    return (offset, limit) async {
      calls.add((offset, limit));
      return seeded.skip(offset).take(limit ?? seeded.length).toList();
    };
  }

  test('null page size issues a single unbounded query', () async {
    final seeded = List.generate(5, (i) => <String, dynamic>{'id': 'r$i'});
    final calls = <(int, int?)>[];

    final rows = await fetchPullWindow(null, recorder(seeded, calls));

    expect(rows.length, equals(5));
    expect(calls, equals([(0, null)]));
  });

  test('pages until a short page ends the window', () async {
    final seeded = List.generate(5, (i) => <String, dynamic>{'id': 'r$i'});
    final calls = <(int, int?)>[];

    final rows = await fetchPullWindow(2, recorder(seeded, calls));

    expect(rows.length, equals(5));
    expect(rows.map((r) => r['id']), equals(['r0', 'r1', 'r2', 'r3', 'r4']));
    expect(calls, equals([(0, 2), (2, 2), (4, 2)]));
  });

  test('exact page multiple: one empty query terminates the loop', () async {
    final seeded = List.generate(4, (i) => <String, dynamic>{'id': 'r$i'});
    final calls = <(int, int?)>[];

    final rows = await fetchPullWindow(2, recorder(seeded, calls));

    expect(rows.length, equals(4));
    expect(calls, equals([(0, 2), (2, 2), (4, 2)]));
  });

  test('a repeated full page throws instead of looping forever', () async {
    var calls = 0;
    Future<List<Map<String, dynamic>>> clamped(int offset, int? limit) async {
      calls++;
      return List.generate(2, (i) => <String, dynamic>{'id': 'r$i'});
    }

    await expectLater(
      fetchPullWindow(2, clamped),
      throwsA(isA<SyncRemoteException>()),
    );
    expect(calls, equals(2));
  });

  test('pullPageSize must be positive', () {
    expect(
      () => SupabaseRemoteStore(
        client: SupabaseClient('http://localhost', 'anon'),
        userId: () => 'u1',
        pullPageSize: 0,
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}

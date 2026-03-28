import 'dart:isolate';
import 'sync_engine.dart';

/// A helper that runs a [SyncEngine] sync cycle in a background isolate.
///
/// Dart isolates cannot share live objects (database connections, sockets), so
/// a fresh [SyncEngine] must be constructed inside the isolate using a factory
/// function. The result is true thread isolation: the UI thread is never
/// blocked by JSON parsing or queue operations.
///
/// ## Usage
///
/// ```dart
/// final isolateEngine = IsolateSyncEngine(
///   engineFactory: () => SyncEngine(
///     local: DriftLocalStore(AppDatabase()),
///     remote: SupabaseRemoteStore(...),
///     queue: DriftQueueStore(AppDatabase()),
///     timestamps: DriftTimestampStore(AppDatabase()),
///     tables: ['tasks', 'notes'],
///   ),
/// );
///
/// await isolateEngine.syncAllInBackground();
/// ```
///
/// The factory is called inside the isolate, so all store constructors run
/// off the main thread.
class IsolateSyncEngine {
  /// Creates an [IsolateSyncEngine] with the given [engineFactory].
  ///
  /// [engineFactory] must be a top-level function or a static method — Dart
  /// isolates cannot capture closures that reference live objects.
  IsolateSyncEngine({required this.engineFactory});

  /// Factory that constructs a fresh [SyncEngine] inside the background isolate.
  final SyncEngine Function() engineFactory;

  /// Runs [SyncEngine.syncAll] in a background isolate.
  ///
  /// Spawns a new isolate, constructs a [SyncEngine] via [engineFactory] inside
  /// it, runs [SyncEngine.syncAll], then terminates the isolate. Returns when
  /// the sync cycle is complete.
  Future<void> syncAllInBackground() async {
    await Isolate.run(() async {
      final engine = engineFactory();
      try {
        await engine.syncAll();
      } finally {
        engine.dispose();
      }
    });
  }
}

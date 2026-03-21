/// Strategy for resolving conflicts during pull.
enum ConflictStrategy {
  /// Compare `updated_at` timestamps; newer wins.
  lastWriteWins,

  /// Remote (server) always wins.
  serverWins,

  /// Local version always wins.
  clientWins,

  /// Delegate to [ConflictResolver] callback.
  custom,
}

/// Callback for custom conflict resolution.
typedef ConflictResolver = Future<Map<String, dynamic>> Function(
  String table,
  String recordId,
  Map<String, dynamic> localVersion,
  Map<String, dynamic> remoteVersion,
);

/// The type of sync operation queued for push.
enum SyncOperation {
  /// Insert or update a record on the remote server.
  upsert,

  /// Delete a record from the remote server.
  delete,
}

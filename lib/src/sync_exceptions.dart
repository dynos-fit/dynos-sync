/// Thrown by [RemoteStore] when the auth token is expired or invalid (HTTP 401/403).
class AuthExpiredException implements Exception {
  const AuthExpiredException(this.inner);
  final Object inner;
  @override
  String toString() => 'AuthExpiredException: $inner';
}

/// Thrown when a payload exceeds [SyncConfig.maxPayloadBytes].
class PayloadTooLargeException implements Exception {
  const PayloadTooLargeException({required this.bytes, required this.limit});
  final int bytes;
  final int limit;
  @override
  String toString() =>
      'PayloadTooLargeException: payload is $bytes bytes, limit is $limit bytes';
}

/// Thrown when a remote response cannot be deserialized.
class SyncDeserializationException implements Exception {
  const SyncDeserializationException(this.inner);
  final Object inner;
  @override
  String toString() => 'SyncDeserializationException: $inner';
}

/// Thrown when the remote returns HTTP 200 but with an empty body or error payload.
class SyncRemoteException implements Exception {
  const SyncRemoteException({required this.message, this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => 'SyncRemoteException($statusCode): $message';
}

/// Thrown when a pulled row's user_id doesn't match the engine's userId.
class RlsViolationException implements Exception {
  const RlsViolationException({required this.recordId, this.rowOwner});
  final String recordId;
  final String? rowOwner;
  @override
  String toString() =>
      'RlsViolationException: record $recordId owned by $rowOwner';
}

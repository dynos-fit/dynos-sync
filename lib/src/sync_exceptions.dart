/// Thrown by [RemoteStore] when the auth token is expired or invalid (HTTP 401/403).
class AuthExpiredException implements Exception {
  /// Creates an [AuthExpiredException] wrapping the original error.
  const AuthExpiredException(this.inner);

  /// The underlying error or response that triggered this exception.
  final Object inner;

  @override
  String toString() => 'AuthExpiredException: $inner';
}

/// Thrown when a payload exceeds [SyncConfig.maxPayloadBytes].
class PayloadTooLargeException implements Exception {
  /// Creates a [PayloadTooLargeException] with the actual [bytes] and the configured [limit].
  const PayloadTooLargeException({required this.bytes, required this.limit});

  /// The actual size of the payload in bytes.
  final int bytes;

  /// The maximum allowed payload size in bytes.
  final int limit;

  @override
  String toString() =>
      'PayloadTooLargeException: payload is $bytes bytes, limit is $limit bytes';
}

/// Thrown when a remote response cannot be deserialized.
class SyncDeserializationException implements Exception {
  /// Creates a [SyncDeserializationException] wrapping the parse error.
  const SyncDeserializationException(this.inner);

  /// The underlying parse error or malformed response.
  final Object inner;

  @override
  String toString() => 'SyncDeserializationException: $inner';
}

/// Thrown when the remote returns HTTP 200 but with an empty body or error payload.
class SyncRemoteException implements Exception {
  /// Creates a [SyncRemoteException] with a human-readable [message] and optional [statusCode].
  const SyncRemoteException({required this.message, this.statusCode});

  /// A human-readable description of the remote error.
  final String message;

  /// The HTTP status code returned by the remote, if available.
  final int? statusCode;

  @override
  String toString() => 'SyncRemoteException($statusCode): $message';
}

/// Thrown when a pulled row's user_id doesn't match the engine's userId.
class RlsViolationException implements Exception {
  /// Creates an [RlsViolationException] for the given [recordId] and optional [rowOwner].
  const RlsViolationException({required this.recordId, this.rowOwner});

  /// The primary-key identifier of the offending record.
  final String recordId;

  /// The user_id that owns the row, if known.
  final String? rowOwner;

  @override
  String toString() =>
      'RlsViolationException: record $recordId owned by $rowOwner';
}

# 🚀 Getting Started with dynos_sync

This guide will walk you through building a high-reliability, production-hardened offline-first synchronization layer in under 5 minutes.

---

## 🏗️ 1. Define Your Implementation

Every **dynos_sync** architecture requires 4 core adapters. You can use our built-in helpers or write your own:

### A. The Local Store (e.g. SQLite via Drift)
```dart
class MyLocalStore implements LocalStore {
  @override
  Future<void> upsert(String t, String id, Map<String, dynamic> d) async => ...;
  @override
  Future<void> delete(String t, String id) async => ...;
  @override
  Future<void> clearAll(List<String> tables) async => ...; // Critical for secure logout
}
```

### B. The Remote Store (e.g. Supabase or REST)
```dart
class MyRemoteStore implements RemoteStore {
  @override
  Future<void> pushBatch(List<SyncEntry> entries) async => ...;
  @override
  Future<List<Map<String, dynamic>>> pullSince(String t, DateTime ts) async => ...;
}
```

---

## ⚡ 2. Initialize the Engine

Configure the `SyncEngine` with your schemas and security policies.

```dart
final sync = SyncEngine(
  local: MyLocalStore(),
  remote: MyRemoteStore(),
  queue: MyQueueStore(),
  timestamps: MyTimestampStore(),
  tables: ['workouts', 'profiles'],
  config: const SyncConfig(
    sensitiveFields: ['password', 'ssn'], // 🛡️ Automasking for PII
    useExponentialBackoff: true,          // 📶 Scalable retry logic
    batchSize: 50,                        // 🧠 Memory-efficient processing
  ),
);
```

---

## 🦾 3. Efficient Backgrounding

To keep your UI at 120 FPS during massive data pulls (e.g., 100k rows), use the `IsolateSyncEngine`:

```dart
final manager = IsolateSyncEngine(sync);

// Runs in a dedicated background worker
await manager.syncAllInBackground(); 
```

---

## 🛡️ 4. Security Practices

### The "Session Void" Pattern
Ensure you call logout explicitly to purge sensitive un-synced data on shared devices:

```dart
await sync.logout(); // Triggers table-scoped local wiping
```

### JSON Exfiltration Prevention
Set `maxPayloadBytes` in the config to prevent oversized accidental writes from jamming your sync pipeline.

---

## 📚 What's Next?
*   Read the **[🏟️ Architecture Guide](architecture.md)** for protocol deep-dives.
*   Check the **[🛡️ Security Audit](security_audit.md)** for the 42 attack vectors.
*   Explore **[example/example.dart](../example/example.dart)** for a complete Supabase integration sample.

---

*Battle-Tested by [dynos.fit](https://dynos.fit)*

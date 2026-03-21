# Security and Improvement Report: `dynos_sync`

Based on a review of the complete `dynos_sync` codebase (including the newly added engine and adapter implementations), here are the identified security leaks, architectural issues, and suggested improvements:

## 🚨 Critical Security Leaks

### 1. Massive SQL Injection Vulnerability (`DriftLocalStore`)
The `DriftLocalStore.upsert` method constructs a raw SQL query by directly interpolating the `table` name and `data.keys` (columns) without escaping or sanitizing them:
```dart
final columns = data.keys.toList();
await _db.customStatement(
  'INSERT OR REPLACE INTO $table (${columns.join(', ')}) VALUES ($placeholders)',
  values,
);
```
**Risk:** This is a textbook SQL injection vulnerability. If a malicious payload is pulled from a compromised remote server, or if a user inputs a malicious dictionary key (e.g. `{"id) VALUES (1); DROP TABLE users; --": "value"}`), it will execute arbitrary SQL on the device, leading to complete local database destruction or data exfiltration.
**Improvement:** You must properly escape column and table names by wrapping them in double-quotes (`"${col}"`), or strictly validate them against a schema allowlist before constructing the query.

---

## 🔒 Additional Security Risks

### 2. Lack of Encryption at Rest (Local Storage)
The `LocalStore` and `QueueStore` interfaces deal with raw `Map<String, dynamic>` payloads. 
**Risk:** If a developer uses a standard SQLite/Drift database, the synced data sits unencrypted on the device. Malicious actors with physical access or relying on local exploits could read sensitive queued data.
**Improvement:** Introduce encryption hooks or a `PayloadSerializer` interface in `SyncConfig` so developers can encrypt data before it is written to the local queue.

### 3. Authentication State and Token Expiry
The `SupabaseRemoteStore` holds a fixed client and `userId` context limit.
**Risk:** If a user's session expires during a background sync, or if users switch accounts on the same device, the `SyncEngine` might attempt to push data to the wrong user's remote, or fail with unhandled auth errors, potentially leaving sensitive data stuck in the queue.
**Improvement:** Provide a mechanism to inject or refresh authentication context dynamically per sync cycle.

### 4. No Schema Validation at the Queue Level
**Risk:** Without schema validation before enqueueing, malformed or malicious data can be queued. 
**Improvement:** The client should enforce schema validation before enqueueing to prevent poisoned queues that will consistently fail remote validation.

---

## 🛠 Architectural / Logical Flaws

### 5. Critical Race Condition: Overwriting Un-synced Local Edits
In `SyncEngine._pullTable`, incoming remote rows unconditionally invoke `local.upsert(table, id, row)`, overwriting whatever is in the local database.
**Risk:** If a user makes an offline edit (queued locally) and then launches the app, `pullAll` might run before `drain` finishes. The remote pull will overwrite the user's un-synced local edit on the UI layer. However, because the queue still holds a snapshot of the user's edit, it will eventually push that older snapshot to the server, overriding the newer remote data.
**Improvement:** Implement conflict resolution. Before `local.upsert` in a pull, the engine should check `queue.getPending()` for that specific `table` and `id`. If a pending write exists, either ignore the incoming remote change (Client-Wins) or handle the merge appropriately. 

### 6. Swallowed Errors in `SupabaseRemoteStore`
In `getRemoteTimestamps()`, any exception retrieving timestamps is caught and silently ignored: `catch (_) { return {}; }`.
**Risk:** A misconfigured trigger or transient network failure will be silently swallowed. The engine will fallback to returning an empty map, which causes `SyncEngine.pullAll` to perform a full sync (`pullSince(epoch)`) for every table. This will cause massive, unexpected bandwidth spikes and server load.
**Improvement:** Log the error or rethrow it in a way that respects `SyncConfig.stopOnFirstError`, rather than silently degrading into expensive full syncs.

### 7. `InMemoryTimestampStore` Risk in Production
`InMemoryTimestampStore` resets on every app launch.
**Risk:** If accidentally used in production, the engine will assume it has never synced and will attempt a full data pull every time the app opens.
**Improvement:** Add a highly visible `@visibleForTesting` annotation or move it to a purely testing package.

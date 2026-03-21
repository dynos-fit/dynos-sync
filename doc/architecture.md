# 🏟️ Dynos Sync Engine Architecture

The **dynos_sync** engine is a high-scale, production-hardened offline-first synchronization protocol. It is designed to handle extreme ingestion rates (50,000+ records/sec on mobile hardware) while maintaining 100% data integrity and security.

---

## 🏗️ Core Components

### 1. `SyncEngine` (The Orchestrator)
The central entry point. Responsibilities include:
* **Optimistic Local Writes**: Validating and writing data to local storage while immediately queuing it for sync.
* **The High-Speed Ingestion Gate**: Applying PII masking and RLS (Row Level Security) checks locally before any data is persisted.

### 2. `IsolateSyncEngine` (The Performance Tier)
Wraps the core logic in a dedicated Dart `Isolate`.
* **Zero-Jitter UX**: Ensures that heavy sync operations (push/pull batches of 100k+ rows) never block the UI thread.
* **Background Sync**: Runs even when the main app UI is busy with complex animations or computations.

### 3. `QueueStore` & `SyncEntry` (The Persistence Tier)
The reliable 'Truth Layer' for offline changes.
* **Transactional Ordering**: Ensures local changes are pushed in the exact order they occurred.
* **Resilient Retry Logic**: Manages exponential backoff (2, 4, 8s) automatically for failed network calls.

---

## 📡 The Sync Protocol

### I. The "Ordered Push" (Write Path)
1. **Scrub**: PII sensitive fields are redacted.
2. **Local Write**: Persisted to the client database (e.g., Drift).
3. **Queue**: Encapsulated in a `SyncEntry` and persisted for the outgoing pipeline.
4. **Immediate Attempt**: A best-effort push is attempted. If it fails (offline), the `drain()` cycle picks it up later.

### II. The "Smart-Gate Pull" (Read Path)
Instead of pulling everything, dynos_sync uses a **Timestamp Delta Gate**:
1. **Timestamp Check**: Lightweight call to fetch all remote table timestamps.
2. **Comparison**: Compare against local timestamps.
3. **Selective Pull**: Only tables where `RemoteTS > LocalTS` are pulled.
4. **Conflict Resolution**: Incoming data is merged based on the active `ConflictStrategy`.

---

## 🛡️ Hardened Security Gates

The engine enforces **4 levels of security** before any bit hits the wire:
1. **JSON Validation**: Payload size limits prevent overflow attacks.
2. **PII Masking**: Secrets are redacted from payloads automatically.
3. **RLS Bypass Check**: Locally blocking writes that spoof `user_id`.
4. **Auth Expiry Hook**: Emits events to the UI if a sync fails due to expired tokens.

---

*Battle-Tested by [dynos.fit](https://dynos.fit)*

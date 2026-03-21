# Hardening Prompt: DynosSync "Military Grade" Upgrades 🛡️

Use this prompt with **Claude Code** (or another agentic AI) to upgrade the `dynos_sync` package for high-security enterprise environments.

---

## 🚀 Execution Instructions

**Task: Harden the `dynos_sync` package for Military-Grade Security & Scalability**

I need you to refactor the current `dynos_sync` engine to close five critical architectural gaps identified during a security audit. Please perform the following changes:

### 1. Implement Unified Atomic Transactions
Currently, `SyncEngine.write` performs local DB writes and sync-queue insertions as independent operations. 
*   **Change**: Update `SyncEngine.write` and `SyncEngine.remove` to support an optional `QueryExecutor` or `TransactionExecutor`. 
*   **Goal**: Ensure that if a crash occurs between the local write and the sync-queue entry, the entire operation is rolled back (Atomic Consistency).

### 2. Add Automation & Exponential Backoff
The current `drain()` method is stateless and manual.
*   **Change**: Add a `RetryStrategy` to `SyncConfig` (e.g., `ExponentialBackoff`). 
*   **Goal**: If `remote.push()` fails, the engine should automatically schedule an internal retry after 2s, 4s, 8s, up to `config.maxRetries`. Add a `pauseAll()` method to the engine for when a `429 Too Many Requests` is detected.

### 3. Implement PII Field Masking (Data Sanitization)
Prevent sensitive information from leaking into sync logs or remote telemetry.
*   **Change**: Add `List<String> sensitiveFields` to `SyncConfig`. 
*   **Goal**: Create a utility to deep-clone the sync `payload` and mask any keys found in `sensitiveFields` (e.g., replace with `[REDACTED]`) before the payload is passed to the `onError` callback or any logging layer.

### 4. Background Isolate Wrapper (`IsolateSyncEngine`)
Large JSON syncs (10k+ records) currently block the UI thread.
*   **Change**: Create a new class `IsolateSyncEngine` that implements the standard `SyncEngine` interface but spawns a background `Isolate` for all `drain`, `pull`, and `write` operations.
*   **Goal**: Zero frame drops on the UI thread during heavy background syncing.

### 5. Hardened Drift Adapter (SQLCipher Ready)
Provide a clear path for AES-256 encryption.
*   **Change**: Create a `HardenedDriftStore` base class that requires a `GeneratedDatabase` with `Delegate` support for `SqlCipher`. Add documentation for setting up hardware-backed key storage.

---

## ⚖️ Quality Rules

- **Backward Compatibility**: DO NOT break existing interfaces; use optional parameters or new factory methods.
- **Testing**: Update `test/dynos_sync_security_test.dart` to verify these new hardening features (e.g., simulate a transaction failure).
- **Docs**: Ensure all new methods are documented in the `README.md` and `example/example.dart`.
- **Privacy**: The sanitization layer should be active **before** any error reporting (Sentry/LogRocket).

---

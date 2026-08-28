# CHANGELOG

## 0.1.8 (2026-08-28)
*   **Fix (data corruption)**: `SyncEngine.write()` and `SyncEngine.push()` no longer apply `SyncConfig.sensitiveFields` masking to the payload that is persisted locally and queued for remote push. Any field listed in `sensitiveFields` was silently replaced with the literal string `'[REDACTED]'` in the local store (`write()` path) and in every pushed payload — permanently destroying the real values on the remote, or failing the push outright on non-text columns (e.g. `numeric`/`double precision` reject the string, leaving the queue stuck retrying). Masking now applies **only** where it was documented to: error contexts passed to `onError` and emitted sync events. Callers who need a field kept off the server entirely should omit it from the payload.
*   Updated the three tests that asserted masked payloads were stored/pushed; added regression tests pinning real-value passthrough for both `write()` and `push()`.

## 0.1.7 (2026-08-27)
*   **Fix (data integrity)**: `SyncEngine._pullTable` now derives each table's delta watermark from the newest **server** `updated_at` in the pulled rows, instead of the device wall clock (`DateTime.now()`). A device whose clock ran ahead of the server would persist a future watermark, after which `pullSince`'s `updated_at > since` filter silently skipped every row the server committed in the gap — unbounded, permanent data loss. If no pulled row carries a parseable `updated_at`, the watermark is left unchanged (safe re-pull) rather than guessing `now()`.
*   Added `test/watermark_clock_skew_test.dart` regression suite.

## 0.1.6 (2026-03-28)
*   **Real background isolate**: `IsolateSyncEngine` now uses `Isolate.run()` with an `engineFactory` constructor for true off-main-thread sync. Previous implementation was a non-functional stub.
*   **Dead code removal**: Removed unused `_getRetryDelay` helper from `SyncEngine`.
*   **Test audit**: Updated test suite header to correctly reflect 140 tests across 13 categories.

## 0.1.5 (2026-03-22)
*   **Patch operation**: Added `SyncOperation.patch` for partial updates. Sends UPDATE instead of upsert, avoiding NOT NULL constraint failures when only a few fields change.
*   Updated `SupabaseRemoteStore` to handle patch in both `push()` and `pushBatch()`.

## 0.1.4 (2026-03-22)
*   **100% dartdoc coverage**: Added documentation comments to all 225 public API elements.

## 0.1.3 (2026-03-22)
*   **Runtime table management**: `addTable()` and `removeTable()` allow registering/unregistering sync tables after engine creation.
*   **130-test security audit**: Comprehensive audit across 12 categories (HIPAA, GDPR, OWASP Mobile Top 10, injection, flood testing, chaos engineering, conflict resolution, race conditions, denial of service).
*   **Updated documentation**: README rewritten with complete API reference. Architecture and security docs rewritten for developers.

## 0.1.2 (2026-03-21) - Global Open Source Milestone
*   **License Shift**: Transitioned from BSL-1.1 to **MIT License** for unrestricted public use.
*   **Score Optimization**: Now achieving **100/100 Points** on pub.dev.

## 0.1.1 (2026-03-21)
*   **Corrected Metadata**: Finalized hyphenated repository URL for pub.dev analysis.
*   **Performance Stability**: Verified 50k+ writes/sec ingestion.

## 0.1.0 (2026-03-21)

Initial Public Release.
*   **Production-Hardened Engine**: Subjected to a 42-point security audit.
*   **High-Scale Ingestion**: High-performance local writes (50k+ writes/sec).
*   **Advanced Privacy**: Built-in PII redaction and secure session purging.
*   **Background Efficiency**: Full support for dedicated Background Isolates.

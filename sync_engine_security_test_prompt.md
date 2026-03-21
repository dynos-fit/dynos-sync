# dynos_sync — Ruthless Security Test Generation Prompt

---

**Paste everything below this line into Google Gemini:**

---

You are the world's most ruthless cybersecurity penetration tester, data-leak hunter, and performance engineer. You have been hired to destroy — not defend — a Flutter package called `dynos_sync`.

## What the package does

It is an **offline-first sync engine** for Flutter apps. The architecture is:

1. All writes go to a **local database first** (Drift / SQLite).
2. A background sync queue silently pushes pending changes to **Supabase** (or any REST/Realtime backend).
3. When the device comes back online, the queue drains automatically.
4. Conflicts between local and remote are resolved via a configurable strategy (last-write-wins, server-wins, merge).
5. The engine supports **multi-user sessions** on the same device (logout → login as different user).
6. It exposes streams/listeners so the UI layer (Riverpod) can react to sync state.

The package name is `dynos_sync`. The main class is `DynosSync`. The stack is: **Flutter + Drift (SQLite) + Supabase + Riverpod**.

---

## Your mission

Generate a **comprehensive, production-grade Dart test file** (`dynos_sync_security_test.dart`) using `flutter_test` that covers **every single category below**. Each test must have:

- A descriptive name that states the attack vector or failure mode.
- A comment explaining **why** this matters and what the real-world exploit looks like.
- Concrete setup → act → assert logic (mock what you need to, but keep tests realistic).
- Severity tags: `// SEVERITY: CRITICAL | HIGH | MEDIUM | LOW`

---

## CATEGORY 1 — DATA LEAKS (Cross-User Isolation)

Write tests that prove data **cannot leak between users on the same device**:

1. After User A logs out, User B logs in — User B must see **zero** of User A's local records across ALL tables (workouts, profiles, body_stats, settings, everything).
2. The **sync queue** must be fully purged on logout. If User A had 50 unsynced records and logs out, those 50 records must NEVER be pushed to the backend under User B's auth token.
3. After logout, the **raw SQLite file on disk** must not contain plaintext PII (email, phone, name) from the previous user. Read the actual bytes of the `.db` file and string-scan it.
4. If the engine supports **Supabase Realtime subscriptions**, verify that after logout, no Realtime channel from User A's session is still open leaking row changes to User B's callback.
5. **Shared device cache**: If the engine caches any sync metadata (last sync timestamp, cursor, etc.), verify it's scoped per user — not global.

---

## CATEGORY 2 — DATA LEAKS (Payload & Log Exposure)

Write tests that prove **sensitive data doesn't escape through side channels**:

6. Auth tokens (JWT, API keys) must NEVER appear inside sync record payloads. They belong in HTTP headers only. Serialize the outgoing payload to JSON and regex-scan for token patterns.
7. Sync **error logs** must not dump full record contents. Force a sync failure and capture all logger output — scan for PII patterns (emails, phone numbers, passwords).
8. **Stack traces** on sync failure must not contain raw SQL queries with interpolated user data.
9. If the engine writes a **sync_log** table locally for debugging, that table must be excluded from the sync push (it should never reach the server).
10. **HTTP request/response bodies** on retry: if the engine retries a failed push, the retry payload must be identical to the original (no accidental double-wrapping, no auth token drift into body).

---

## CATEGORY 3 — SECURITY (Injection & Tampering)

Write tests that prove the engine is **hardened against malicious input**:

11. **SQL Injection via record fields**: Insert records where field values are classic SQL injection strings (`'; DROP TABLE workouts; --`, `' UNION SELECT * FROM auth --`, `1 OR 1=1`). Verify the data is stored as a literal string AND that all other tables survive intact.
12. **Oversized payloads**: Insert a record with a 50MB string field. The engine must either reject it locally with a clear error, or truncate safely — it must NOT crash, OOM, or silently corrupt the DB.
13. **Malformed JSON in sync response**: Mock the backend returning `{corrupt json` or `<html>502 Bad Gateway</html>`. The engine must not crash, must log the error, and must NOT mark the record as synced.
14. **Tampered server response**: Mock the backend returning a sync response that tries to **overwrite a different user's record** (userId mismatch). The engine must reject it.
15. **Replay attack on sync**: Send the same sync acknowledgement twice. Verify the engine doesn't double-apply it (e.g., incrementing a counter twice).
16. **Null / empty / special character fields**: Test with `null`, empty string `""`, unicode `"💪🏽"`, RTL text `"مرحبا"`, zero-width characters, and extremely long strings (100K chars). None of these should break serialization or deserialization.

---

## CATEGORY 4 — SECURITY (Authentication & Authorization)

Write tests that prove **auth boundaries are enforced**:

17. If the auth token expires mid-sync, the engine must **stop pushing**, surface a re-auth event, and NOT silently drop records.
18. If someone manually calls `dynosSync.forcePush()` without being logged in, it must throw or return an error — never push with a null/empty auth header.
19. **Row-Level Security bypass attempt**: If the engine sends a Supabase INSERT for a row where `userId != currentUser.id`, verify the engine **rejects it locally before it even hits the network**.
20. After logout, ALL in-memory references to the previous auth token must be nulled. Access `dynosSync.currentToken` after logout — it must be `null`, not the stale JWT.

---

## CATEGORY 5 — CONFLICT RESOLUTION INTEGRITY

Write tests that prove **conflict resolution doesn't silently eat data**:

21. **Last-Write-Wins correctness**: Create a record locally at T=1, mock the server having a version at T=2. After sync, the server's version must win. Then reverse it (local T=2, server T=1) — local must win.
22. **Clock skew attack**: Set the local device clock 1 year in the future. Create a record. Fix the clock. The record's timestamp should NOT cause it to permanently "win" every future conflict.
23. **Simultaneous conflicting edits to the same field**: User A edits `workout.name` to "Push" locally. Server has it as "Pull". After conflict resolution, EXACTLY ONE value must survive — no concatenation, no empty string, no crash.
24. **Conflict on DELETE vs UPDATE**: User A deletes a record locally. Server has an update for the same record. What wins? The engine must have a deterministic policy and this test must assert it.
25. **Conflict callback fires**: If the engine supports an `onConflict` callback/stream, verify it fires with both versions of the record so the app layer can react.

---

## CATEGORY 6 — PERFORMANCE BOTTLENECKS

Write tests that prove **the engine doesn't choke under load**:

26. **Bulk insert throughput**: Insert 10,000 records locally in a loop. Measure total time. Assert it completes in under 5 seconds (or whatever reasonable threshold). Log records/second.
27. **Sync queue drain speed**: Queue 1,000 records offline, then go online. Measure time to fully sync. Assert it completes in under 30 seconds. Verify the engine batches requests (not 1 HTTP call per record).
28. **Memory pressure during large sync**: Queue 10,000 records, start syncing, and monitor peak memory. The engine must NOT load all 10K records into memory at once — it must paginate/stream.
29. **UI thread blocking**: During a sync of 1,000 records, measure main isolate frame time. The sync must NOT cause jank (frame time > 16ms). All heavy work must be on a background isolate.
30. **Rapid online/offline toggling**: Toggle connectivity 100 times in 10 seconds while the engine has pending records. It must NOT crash, leak listeners, spawn duplicate sync jobs, or corrupt the queue.
31. **Concurrent writes during sync**: While a sync push is in-flight, insert 100 new records locally. These new records must NOT be included in the current in-flight batch (they should wait for the next cycle). No data loss.
32. **Database lock contention**: From two isolates simultaneously, write to the local DB. Verify no `database is locked` exceptions and no data loss — Drift's write-ahead logging should handle this, but test it.
33. **Cold start sync time**: Kill the app, relaunch. Measure time from `DynosSync.init()` to "sync state = idle". With 5,000 unsynced records, this must complete in under 3 seconds.
34. **Exponential backoff verification**: Force 10 consecutive sync failures. Capture the delay between each retry. Assert that delays increase exponentially (not linear, not instant) and cap at a max ceiling (e.g., 60 seconds).

---

## CATEGORY 7 — EDGE CASES & CHAOS

Write tests for the weird stuff that happens in production:

35. **App killed mid-sync**: Simulate `exit(0)` while a batch is in-flight. On next launch, verify: no records were lost locally, no partial/corrupt records on server, sync resumes cleanly.
36. **Backend returns HTTP 200 but empty body**: The engine must treat this as a failure, not silently mark records as synced.
37. **Backend returns HTTP 200 but with an error payload** (`{"error": "rate limited"}`): Same — must not mark as synced.
38. **Supabase maintenance mode (HTTP 503 for 5 minutes)**: The engine must queue, retry with backoff, and eventually drain when service returns — zero data loss.
39. **Device storage full**: When the local DB write fails due to disk space, the engine must surface a clear error to the UI, NOT silently drop the record.
40. **Timezone change mid-session**: User flies from NYC to Tokyo. Timestamps on records created before and after the timezone change must still be consistent (UTC-based).
41. **Schema migration with unsynced data**: The local DB schema is upgraded (new column). 500 records in the sync queue were written under the OLD schema. The engine must migrate them or handle gracefully — no crash, no data loss.
42. **Deeply nested JSON fields**: A record contains a JSON field with 10 levels of nesting and arrays of 1,000 elements. Serialization/deserialization must not stack overflow or silently truncate.

---

## OUTPUT FORMAT

Return a single, complete, well-structured Dart test file that:

- Uses `flutter_test` and `group()` / `test()` structure.
- Groups tests by the 7 categories above.
- Uses descriptive test names with the attack vector in the name.
- Includes `// SEVERITY: CRITICAL | HIGH | MEDIUM` comments.
- Mocks network calls (use `MockHttpClient` or equivalent — do NOT make real network calls).
- Mocks the Supabase client.
- Provides helper functions at the top for common setup (create `DynosSync` instance, login, seed data, etc.).
- Includes timing assertions using `Stopwatch` for performance tests.
- Includes memory measurement helpers for memory pressure tests.
- Compiles against Dart 3.x.
- Is ready to paste into a project and adapt with minimal wiring.

Do NOT be gentle. Do NOT skip edge cases. Do NOT assume anything works correctly. Test like the developer who wrote this engine is your enemy and is actively trying to hide bugs from you.

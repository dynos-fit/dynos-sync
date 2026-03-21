# ❓ dynos_sync FAQ

Common questions and troubleshooting for the **dynos_sync** engine.

---

## 🛠️ General Questions

### **Q: Does this replace my local database?**
**A: No.** `dynos_sync` is a **headless** layer. It sits between your existing local database (Drift, Hive, Isar) and your remote API. You use your database normally; the engine simply mirrors those changes to the remote backend.

### **Q: What is "Ordered Ingestion"?**
**A: Data Reliability.** Unlike libraries that push data in parallel chunks, `dynos_sync` preserves the **causal ordering** of your writes. This prevents race conditions where a record is "deleted" before it's even "created" on the server.

### **Q: How does it handle 100,000 records?**
**A: Through Delta-Pulling.** Instead of fetching all data, the engine checks remote table timestamps. If `RemoteTS == LocalTS`, zero data is pulled. Only modified tables are fetched in memory-efficient batches.

---

## 🛡️ Security & Privacy

### **Q: What happens if the user logs out while offline?**
**A: The Session Purge protocol.** When `logout()` is called, we call `local.clearAll([tables])`. This ensures that if User B logs into the same shared device, they cannot see User A's un-synced local data.

### **Q: Where is my data masked?**
**A: On the edge.** Masking happens **locally on the device** before the JSON is even written to the sync queue. Your sensitive PII never leaves your device's boundary in plain text.

---

## 🚀 Performance & UI

### **Q: Will syncing block my UI thread?**
**A: Not if you use isolates.** Wrap your engine in `IsolateSyncEngine` to offload all JSON serialization, deep-cloning, and PII masking to a dedicated background worker.

### **Q: My sync is stuck. How do I clear it?**
**A: Check the Queue.** If a "poison pill" (a record that repeatedly fails) is blocking the queue, you can inspect it via `queue.getPending()` and either delete it or increase `maxRetries` in your `SyncConfig`.

---

## 🤝 Support & Licensing

### **Q: Can I use this for free?**
**A: Yes!** If you are a startup with <$5M ARR/Funding or a non-commercial dev, the **Community Tier** is 100% free under the Business Source License (BSL).

---

*Secured by [dynos.fit](https://dynos.fit)*

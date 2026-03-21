# 🔱 Pull Request Template

**Thank you for contributing!** Please ensure your PR meets the 'High-Reliability' criteria before submission.

---

### Description
<!-- Summarize your changes and the value they add to the sync engine. -->

### 🧩 Category Checkpoint
- [ ] **Data Isolation**: Does this change impact how user data is stored/purged?
- [ ] **Performance**: Have you verified there is no UI thread jank?
- [ ] **Privacy**: Are you sanitizing sensitive fields?

### 🧪 Security Audit (Mandatory)
- [ ] I have run `dart test test/dynos_sync_security_test.dart` and all **42 attack vectors** are passing.
- [ ] I have added new tests covering the failure modes of this feature.

### 📚 Documentation
- [ ] I have updated the `README.md` (if applicable).
- [ ] I have updated the `example/` code.

---

*Verified by dynos maintainers.*

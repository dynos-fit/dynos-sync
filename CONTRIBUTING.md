# Contributing to dynos_sync 🤝

Thank you for your interest in improving `dynos_sync`! To maintain our status as a high-reliability synchronization engine, we follow a rigorous contribution process.

---

## 🚀 How to Contribute

### 1. Reporting Bugs
- Use the **GitHub Issue Tracker**.
- Provide a **Minimal Reproducible Example** (Dart/Flutter).
- Include your environment details (OS, Dart version, DB adapter).

### 2. Pull Requests
1.  **Fork the repository** and create your branch from `master`.
2.  **Run the Analysis**: Ensure `dart analyze` passes with zero warnings.
3.  **Audit Mandate**: You must run the full security suite before submitting:
    ```bash
    dart test test/dynos_sync_security_test.dart
    ```
4.  **Update Documentation**: If you add a feature, update the `README.md` and `example/`.
5.  **Clean Commits**: Use descriptive, imperative commit messages (e.g., `feat: add retry pause state`).

---

## 🛠️ Development Setup

```bash
# Get dependencies
dart pub get

# Run all tests
dart test

# Check formatting
dart format .
```

## ⚖️ Our Standards
- **Zero Frame Drops**: Never perform blocking work on the main UI thread.
- **Atomic Integrity**: Every write must be transactional.
- **Data Privacy**: Always sanitization sensitive fields before logging.

---

*Thank you for helping us build the world's most reliable sync engine!* 🛡️🦾

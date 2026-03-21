# Security Policy 🛡️🤖

`dynos_sync` is built with a **Security-First** philosophy. We appreciate the research and testing performed by the data security community to help us maintain a high-reliability synchronization ecosystem.

---

## 🚀 Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | ✅ Active Support   |
| < 0.1.x | ❌ End of Life      |

## 🔱 Reporting a Vulnerability

**DO NOT OPEN A GITHUB ISSUE** for suspected security vulnerabilities.

Please report suspected vulnerabilities directly via the **Project Repository's 'Security' tab (Private Reporting)** or by contacting the maintainer via the secure email listed in the profile.

We investigate all reports and aim to provide a remediation plan within **48 hours**.

### 🔍 Scope of Security
We are particularly interested in reports covering:
1.  **Cross-User Data Leaks**: Evidence of data surviving logout or leaking into separate auth sessions.
2.  **PII Exfiltration**: Evidence of sensitive fields bypassing the `redaction` layer into logs or telemetry.
3.  **Sync-Queue Hijacking**: Forged writes or unauthorized push attempts.
4.  **SQL Injection**: Bypass of the literal-string hardening in Drift/SQL stores.

## ⚖️ Our Response Process
1.  **Acknowledgment**: 24-48 hours.
2.  **Investigation**: 2-5 business days.
3.  **Patch & Advisory**: Vulnerabilities will be patched in a minor release, followed by a public Security Advisory describing the fix.

---

*Thank you for helping us keep dynos_sync production-hardened!* 🏢🔱

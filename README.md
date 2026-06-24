# IT_Scripts

A curated collection of automation and administration scripts I've developed and
refined over time to support endpoint security, system compliance, cloud identity
management, and general IT operations.

Targets a variety of platforms and tooling — Windows PowerShell, macOS, and
cross-platform Bash — with an emphasis on:

- **Idempotent design** — safe to run repeatedly
- **Structured output** — CSV/JSON reports + logs
- **Self-contained tooling** — minimal external dependencies
- **Operational readiness** — exit codes suitable for MDM/automation pipelines (Intune, Addigy)

## Contents

| Folder | What's inside |
|--------|---------------|
| [`mac-migrate/`](mac-migrate/) | Portable, encrypted migration of a Mac dev environment (tool configs + credentials) to a new machine, with a restore + verification test suite. |
| [`m365-exchange/`](m365-exchange/) | Microsoft 365 / Exchange Online automation — bulk mailbox provisioning. |
| [`atlassian/`](atlassian/) | Atlassian admin tooling — inactive-license audit for seat reclamation. |
| [`duo-mfa/`](duo-mfa/) | Duo MFA detection and remediation (PowerShell). |
| [`macos/`](macos/) | macOS compliance checks, SentinelOne activation, security scanners, and an AirDrop→SIEM log collector. |
| [`intune-win32/`](intune-win32/) | Microsoft Intune Win32 app packaging — install/detect scripts for Claude Code and portable Git. |
| [`teamviewer/`](teamviewer/) | TeamViewer MDM deployment examples — assignment and conditional-access scripts. |

> These are generic, sanitized reference implementations. Identifiers (bundle
> IDs, org names, tenant/assignment IDs, signing identities, API tokens) are
> placeholders — supply your own before deploying.

Each folder has its own README or header docs. See [`mac-migrate/README.md`](mac-migrate/README.md)
for the migration toolkit.

## License

[MIT](LICENSE) © 2026 Brenden Matos

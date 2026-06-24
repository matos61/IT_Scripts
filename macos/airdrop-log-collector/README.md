# airdrop-log-collector

Parses macOS unified logs for AirDrop transfer events and forwards structured
records to a SIEM. Runs as a `LaunchDaemon` and ships as a signed `.pkg`.

Useful for security teams that need visibility into AirDrop file sharing on
managed Macs (who shared what, when, transfer/state IDs, filenames).

## Files
| File | Purpose |
|------|---------|
| `airdrop_log_collector.py` | Parses `log show` output, extracts AirDrop events, posts to SIEM. |
| `com.example.airdrop.monitor.plist` | LaunchDaemon definition. |
| `install.sh` / `uninstall.sh` | Place/remove the daemon + script. |
| `build_pkg.sh` | Build an installer `.pkg` (sign with your Developer ID). |
| `CHANGES.md` | Version notes + operational commands. |

## Configure
SIEM endpoint lives in `/Library/Application Support/airdrop-monitor/siem.conf`.
Replace the `com.example.airdrop.monitor` bundle identifier and the
`Developer ID Installer: Example Inc (TEAMID)` signing identity with your own.

> Generic example — bundle IDs, org names, and signing identities are
> placeholders. Supply your own before deploying.

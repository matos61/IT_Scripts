# AirDrop Log Collector — Jamf deployment changes

Handoff notes for the original author. This documents the changes made to the deployment layer to get the tool installing cleanly via Jamf Pro. **The collector and the launchd plist were not touched.** Everything here is about packaging and Jamf wiring.

## Why the change was needed

The original DEPLOY.md describes shipping a zip with all four files co-located, with `install.sh` doing everything (copy files into place, write `siem.conf` from Jamf parameters 4/5, load the daemon). The intended path was to wrap that zip into a payload-free pkg and run `install.sh` as the postinstall.

That doesn't work, for one specific reason: **Jamf policy script parameters (`$4`–`$11`) are only passed to Script objects attached to a policy. They are never passed to a package's preinstall/postinstall scripts.** So the SIEM URL and API key — which the design deliberately delivers at install time rather than embedding — would arrive empty inside a package postinstall, and `install.sh` would fail its parameter preflight on every host.

The fix splits the one artifact into two, along the line that the parameter mechanism forces:

- A **pkg** that lays down only the static files (collector + plist). No secrets, no daemon load.
- A **Jamf Script object** (the trimmed `install.sh`) that receives parameters 4/5, writes `siem.conf`, and loads the daemon.

A single install policy runs both: the package installs first, then the script runs "After."

## What stayed the same

The end state on each Mac is identical to the original design:

- Same four paths, same perms (`755`/`644`/`600 root:wheel`).
- The SIEM API key is still never in the package; it still arrives via Jamf parameters 4/5 at install time and is still written to `siem.conf` on the endpoint by a root script.
- The install status file, Extension Attribute values (`SUCCESS`/`FAILED`/`UNINSTALLED`/`NOT_FOUND`), uninstall semantics, and the `observer.version` rollout check all behave as documented.

Only the *division of labour* changed: the pkg lays down the static files; the script handles secrets + daemon load. Previously `install.sh` did both.

## Script changes

### install.sh (now a Jamf Script object, not a postinstall)

Removed:
- `SCRIPT_DIR`, `SCRIPT_SRC`, `PLIST_SRC` variables.
- Both `cp` blocks (collector and plist) and the `install -d` / `chown` / `chmod` operations on the copied files. The pkg does this now.
- The preflight checks for source files next to the script (`[[ -f "$SCRIPT_SRC" ]]` etc.) — there are no companion files next to a Jamf Script object at runtime; Jamf drops only the script text into a temp dir.

Added:
- A **payload preflight** that checks the *destination* paths exist (`SCRIPT_DEST`, `PLIST_DEST`). If the package payload didn't land — e.g. the Packages payload failed, or the Scripts payload was left on "Before" so it ran ahead of the package — the script records `STATUS=FAILED` with a clear `DETAIL` instead of bootstrapping a broken daemon.

Changed:
- Daemon load switched from the deprecated `launchctl load` / `launchctl start` to the modern `launchctl bootout` → `bootstrap` → `enable` → `kickstart` sequence, with verification via `launchctl print system/<label>`. (`launchctl list` is still used only to scrape the last exit code for the status file.)

Unchanged: the `siem.conf` write and its `600` perms, the log directory, the status-file format, and the `log()` / `fail()` helpers.

See `install.sh` (attached).

### uninstall.sh

A pkg leaves a receipt that the old zip flow never did, so the uninstall needs one extra line to fully clear state for a clean `UNINSTALLED` result. Add this after the daemon is unloaded and files are removed:

```bash
pkgutil --forget com.example.airdrop.monitor 2>/dev/null || true
```

Everything else in `uninstall.sh` is unchanged, including the optional `--purge-logs` behaviour on Parameter 4.

## New build artifact

`build_pkg.sh` (attached) turns the existing zip into a Jamf-ready pkg. It deliberately excludes `install.sh` from the package — that file becomes the Jamf Script object instead.

```bash
chmod +x build_pkg.sh
./build_pkg.sh ~/Downloads/airdrop-monitor.zip
# version auto-detected from __version__, or override:
./build_pkg.sh ~/Downloads/airdrop-monitor.zip 1.2.0
```

It stages the collector + plist with the documented perms and runs `pkgbuild --ownership recommended` (which yields `root:wheel` under `/Library`), then prints the payload listing. Output lands in `~/Downloads/airdrop-monitor-<version>.pkg`. Signing with a Developer ID Installer cert is supported (commented `productsign` line) but not required — the jamf binary installs as root and doesn't hit Gatekeeper.

## Jamf configuration changes vs the original DEPLOY.md

| Original DEPLOY.md | What it is now |
|---|---|
| One package containing all four files in a `Scripts/` folder | A **pkg** (collector + plist only) **and** a separate Jamf **Script object** for `install.sh` |
| Policy runs `install.sh` (with params 4/5) as the install action | Policy has a **Packages payload** (Install) **plus** a **Scripts payload** set to Priority **After**, with the URL/key entered as Parameter 4/5 *on the policy's Scripts payload* — not on the Script object |
| Parameter 5 "encrypted script parameters" toggle | Not a native Jamf toggle (see note below) |
| Uninstall = same package, separate policy running `uninstall.sh` | Uninstall = standalone Jamf **Script object** in its own policy (no package payload needed); `uninstall.sh` now also runs `pkgutil --forget` |
| — | **Maintenance payload → Update Inventory** added to both policies so the EA / smart group refresh immediately instead of at next recon |

Two operational additions worth carrying into the doc:

- The **Scripts payload Priority must be "After"** on the install policy. On "Before" (the default), the script runs ahead of the package and the new payload preflight will correctly fail the install.
- Parameter *values* live on the policy's Scripts payload. The Script object's Options tab holds only the parameter *labels* (Parameter 4 = "SIEM HEC URL", Parameter 5 = "SIEM API Key"). Putting the real values on the shared Script object both fails to deliver them at runtime and exposes the key to anyone with script-read access.

The Extension Attribute and the "install failed" smart group are unchanged from the original design.

### On "encrypted script parameters"

The original doc references marking Parameter 5 as encrypted. That isn't a native Jamf Pro feature. It refers to a community pattern where the value is encrypted with `openssl` and the salt/passphrase are embedded in the uploaded script, so the value can't be decrypted without both the policy and the script. Worth adopting for Parameter 5 — plaintext policy parameters are readable by anyone with policy access and appear in `ps` output while the script runs.

## DEPLOY.md sections that need editing

- **"What gets installed where"** — still accurate.
- **"Jamf policy setup" → step 1** — the "all four files co-located in `Scripts/`" requirement no longer applies. Replace with: build the pkg (collector + plist) and upload `install.sh` / `uninstall.sh` as separate Script objects.
- **"Jamf policy setup" → step 2** — note that the package installs first and the configure script runs "After," and that parameter values go on the policy's Scripts payload.
- **"Encrypted script parameters" line** — reword per the note above.
- **"Uninstall"** — note the standalone Script object (no package payload) and the added `pkgutil --forget`.

## Verification on first host

```
sudo jamf policy
pkgutil --pkg-info com.example.airdrop.monitor
sudo launchctl print system/com.example.airdrop.monitor
ls -l "/Library/Application Support/airdrop-monitor/siem.conf"   # expect 600 root:wheel
cat /var/log/airdrop-monitor/install_status.txt                  # expect STATUS=SUCCESS
```

Then confirm the EA populated in the computer record and events arrive in NG-SIEM with the expected `observer.version`.

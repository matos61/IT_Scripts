#!/bin/bash
# Jamf uninstall script — AirDrop Log Collector daemon
# Run as root. Pass --purge-logs to also remove /var/log/airdrop-monitor.

SUPPORT_DIR="/Library/Application Support/airdrop-monitor"
SCRIPT_DEST="${SUPPORT_DIR}/airdrop_log_collector.py"
PLIST_DEST="/Library/LaunchDaemons/com.example.airdrop.monitor.plist"
LOG_DIR="/var/log/airdrop-monitor"
STATUS_FILE="${LOG_DIR}/uninstall_status.txt"
DAEMON_LABEL="com.example.airdrop.monitor"
PURGE_LOGS=false

[[ "${*}" == *--purge-logs* ]] && PURGE_LOGS=true

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fail() {
    log "ERROR: $*"
    mkdir -p "$LOG_DIR"
    printf 'STATUS=FAILED\nDETAIL=%s\nTIMESTAMP=%s\n' "$*" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATUS_FILE"
    exit 1
}

[[ $EUID -eq 0 ]] || fail "Script must run as root"

# ── Stop & unload daemon ───────────────────────────────────────────────────────

if launchctl list "$DAEMON_LABEL" &>/dev/null; then
    log "Stopping daemon"
    launchctl stop   "$DAEMON_LABEL" 2>/dev/null || true
    log "Unloading daemon"
    launchctl unload "$PLIST_DEST"   2>/dev/null || true
else
    log "Daemon not loaded — skipping unload"
fi

# ── Remove files ───────────────────────────────────────────────────────────────

for f in "$PLIST_DEST" "$SCRIPT_DEST"; do
    if [[ -f "$f" ]]; then
        rm -f "$f" && log "Removed ${f}" || log "WARNING: could not remove ${f}"
    else
        log "Not found (already removed?): ${f}"
    fi
done

if [[ -d "$SUPPORT_DIR" ]]; then
    rm -rf "$SUPPORT_DIR" && log "Removed ${SUPPORT_DIR}" || log "WARNING: could not remove ${SUPPORT_DIR}"
fi

if $PURGE_LOGS; then
    log "Purging log directory → ${LOG_DIR}"
    rm -rf "$LOG_DIR"
    log "Log directory removed"
    exit 0
fi

# ── Record status (only if log dir still exists) ───────────────────────────────

mkdir -p "$LOG_DIR"
printf 'STATUS=UNINSTALLED\nDETAIL=Daemon stopped and files removed\nTIMESTAMP=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATUS_FILE"
log "Uninstall complete. Status → ${STATUS_FILE}"
exit 0

#!/bin/bash
# Jamf install script — AirDrop Log Collector daemon
# Run as root. Expects airdrop_log_collector.py and
# com.example.airdrop.monitor.plist to be co-located with this script.
#
# Jamf script parameters:
#   $4 = SIEM HEC URL  (e.g. https://<id>.ingest.eu-1.crowdstrike.com/services/collector/raw)
#   $5 = SIEM API key
# Source values from the 1Password SecOps vault item
# "CS SIEM: AirDrop Connection".

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_SRC="${SCRIPT_DIR}/airdrop_log_collector.py"
PLIST_SRC="${SCRIPT_DIR}/com.example.airdrop.monitor.plist"

SUPPORT_DIR="/Library/Application Support/airdrop-monitor"
SCRIPT_DEST="${SUPPORT_DIR}/airdrop_log_collector.py"
CONFIG_FILE="${SUPPORT_DIR}/siem.conf"
PLIST_DEST="/Library/LaunchDaemons/com.example.airdrop.monitor.plist"
LOG_DIR="/var/log/airdrop-monitor"
STATUS_FILE="${LOG_DIR}/install_status.txt"
DAEMON_LABEL="com.example.airdrop.monitor"

SIEM_URL="${4:-}"
SIEM_KEY="${5:-}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fail() {
    log "ERROR: $*"
    mkdir -p "$LOG_DIR"
    printf 'STATUS=FAILED\nDETAIL=%s\nTIMESTAMP=%s\n' "$*" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATUS_FILE"
    exit 1
}

# ── Preflight ──────────────────────────────────────────────────────────────────

[[ $EUID -eq 0 ]] || fail "Script must run as root"
[[ -f "$SCRIPT_SRC" ]] || fail "Source not found: ${SCRIPT_SRC}"
[[ -f "$PLIST_SRC"  ]] || fail "Plist not found: ${PLIST_SRC}"
[[ -n "$SIEM_URL"   ]] || fail "Missing Jamf parameter 4 (SIEM HEC URL)"
[[ -n "$SIEM_KEY"   ]] || fail "Missing Jamf parameter 5 (SIEM API key)"

# ── Install files ──────────────────────────────────────────────────────────────

log "Creating support directory → ${SUPPORT_DIR}"
install -d -m 755 -o root -g wheel "$SUPPORT_DIR"

log "Copying collector script → ${SCRIPT_DEST}"
cp "$SCRIPT_SRC" "$SCRIPT_DEST"         || fail "Failed to copy script"
chown root:wheel "$SCRIPT_DEST"
chmod 755 "$SCRIPT_DEST"

log "Writing SIEM config → ${CONFIG_FILE}"
umask 077
cat > "$CONFIG_FILE" <<EOF
SIEM_HEC_URL=${SIEM_URL}
SIEM_API_KEY=${SIEM_KEY}
EOF
chown root:wheel "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

log "Creating log directory → ${LOG_DIR}"
mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR"

log "Copying plist → ${PLIST_DEST}"
cp "$PLIST_SRC" "$PLIST_DEST"           || fail "Failed to copy plist"
chown root:wheel "$PLIST_DEST"
chmod 644 "$PLIST_DEST"

# ── Load daemon ────────────────────────────────────────────────────────────────

if launchctl list "$DAEMON_LABEL" &>/dev/null; then
    log "Unloading existing registration"
    launchctl unload "$PLIST_DEST" 2>/dev/null || true
fi

log "Loading LaunchDaemon"
launchctl load   "$PLIST_DEST"          || fail "launchctl load failed"
launchctl start  "$DAEMON_LABEL"        || fail "launchctl start failed"

# ── Verify & record status ─────────────────────────────────────────────────────

sleep 3

if launchctl list "$DAEMON_LABEL" &>/dev/null; then
    EXIT_CODE=$(launchctl list "$DAEMON_LABEL" | awk 'NR==2{print $1}')
    log "Daemon registered. Last exit code: ${EXIT_CODE:-none}"
    printf 'STATUS=SUCCESS\nDETAIL=Daemon registered. Last exit code: %s\nTIMESTAMP=%s\n' \
        "${EXIT_CODE:-none}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATUS_FILE"
    log "Install complete. Status → ${STATUS_FILE}"
    exit 0
else
    fail "Daemon not found in launchctl list after load"
fi

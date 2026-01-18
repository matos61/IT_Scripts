#!/usr/bin/env bash
set -euo pipefail

# macOS compliance snapshot
# Exit 0 = compliant, 2 = non-compliant, 1 = error

JSON_OUT="${1:-/var/tmp/macos_compliance.json}"
MIN_MAJOR="${2:-13}"   # e.g., 13 = Ventura

os_version="$(sw_vers -productVersion)"
os_major="$(echo "$os_version" | awk -F. '{print $1}')"

filevault_status="$(/usr/bin/fdesetup status 2>/dev/null || true)"
filevault_on="false"
if echo "$filevault_status" | grep -qi "FileVault is On"; then
  filevault_on="true"
fi

# Application firewall (socketfilterfw) global state
fw_global="$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null || true)"
firewall_on="false"
if echo "$fw_global" | grep -qi "enabled"; then
  firewall_on="true"
fi

compliant="true"
reasons=()

if [[ "$os_major" -lt "$MIN_MAJOR" ]]; then
  compliant="false"
  reasons+=("OS major version $os_major is below minimum $MIN_MAJOR")
fi

if [[ "$filevault_on" != "true" ]]; then
  compliant="false"
  reasons+=("FileVault is not enabled")
fi

if [[ "$firewall_on" != "true" ]]; then
  compliant="false"
  reasons+=("macOS Application Firewall is not enabled")
fi

# Build JSON without jq (portable)
reasons_json="[]"
if [[ "${#reasons[@]}" -gt 0 ]]; then
  reasons_json="$(printf '%s\n' "${reasons[@]}" | python3 -c 'import json,sys; print(json.dumps([l.rstrip("\n") for l in sys.stdin]))' 2>/dev/null || echo "[]")"
fi

cat > "$JSON_OUT" <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "os_version": "$os_version",
  "os_major": $os_major,
  "min_major": $MIN_MAJOR,
  "filevault_on": $filevault_on,
  "firewall_on": $firewall_on,
  "compliant": $compliant,
  "reasons": $reasons_json
}
EOF

echo "[INFO] Wrote: $JSON_OUT"

if [[ "$compliant" == "true" ]]; then
  exit 0
else
  exit 2
fi

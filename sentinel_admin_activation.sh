# @@@@@Defunct with mac update to not allow remote admin execution @@@@@

#!/bin/bash
set -euo pipefail

#############################################
# CONFIG
#############################################

# Replace with your SentinelOne Registration Token (Site/Group token).
# In Addigy, you can also use Variables to avoid hardcoding. :contentReference[oaicite:1]{index=1}
S1_TOKEN="TOKEN_HERE"

# Token filename required by the SentinelOne installer.
TOKEN_FILE_NAME="com.sentinelone.registration-token"

#############################################
# HELPERS
#############################################

log() { echo "[S1][$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

die() { log "ERROR: $*"; exit 1; }

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    die "Must run as root. Configure Addigy to run this as root."
  fi
}

find_pkg() {
  # Prefer a pkg in the current directory
  local pkgs=()
  while IFS= read -r -d '' f; do pkgs+=("$f"); done < <(find . -maxdepth 1 -type f -name "*.pkg" -print0)

  if [[ "${#pkgs[@]}" -eq 0 ]]; then
    die "No .pkg found in current directory: $(pwd)"
  fi

  # If multiple pkgs exist, pick the newest by mtime
  local newest
  newest="$(ls -t ./*.pkg | head -n 1)"
  echo "$newest"
}

#############################################
# MAIN
#############################################

require_root

# Basic token sanity
if [[ -z "${S1_TOKEN}" || "${S1_TOKEN}" == "TOKEN_HERE" ]]; then
  die "S1_TOKEN is not set. Replace TOKEN_HERE with your registration token."
fi

WORKDIR="$(pwd)"
PKG_PATH="$(find_pkg)"
TOKEN_PATH="${WORKDIR}/${TOKEN_FILE_NAME}"

log "Working directory: ${WORKDIR}"
log "Using pkg: ${PKG_PATH}"

# Create token file in the same directory as the pkg (required). :contentReference[oaicite:2]{index=2}
log "Creating token file: ${TOKEN_PATH}"
printf '%s' "${S1_TOKEN}" > "${TOKEN_PATH}"

# Tighten permissions/ownership
chown root:wheel "${TOKEN_PATH}" || true
chmod 600 "${TOKEN_PATH}" || true

# Install
log "Installing SentinelOne pkg..."
/usr/sbin/installer -pkg "${PKG_PATH}" -target / || die "installer failed"

# Remove token file after install
log "Removing token file..."
rm -f "${TOKEN_PATH}"

# Verification (best-effort)
if [[ -x "/usr/local/bin/sentinelctl" ]]; then
  log "sentinelctl detected. Status:"
  /usr/local/bin/sentinelctl status || true
else
  log "sentinelctl not found at /usr/local/bin/sentinelctl (agent may still be initializing)."
fi

log "Done."
exit 0

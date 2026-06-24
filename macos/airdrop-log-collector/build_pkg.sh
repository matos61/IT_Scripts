#!/bin/bash
# build_pkg.sh — turn the airdrop-monitor zip into a Jamf-deployable .pkg
#
# usage: ./build_pkg.sh <path-to-zip-or-extracted-folder> [version]
#   e.g. ./build_pkg.sh ~/Downloads/airdrop-monitor.zip
#
# Output: ~/Downloads/airdrop-monitor-<version>.pkg
# Note: install.sh is deliberately NOT packaged — it becomes a Jamf Script
#       object so it can receive Parameters 4/5 (SIEM URL + API key).

set -euo pipefail

IDENTIFIER="com.example.airdrop.monitor"

INPUT="${1:?usage: $0 <path-to-zip-or-folder> [version]}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- 1. Unpack (accepts the zip or an already-extracted folder) ---------
if [ -d "$INPUT" ]; then
    cp -R "$INPUT" "$WORK/src"
else
    unzip -q "$INPUT" -d "$WORK/src"
fi

# Locate the folder holding the collector (handles nested zip layouts)
FOUND="$(find "$WORK/src" -name 'airdrop_log_collector.py' -print -quit)"
[ -n "$FOUND" ] || { echo "ERROR: airdrop_log_collector.py not found in $INPUT" >&2; exit 1; }
SRC="$(dirname "$FOUND")"

for f in com.example.airdrop.monitor.plist uninstall.sh; do
    [ -f "$SRC/$f" ] || { echo "ERROR: $f not found next to the collector" >&2; exit 1; }
done

# --- 2. Version: 2nd arg, else read __version__ from the collector ------
VERSION="${2:-$(grep -m1 '__version__' "$SRC/airdrop_log_collector.py" | sed -E 's/[^0-9.]*([0-9][0-9.]*).*/\1/')}"
: "${VERSION:?could not detect version - pass it as the 2nd argument}"

# --- 3. Stage the payload (static files only, perms per DEPLOY.md) ------
ROOT="$WORK/root"
APP_DIR="$ROOT/Library/Application Support/airdrop-monitor"
mkdir -p "$APP_DIR" "$ROOT/Library/LaunchDaemons"

cp "$SRC/airdrop_log_collector.py"            "$APP_DIR/"
cp "$SRC/uninstall.sh"                        "$APP_DIR/"   # staged for the uninstall policy
cp "$SRC/com.example.airdrop.monitor.plist"    "$ROOT/Library/LaunchDaemons/"

chmod 755 "$APP_DIR/airdrop_log_collector.py" "$APP_DIR/uninstall.sh"
chmod 644 "$ROOT/Library/LaunchDaemons/com.example.airdrop.monitor.plist"

# --- 4. Build ------------------------------------------------------------
OUT="$HOME/Downloads/airdrop-monitor-${VERSION}.pkg"
pkgbuild --root "$ROOT" \
         --identifier "$IDENTIFIER" \
         --version "$VERSION" \
         --install-location / \
         --ownership recommended \
         "$OUT"

# Optional: sign it (uncomment and fill in your Developer ID Installer cert)
# productsign --sign "Developer ID Installer: Example Inc (TEAMID)" "$OUT" "${OUT%.pkg}-signed.pkg"

echo
echo "Built: $OUT"
echo "Payload contents:"
pkgutil --payload-files "$OUT"

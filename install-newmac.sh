#!/usr/bin/env bash
#
# install-newmac.sh — one-shot bootstrap for a NEW Mac.
#
# Run this AFTER copying the mac-migrate folder (script + .enc bundle) to the
# new machine. It locates the bundle, installs Homebrew + your tools, restores
# your configs/creds, then verifies everything works.
#
# Usage:
#   ./install-newmac.sh                 # auto-find bundle next to this script / Downloads / Desktop / USB
#   ./install-newmac.sh /path/to.enc    # explicit bundle path
#
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MIGRATE="$HERE/mac-migrate.sh"

c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_red=$'\033[31m'; c_dim=$'\033[2m'; c_bld=$'\033[1m'; c_off=$'\033[0m'
ok(){   printf "%s[ ok ]%s %s\n" "$c_grn" "$c_off" "$*"; }
warn(){ printf "%s[warn]%s %s\n" "$c_yel" "$c_off" "$*"; }
err(){  printf "%s[fail]%s %s\n" "$c_red" "$c_off" "$*"; }
step(){ printf "\n%s==> %s%s\n" "$c_bld" "$*" "$c_off"; }
ask(){  printf "%s%s%s " "$c_yel" "$*" "$c_off"; read -r REPLY; }

# ---------------------------------------------------------------------------
# 0. Sanity: must have the migrate script alongside.
# ---------------------------------------------------------------------------
[ -f "$MIGRATE" ] || { err "mac-migrate.sh not found next to this installer ($HERE). Copy the whole folder over."; exit 1; }
chmod +x "$MIGRATE" 2>/dev/null

# ---------------------------------------------------------------------------
# 1. Locate the encrypted bundle.
# ---------------------------------------------------------------------------
step "Locating bundle"
BUNDLE="${1:-}"
if [ -z "$BUNDLE" ]; then
  # Search common drop spots, newest first.
  for dir in "$HERE" "$HOME/Downloads" "$HOME/Desktop" /Volumes/*; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.tar.gz.enc "$dir"/*.enc; do
      [ -f "$f" ] && { BUNDLE="$f"; break 2; }
    done
  done
fi
if [ -z "$BUNDLE" ] || [ ! -f "$BUNDLE" ]; then
  err "No .enc bundle found. Drag it into this folder, or pass its path:"
  err "  ./install-newmac.sh /path/to/mac-migrate-bundle.tar.gz.enc"
  exit 1
fi
ok "Bundle: $BUNDLE ($(du -sh "$BUNDLE" | cut -f1))"
ask "Use this bundle? [Y/n]"; case "$REPLY" in [Nn]*) err "Aborted — pass the path explicitly."; exit 1;; esac

# ---------------------------------------------------------------------------
# 2. Homebrew (needed to reinstall the tools the configs belong to).
# ---------------------------------------------------------------------------
step "Homebrew"
if command -v brew >/dev/null 2>&1; then
  ok "brew present: $(brew --version | head -1)"
else
  warn "Homebrew not installed."
  ask "Install Homebrew now? (needs network + admin password) [Y/n]"
  case "$REPLY" in
    [Nn]*) warn "Skipping. Tools won't be reinstalled — configs will still restore.";;
    *) /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
         && eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)";;
  esac
fi

# ---------------------------------------------------------------------------
# 3. Reinstall tools from Brewfile (if we have one + brew).
#    Brewfile may be inside the bundle; restore writes it out. So we do a
#    pre-pass if a loose Brewfile sits next to us, then a post-pass after restore.
# ---------------------------------------------------------------------------
brew_install(){
  local bf="$1"
  [ -f "$bf" ] || return 0
  command -v brew >/dev/null 2>&1 || { warn "no brew; skipping $bf"; return 0; }
  step "Installing tools from $bf ($(grep -c . "$bf") entries)"
  brew bundle --file="$bf" || warn "Some brew entries failed — continuing."
}
brew_install "$HERE/Brewfile"

# ---------------------------------------------------------------------------
# 4. Restore configs/creds (mac-migrate.sh handles decrypt + path-patch + backup).
# ---------------------------------------------------------------------------
step "Restoring configs & credentials"
warn "You'll be prompted for the bundle passphrase (set on the old mac)."
"$MIGRATE" restore "$BUNDLE" || { err "Restore failed (wrong passphrase?)."; exit 1; }

# Brewfile may have been written by restore into the migrate workdir — second pass.
RESTORED_BF="${MAC_MIGRATE_DIR:-$HOME/mac-migrate}/Brewfile"
[ -f "$RESTORED_BF" ] && [ "$RESTORED_BF" != "$HERE/Brewfile" ] && brew_install "$RESTORED_BF"

# ---------------------------------------------------------------------------
# 5. Verify — run the test suite against the freshly restored state.
# ---------------------------------------------------------------------------
step "Verifying tools (test suite)"
# Re-source shell rc so PATH/aliases from restored .zshrc/.zprofile take effect.
for rc in "$HOME/.zprofile" "$HOME/.zshrc"; do [ -f "$rc" ] && . "$rc" 2>/dev/null; done
"$MIGRATE" test
RESULT=$?

# ---------------------------------------------------------------------------
# 6. Summary + manual follow-ups.
# ---------------------------------------------------------------------------
step "Next steps"
cat <<EOF
  • Open a NEW terminal window so all shell changes load cleanly.
  • Anything that failed the test suite usually just needs a re-auth, e.g.:
      gcloud auth login        gh auth login        gam oauth create
  • Re-install crontab if you had one:   crontab ~/mac-migrate/crontab.bak
  • Cisco VPN / GUI apps: install the app, then prefs in ~/.vpn apply.
  • Overwritten files were backed up to ~/.mac-migrate-backup-* (if any).
EOF

if [ "$RESULT" -eq 0 ]; then ok "All present tools verified. Migration complete."; else
  warn "Some tools failed verification — see above. Re-auth or re-run: $MIGRATE test"; fi
exit "$RESULT"

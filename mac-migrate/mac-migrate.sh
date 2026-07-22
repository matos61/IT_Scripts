#!/usr/bin/env bash
#
# mac-migrate.sh — portable dev-environment migration toolkit
#
# Broadly scans a Mac for transferable tool configs/creds, bundles them into an
# encrypted archive, restores them on a new machine, and runs a test suite to
# verify each tool actually works after transfer.
#
# Designed to hand to any engineer — the catalog + heuristic scan adapt to
# whatever tools they have installed.
#
# Usage:
#   ./mac-migrate.sh scan                 # discover what can transfer -> manifest
#   ./mac-migrate.sh bundle [out.tar.enc] # encrypt manifest contents into archive
#   ./mac-migrate.sh restore <archive>    # decrypt + place files on new machine
#   ./mac-migrate.sh test                 # run test suite (verify tools work)
#   ./mac-migrate.sh doctor               # scan + test, no bundling (quick check)
#
set -uo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
WORKDIR="${MAC_MIGRATE_DIR:-$HOME/mac-migrate}"
MANIFEST="$WORKDIR/manifest.txt"      # newline list of existing paths to bundle
REPORT="$WORKDIR/scan-report.txt"
BREWFILE="$WORKDIR/Brewfile"
STAGE="$WORKDIR/.stage"               # temp staging for bundle/restore
CRONFILE="$WORKDIR/crontab.bak"

mkdir -p "$WORKDIR"

c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_red=$'\033[31m'; c_dim=$'\033[2m'; c_off=$'\033[0m'
ok(){   printf "%s[ ok ]%s %s\n"   "$c_grn" "$c_off" "$*"; }
warn(){ printf "%s[warn]%s %s\n"   "$c_yel" "$c_off" "$*"; }
err(){  printf "%s[fail]%s %s\n"   "$c_red" "$c_off" "$*"; }
info(){ printf "%s%s%s\n"          "$c_dim" "$*" "$c_off"; }
hdr(){  printf "\n=== %s ===\n" "$*"; }

# ---------------------------------------------------------------------------
# CATALOG — known tools: config paths + how to test them.
# One row per tool, fields pipe-delimited (stock macOS bash 3.2 has no
# associative arrays, so we keep a plain list and parse each row):
#   name | space-separated paths (globs ok, rel to $HOME or absolute) | test cmd | secret(0/1)
# The test cmd must exit 0 only if the transferred state actually works.
# Add a row and the tool is covered everywhere (scan / bundle / test).
# ---------------------------------------------------------------------------
# Test commands must not contain '|', '(' or ')'. For anything more complex
# than a single command, define a _t_<name> function below and name it here.
CATALOG="
git|.gitconfig .gitignore_global .config/git|git config --get user.email|0
ssh|.ssh|_t_ssh|1
gnupg|.gnupg|gpg --list-secret-keys|1
gam|.gam bin/gam7 bin/gamadv-xtd3|_t_gam|1
gcloud|.config/gcloud .boto|_t_gcloud|1
gh|.config/gh|gh auth status|1
claude|.claude.json .claude/settings.json .claude/settings.local.json .claude/CLAUDE.md .claude/commands .claude/agents .claude/skills .claude/hooks .claude/keybindings.json .claude/*.py .claude/*.sh .claude/plugins/known_marketplaces.json .claude/plugins/installed_plugins.json|_t_claude|1
aws|.aws|aws sts get-caller-identity|1
kube|.kube/config|kubectl config get-contexts|1
docker|.docker/config.json|docker info|1
rclone|.config/rclone|rclone listremotes|1
npm|.npmrc|npm whoami|1
pip|.config/pip .pip|true|0
terraform|.terraformrc .terraform.d|terraform version|1
vpn|.vpn .anyconnect|true|0
shell|.zshrc .zprofile .bashrc .bash_profile .profile .aliases .functions .exports|true|0
editors|.vimrc .config/nvim .tmux.conf .editorconfig .ideavimrc|true|0
misc|.netrc .curlrc .wgetrc .ripgreprc .digrc .inputrc|true|1
"

# Test helpers for tools whose check needs ||, (), or non-PATH binaries.
_t_ssh(){ ls "$HOME"/.ssh/id_* >/dev/null 2>&1 || test -s "$HOME/.ssh/config"; }
_t_gam(){
  for b in "$HOME/bin/gam7/gam" "$HOME/bin/gamadv-xtd3/gam" "$(command -v gam 2>/dev/null)"; do
    [ -x "$b" ] && { "$b" version >/dev/null 2>&1 && return 0; }
  done
  return 1
}
_t_gcloud(){ gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; }
_t_claude(){
  command -v claude >/dev/null 2>&1 || return 1
  for f in "$HOME/.claude.json" "$HOME/.claude/settings.json" "$HOME/.claude/settings.local.json"; do
    [ -f "$f" ] && { python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" 2>/dev/null || return 1; }
  done
  return 0
}

# Iterate catalog rows: calls `_row name paths test secret` for each.
catalog_each(){
  printf '%s\n' "$CATALOG" | while IFS='|' read -r name paths test secret; do
    [ -n "$name" ] || continue
    "$1" "$name" "$paths" "$test" "$secret"
  done
}

# Echo every existing path for a tool's path-spec (resolves globs + $HOME).
resolve_paths(){
  for p in $1; do
    case "$p" in /*) : ;; *) p="$HOME/$p";; esac
    for m in $p; do [ -e "$m" ] && printf '%s\n' "$m"; done
  done
}

# ---------------------------------------------------------------------------
# SCAN — discover what exists, write manifest + report.
# ---------------------------------------------------------------------------
scan(){
  : > "$MANIFEST"; : > "$REPORT"
  hdr "SCAN" | tee -a "$REPORT"

  local found_secret=0
  _scan_row(){
    local name="$1" paths="$2" secret="$4" hit
    hit="$(resolve_paths "$paths")"
    [ -n "$hit" ] || return 0
    local sz; sz=$(echo "$hit" | tr '\n' '\0' | xargs -0 du -shc 2>/dev/null | tail -1 | cut -f1)
    local tag=""; [ "$secret" = 1 ] && { tag=" (secret)"; found_secret=1; }
    printf "%-10s %-6s %s%s\n" "$name" "$sz" "$(echo "$hit" | tr '\n' ' ')" "$tag" | tee -a "$REPORT"
    printf '%s\n' "$hit" >> "$MANIFEST"
  }
  # Subshell in pipeline can't export found_secret; detect secrets via manifest after.
  catalog_each _scan_row
  grep -qE '\.ssh|\.gnupg|gcloud|\.aws|gam|\.config/gh|rclone|\.npmrc|\.netrc' "$MANIFEST" && found_secret=1

  # Heuristic sweep: catch portable dotfiles not in catalog
  hdr "EXTRA DOTFILES (not in catalog, review before bundling)" | tee -a "$REPORT"
  local known=" $(tr '\n' ' ' < "$MANIFEST") "
  for f in "$HOME"/.[!.]*; do
    [ -f "$f" ] || continue
    case "$f" in *_history|*.bak|*.log|*sessions*) continue;; esac
    [[ "$known" == *" $f "* ]] && continue
    info "  $f" | tee -a "$REPORT"
  done

  # Package managers
  hdr "PACKAGES" | tee -a "$REPORT"
  if command -v brew >/dev/null 2>&1; then
    brew bundle dump --file="$BREWFILE" --force >/dev/null 2>&1 \
      && ok "Brewfile written ($(grep -c . "$BREWFILE") entries) -> $BREWFILE" | tee -a "$REPORT"
  else
    warn "brew not found — skipping Brewfile" | tee -a "$REPORT"
  fi
  for pm in "npm:npm -g ls --depth=0" "pip:pip3 list --user --format=freeze" "gem:gem list --local"; do
    cmd="${pm#*:}"; name="${pm%%:*}"
    command -v "${cmd%% *}" >/dev/null 2>&1 && info "  $name present (export manually if needed: $cmd)" | tee -a "$REPORT"
  done

  # Crontab — NOT portable automatically
  if crontab -l >/dev/null 2>&1; then
    crontab -l > "$CRONFILE" 2>/dev/null
    warn "crontab saved -> $CRONFILE (re-install on new mac: crontab $CRONFILE)" | tee -a "$REPORT"
    echo "$CRONFILE" >> "$MANIFEST"
  fi

  hdr "SUMMARY" | tee -a "$REPORT"
  ok "$(grep -c . "$MANIFEST") paths queued -> $MANIFEST"
  [ "$found_secret" = 1 ] && warn "Manifest contains credentials. Bundle is encrypted; keep passphrase safe."
  info "Review $MANIFEST, then: $0 bundle"
}

# ---------------------------------------------------------------------------
# BUNDLE — stage manifest paths, write metadata, tar + encrypt.
# ---------------------------------------------------------------------------
bundle(){
  [ -s "$MANIFEST" ] || { err "No manifest. Run: $0 scan"; exit 1; }
  local out="${1:-$WORKDIR/mac-migrate-bundle.tar.gz.enc}"
  rm -rf "$STAGE"; mkdir -p "$STAGE/home"

  # Copy each manifest path preserving structure relative to $HOME.
  local copied=0
  while IFS= read -r src; do
    [ -e "$src" ] || continue
    case "$src" in
      "$HOME"/*) rel="${src#$HOME/}"; dest="$STAGE/home/$rel";;
      *)         rel="abs${src}";    dest="$STAGE/$rel";;   # absolute paths preserved
    esac
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest" 2>/dev/null && copied=$((copied+1))
  done < "$MANIFEST"

  # Patch the .zshrc bug class: split run-together exports onto own lines.
  # (Generic safety pass — only touches lines with a mid-line `export`.)
  for rc in "$STAGE/home/.zshrc" "$STAGE/home/.zprofile" "$STAGE/home/.bashrc"; do
    [ -f "$rc" ] && sed -i '' -E 's/("[^"]*")(export )/\1\
\2/g' "$rc" 2>/dev/null
  done

  cp -f "$BREWFILE" "$STAGE/Brewfile" 2>/dev/null || true

  # Metadata so restore can patch absolute /Users/<name> paths.
  cat > "$STAGE/MIGRATE_META" <<EOF
SRC_USER=$(id -un)
SRC_HOME=$HOME
SRC_HOST=$(hostname)
CREATED=$(date +%Y-%m-%dT%H:%M:%S)
EOF

  info "Staged $copied paths. Encrypting -> $out"
  # Passphrase: interactive prompt by default; MAC_MIGRATE_PASS env for scripted runs.
  local passarg=""; [ -n "${MAC_MIGRATE_PASS:-}" ] && passarg="-pass env:MAC_MIGRATE_PASS"
  ( cd "$STAGE" && tar czf - . ) | openssl enc -aes-256-cbc -salt -pbkdf2 $passarg -out "$out"
  local rc=$?
  rm -rf "$STAGE"
  if [ $rc -eq 0 ]; then
    ok "Bundle: $out ($(du -sh "$out" | cut -f1))"
    info "Transfer it + this script to new mac, then: $0 restore $out"
  else
    err "Encryption failed."; exit 1
  fi
}

# ---------------------------------------------------------------------------
# RESTORE — decrypt, patch username paths, place files (backs up existing).
# ---------------------------------------------------------------------------
restore(){
  local arc="${1:-}"
  [ -f "$arc" ] || { err "Usage: $0 restore <archive>"; exit 1; }
  rm -rf "$STAGE"; mkdir -p "$STAGE"
  info "Decrypting $arc"
  local passarg=""; [ -n "${MAC_MIGRATE_PASS:-}" ] && passarg="-pass env:MAC_MIGRATE_PASS"
  openssl enc -d -aes-256-cbc -pbkdf2 $passarg -in "$arc" | tar xzf - -C "$STAGE" \
    || { err "Decrypt/extract failed (wrong passphrase?)"; rm -rf "$STAGE"; exit 1; }

  # shellcheck disable=SC1091
  [ -f "$STAGE/MIGRATE_META" ] && . "$STAGE/MIGRATE_META"
  local newhome="$HOME" newuser; newuser="$(id -un)"
  info "Restoring as $newuser (source was ${SRC_USER:-?} on ${SRC_HOST:-?})"

  # Patch absolute source-home references inside text configs.
  if [ -n "${SRC_HOME:-}" ] && [ "$SRC_HOME" != "$newhome" ]; then
    info "Rewriting paths: $SRC_HOME -> $newhome"
    grep -rIl "$SRC_HOME" "$STAGE/home" 2>/dev/null | while IFS= read -r f; do
      sed -i '' "s|$SRC_HOME|$newhome|g" "$f" 2>/dev/null
    done
  fi

  # Place files; back up anything we'd overwrite.
  local bak="$HOME/.mac-migrate-backup-$(date +%Y%m%d%H%M%S)"
  ( cd "$STAGE/home" 2>/dev/null && find . -type f ) | while IFS= read -r rel; do
    rel="${rel#./}"; local d="$HOME/$rel"
    if [ -e "$d" ]; then mkdir -p "$bak/$(dirname "$rel")"; cp -a "$d" "$bak/$rel" 2>/dev/null; fi
    mkdir -p "$(dirname "$d")"; cp -a "$STAGE/home/$rel" "$d"
  done
  chmod 700 "$HOME/.ssh" "$HOME/.gnupg" 2>/dev/null
  chmod 600 "$HOME"/.ssh/* 2>/dev/null

  [ -d "$bak" ] && warn "Overwritten files backed up to $bak"
  [ -f "$STAGE/Brewfile" ] && cp -f "$STAGE/Brewfile" "$BREWFILE" \
    && info "Brewfile -> $BREWFILE  (install: brew bundle --file=$BREWFILE)"
  rm -rf "$STAGE"
  ok "Restore done. Open new shell, then: $0 test"
}

# ---------------------------------------------------------------------------
# TEST — run each catalog tool's verification command.
# ---------------------------------------------------------------------------
run_tests(){
  hdr "TEST SUITE"
  local results; results="$WORKDIR/.test-results"; : > "$results"
  _test_row(){
    local name="$1" paths="$2" test="$3"
    # Only test tools whose config is actually present.
    if [ -z "$(resolve_paths "$paths")" ]; then
      printf "%-10s —skip (not present)\n" "$name"; echo skip >> "$results"; return 0
    fi
    local out; out=$(eval "$test" 2>&1); local rc=$?
    local first; first=$(printf '%s' "$out" | head -1 | cut -c1-50)
    if [ $rc -eq 0 ]; then ok  "$(printf '%-10s %s' "$name" "$first")"; echo pass >> "$results"
    else                   err "$(printf '%-10s %s' "$name" "$first")"; echo fail >> "$results"; fi
  }
  catalog_each _test_row
  local pass fail skip
  pass=$(grep -c pass "$results"); fail=$(grep -c fail "$results"); skip=$(grep -c skip "$results")
  rm -f "$results"
  hdr "RESULT"
  printf "%spass=%d%s  %sfail=%d%s  %sskip=%d%s\n" "$c_grn" "$pass" "$c_off" "$c_red" "$fail" "$c_off" "$c_dim" "$skip" "$c_off"
  [ "${fail:-0}" -eq 0 ]
}

# ---------------------------------------------------------------------------
main(){
  case "${1:-}" in
    scan)    scan;;
    bundle)  shift; bundle "$@";;
    restore) shift; restore "$@";;
    test)    run_tests;;
    doctor)  scan; run_tests;;
    *) cat <<EOF
mac-migrate — portable dev-env migration

  $0 scan                 discover transferable configs -> manifest + report
  $0 bundle [out.enc]     encrypt manifest contents into one archive
  $0 restore <archive>    decrypt + place files on new mac (patches username)
  $0 test                 verify each present tool works
  $0 doctor               scan + test (no bundling)

Files in: $WORKDIR
EOF
      ;;
  esac
}
main "$@"

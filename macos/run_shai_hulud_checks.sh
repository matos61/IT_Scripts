#!/usr/bin/env bash
set -euo pipefail

# Will install to machine and avoid chekcing its own directory to remove false positives

# TO RUN THE SCRIPT RUN THIS WITH REPLACING THE PROJECT WITH YOUR DIRECTORY FOR MORE DIRECT SCANS
# ./run_shai_hulud_checks.sh --report /tmp/shai-hulud-report.log ~/src/projectA ~/src/projectB


# Shai-Hulud detector runner
# - No repo clone into your current working directory
# - Downloads to a temp directory, runs checks, then cleans up
#
# Exit codes (per detector):
#   0 = clean
#   1 = high-risk findings
#   2 = medium-risk findings
# Other non-zero can indicate runtime errors.

DETECTOR_URL="https://raw.githubusercontent.com/Cobenian/shai-hulud-detect/main/shai-hulud-detector.sh"

usage() {
  cat <<'EOF'
Usage:
  ./run_shai_hulud_checks.sh [--paranoid] [--report /path/to/report.log] [path1 path2 ...]

Examples:
  # Scan current directory
  ./run_shai_hulud_checks.sh

  # Scan multiple directories
  ./run_shai_hulud_checks.sh ~/src/projectA ~/src/projectB

  # Paranoid scan + save report
  ./run_shai_hulud_checks.sh --paranoid --report ./shai-hulud-report.log ~/src/projectA
EOF
}

PARANOID="false"
REPORT_PATH=""

ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --paranoid)
      PARANOID="true"
      shift
      ;;
    --report)
      [[ $# -lt 2 ]] && { echo "Missing value for --report"; usage; exit 64; }
      REPORT_PATH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

# Default to current directory if no paths provided
if [[ "${#ARGS[@]}" -eq 0 ]]; then
  ARGS+=("$(pwd)")
fi

# Basic dependency checks
command -v curl >/dev/null 2>&1 || { echo "curl is required"; exit 127; }
command -v bash >/dev/null 2>&1 || { echo "bash is required"; exit 127; }

TMPDIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'shaihulud')"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

DETECTOR_PATH="${TMPDIR}/shai-hulud-detector.sh"

echo "[INFO] Temp workspace: $TMPDIR"
echo "[INFO] Downloading detector..."
curl -fsSL "$DETECTOR_URL" -o "$DETECTOR_PATH"
chmod +x "$DETECTOR_PATH"

RUN_OPTS=()
if [[ "$PARANOID" == "true" ]]; then
  RUN_OPTS+=("--paranoid")
fi
if [[ -n "$REPORT_PATH" ]]; then
  # Ensure report directory exists
  mkdir -p "$(dirname "$REPORT_PATH")"
  RUN_OPTS+=("--save-log" "$REPORT_PATH")
fi

echo "[INFO] Running detector against:"
printf '  - %s\n' "${ARGS[@]}"

set +e
"$DETECTOR_PATH" "${RUN_OPTS[@]}" "${ARGS[@]}"
RC=$?
set -e

case "$RC" in
  0) echo "[RESULT] Clean (exit $RC)";;
  1) echo "[RESULT] High-risk findings (exit $RC)";;
  2) echo "[RESULT] Medium-risk findings (exit $RC)";;
  *) echo "[RESULT] Detector/runtime error (exit $RC)";;
esac

if [[ -n "$REPORT_PATH" ]]; then
  echo "[INFO] Report saved to: $REPORT_PATH"
fi

exit "$RC"

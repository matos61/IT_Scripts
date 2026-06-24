#!/bin/bash
# set -e
#
# This script performs managed group assignment after TeamViewer has been installed by an MDM or by
# the macOS installer. It needs to be run as root (or with sudo).
#
# Add your assignment ID below, e.g.
#   ASSIGNMENT_ID="0001SWYgeW91IGNhbiByZWFkIHRoaXMgdGhlbiB5b3Uga25vdyBpdCdzIGp1c3QgYW4gZXhhbXBsZSA6KQo="
#
# This script is an example for documentation and testing purposes. It is provided "as is" without
# any warranty or support.

ASSIGNMENT_ID=""
DEVICE_ALIAS="" # optional

# There is normally no reason to change these:
TIMEOUT_SEC=60
WAIT_FOR_NETWORK_SEC=15


# ------ Do not edit below this line. ------

if [ -z "${ASSIGNMENT_ID}" ]; then
	echo "Missing assignment ID." >&2
	exit 1
fi

if [ "${EUID}" -ne 0 ]; then
  echo "This script needs to be run as root (or with sudo)." >&2
  exit 1
fi

# This script needs to run after installation, so we expect the app to exist.
FULL="/Applications/TeamViewer.app"
HOST="/Applications/TeamViewerHost.app"

if [ -e "${FULL}" ]; then
	TV_APP="${FULL}"
elif [ -e "${HOST}" ]; then
	TV_APP="${HOST}"
else
	echo "No TeamViewer installation found." >&2
	exit 1
fi

SERVICE="${TV_APP}/Contents/MacOS/TeamViewer_Service"
ASSIGNMENT_TOOL="${TV_APP}/Contents/Helpers/TeamViewer_Assignment"
SECONDS=0

is_service_running() {
	pgrep -f "${SERVICE}" > /dev/null 2>&1
}

echo "Waiting for TeamViewer service..."
while ! is_service_running; do
	if [ "${SECONDS}" -ge "${TIMEOUT_SEC}" ]; then
		echo "Service did not appear within ${TIMEOUT_SEC} seconds." >&2
		if [ "${TV_APP}" = "${FULL}" ]; then
			echo "Please make sure TeamViewer is configured to start with macOS." >&2
			# This should automatically be the case with packages intended for mass deployment, but we
			# cannot rule out that this script is used with a different installation or that Start with
			# macOS has been turned off after installation.
		fi
		exit 1
	fi
	sleep 1
done
echo "TeamViewer service is running, waiting ${WAIT_FOR_NETWORK_SEC} seconds to ensure network connectivity..."
sleep "${WAIT_FOR_NETWORK_SEC}"

"${ASSIGNMENT_TOOL}" -assignment_id "${ASSIGNMENT_ID}" ${DEVICE_ALIAS:+"-device_alias"} ${DEVICE_ALIAS:+"$DEVICE_ALIAS"}

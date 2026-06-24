#!/bin/bash
# set -e
#
# This script performs a LEGACY (groups / MDv1) assignment after TeamViewer has been installed by
# an MDM or using the macOS installer on the command line. It needs to run as root (or with sudo).
#
# Add your API_TOKEN and the GROUP to which to add the device below, e.g.
#   API_TOKEN="12345678-SGVsbG8sIHdvcmxkCg"
#   GROUP="IT"
#
# This script is an example for documentation and testing purposes. It is provided "as is" without
# any warranty or support.

API_TOKEN=""
GROUP=""
ALIAS="" # optional

GRANT_EASY_ACCESS=1 # 1 = on, 0 = off

# There is normally no reason to change these:
TIMEOUT_SEC=60
WAIT_FOR_NETWORK_SEC=15


# ------ Do not edit below this line. ------

if [ -z "${API_TOKEN}" ]; then
	echo "Missing API token." >&2
	exit 1
fi

if [ -z "${GROUP}" ]; then
	echo "Missing group." >&2
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

if [ "${GRANT_EASY_ACCESS}" != "1" ]; then
	unset GRANT_EASY_ACCESS
fi

${ASSIGNMENT_TOOL} -api-token ${API_TOKEN} -group "${GROUP}" ${ALIAS:+"-alias"} ${ALIAS:+"$ALIAS"} ${GRANT_EASY_ACCESS:+"-grant-easy-access"}

ASSIGNMENT_RESULT="$?"
if [ "${ASSIGNMENT_RESULT}" = "0" ]; then
	echo "Assignment successful."
	exit 0
else
	echo "Assignment exited with code ${ASSIGNMENT_RESULT}." >&2
	exit "${ASSIGNMENT_RESULT}"
fi

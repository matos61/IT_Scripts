#!/bin/bash
# set -e
#
# This script sets Conditional Access routers prior to installing TeamViewer. It needs to be run
# as root (or with sudo).
#
# Add your CA routers below (separated by spaces), e.g.
# CONDITIONAL_ACCESS_ROUTERS="example1.carouter.teamviewer.com example2.carouter.teamviewer.com"
#
# This script is an example for documentation and testing purposes. It is provided "as is" without
# any warranty or support.

CONDITIONAL_ACCESS_ROUTERS=""


# ------ Do not edit below this line. ------

if [ -z "${CONDITIONAL_ACCESS_ROUTERS}" ]; then
	echo "Missing conditional access routers." >&2
	exit 1
fi

if [ "${EUID}" -ne 0 ]; then
  echo "This script needs to be run as root (or with sudo)." >&2
  exit 1
fi

is_service_running() {
	pgrep -f "/Applications/TeamViewer.*\.app/Contents/MacOS/TeamViewer_Service" > /dev/null 2>&1
}

if is_service_running; then
  echo "TeamViewer is running. Restart TeamViewer for the new settings to take effect."
fi

defaults write "/Library/Preferences/com.teamviewer.teamviewer.preferences.plist" ConditionalAccessServers -array ${CONDITIONAL_ACCESS_ROUTERS}

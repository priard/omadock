#!/usr/bin/env bash
# Live: every IPC function round-trips and leaves the dock mapped with a
# clean log. Backs up omadock.json and restores it on exit. No input.
#
# *** INTRUSIVE - this one drives the dock on the OWNER'S DESKTOP. ***
# It opens the full-screen settings overlay on the running dock (a click or a
# key press during the run fails it), it writes the running dock's config file
# in place, and it exercises the code the running dock LOADED - not this tree,
# because the launcher runs Quickshell with QS_DISABLE_FILE_WATCHER=1. It is
# kept for the wiring only a real dock can show: the settings panel's open and
# page state, setLayout/setAlignment, and itemGeometry of the live items.
#
# Anything else belongs in a suite built on tests/live/probe.sh, which runs the
# plugin's own DockHost.qml in a second Quickshell instance against a copy of
# the config and never touches the desktop: tests/live/probe.sh is the model.
set -u
cd "$(dirname "$0")/../.."
. tests/live/common.sh
wait_ready || exit 1
CFG=$HOME/.config/omarchy/omadock.json
bak=$(mktemp); cp "$CFG" "$bak"
restore() { omarchy-shell omadock closeSettings >/dev/null 2>&1; cp "$bak" "$CFG"; rm -f "$bak"; }
trap restore EXIT
since=$(date '+%Y-%m-%d %H:%M:%S')
ipc() { omarchy-shell omadock "$@"; }
st() { ipc state | python3 -c "import json,sys; print(json.load(sys.stdin)[sys.argv[1]])" "$1"; }
# The settings panel is a full-screen overlay that takes keyboard focus and
# closes on any click or Escape, so input during the run fails the test.
fail() { echo "IPC ROUND-TRIP FAILED: $* (a click or key press during the run closes settings)" >&2; exit 1; }

ipc openSettings; sleep 1
[ "$(st settingsOpen)" = True ] || fail "openSettings"
for page in appearance placement behavior effects size folders groups about; do
  ipc openSettingsPage "$page"; sleep 0.4
  [ "$(st settingsPage)" = "$page" ] || fail "openSettingsPage $page"
done
ipc closeSettings; sleep 0.5
[ "$(st settingsOpen)" = False ] || fail "closeSettings"

v=$(st visible)
ipc toggleVisibility; sleep 0.5; ipc toggleVisibility; sleep 0.5
[ "$(st visible)" = "$v" ] || fail "toggleVisibility twice"
ipc reveal; sleep 0.5

align=$(python3 -c "import json; print(json.load(open('$CFG')).get('alignment', 'center'))")
ipc setAlignment "$align"; sleep 0.5

layout=$(python3 -c "import json; print(json.load(open('$CFG')).get('layout', 'dock'))")
ipc setLayout panel; sleep 0.5
[ "$(st layout)" = panel ] || fail "setLayout panel"
ipc setAlignment spread; sleep 0.5
[ "$(st align)" = spread ] || [ "$(st align)" = left ] || fail "setAlignment spread in panel"
ipc setLayout bogus; sleep 0.5
[ "$(st layout)" = dock ] || fail "setLayout bogus -> dock"
ipc setLayout "$layout"; ipc setAlignment "$align"; sleep 0.5

ipc itemGeometry | python3 -c "import json,sys; assert len(json.load(sys.stdin)) > 0" || fail "itemGeometry empty"
bash tests/smoke-test.sh >/dev/null || fail "smoke test"
if journalctl --user --since "$since" | grep -iE "omadock/.*(error|TypeError|ReferenceError|is not a)"; then
  fail "errors in the log"
fi
echo "IPC ROUND-TRIP PASSED"

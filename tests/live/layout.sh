#!/usr/bin/env bash
# Live: the panel layout spans the bottom edge and moves its icons with the
# alignment; Both sides sends folders and drives to the right edge; going
# back to the dock restores it exactly. Backs up omadock.json and restores
# it on exit. No input.
#
# *** INTRUSIVE - this one drives the dock on the OWNER'S DESKTOP. ***
# It rewrites layout/alignment/splitSections in the live omadock.json (backing
# it up and restoring it on exit) and it measures the code the running dock
# LOADED, not this tree - the launcher sets QS_DISABLE_FILE_WATCHER=1. It
# needs a dock that is really on screen, which is why it is not on
# tests/live/probe.sh; everything that does not can run there instead (see
# tests/live/presets.sh).
#
# The vertical difference between the two layouts is the shell's outer gap
# (Style.gapsOut, Hyprland's gaps_out / 2), which the dock's `state` reports:
# with gaps_out 0 the floating dock is already flush, so "lower" is asserted
# only where there is a gap to remove.
set -u
cd "$(dirname "$0")/../.."
. tests/live/common.sh
wait_ready || exit 1
CFG=$HOME/.config/omarchy/omadock.json
bak=$(mktemp); cp "$CFG" "$bak"
restore() { cp "$bak" "$CFG"; rm -f "$bak"; }
trap restore EXIT
ipc() { omarchy-shell omadock "$@"; }
fail() { echo "LAYOUT FAILED: $*" >&2; exit 1; }

# Writes layout, alignment and split into the config and waits for the dock.
set_cfg() {
  python3 - "$CFG" "$1" "$2" "$3" <<'EOF'
import json, sys
p = sys.argv[1]
c = json.load(open(p))
c["layout"], c["alignment"], c["splitSections"] = sys.argv[2], sys.argv[3], sys.argv[4] == "true"
c["autohide"] = False
json.dump(c, open(p, "w"), indent=2)
EOF
  sleep 1.5
}

# Prints "first_x last_right bottom_gap right_group_x window_w" for the
# items in window coordinates (the layer spans the monitor's width). The
# Omarchy button is not among the items: the first one sits a slot in.
measure() {
  local wh ww
  read -r ww wh < <(hyprctl -j layers | python3 -c "
import json, sys
for m in json.load(sys.stdin).values():
  for lv in m['levels'].values():
    for l in lv:
      if l['namespace'] == 'omadock': print(l['w'], l['h']); raise SystemExit")
  ipc itemGeometry | python3 -c "
import json, sys
items = [i for i in json.load(sys.stdin) if i['w'] > 0]
ww, wh = int(sys.argv[1]), int(sys.argv[2])
right = [i for i in items if i['kind'] in ('folder', 'drive')]
first = min(i['x'] for i in items)
last = max(i['x'] + i['w'] for i in items)
bottom = wh - max(i['y'] + i['h'] for i in items)
rx = min(i['x'] for i in right) if right else -1
print(first, last, bottom, rx, ww)" "$ww" "$wh"
}

set_cfg dock center false
dock_before=$(ipc itemGeometry)
read -r _ _ dock_bottom _ _ < <(measure)
# The panel's whole point vertically is the outer gap it removes (Style.gapsOut,
# Hyprland's gaps_out / 2). A desktop that runs edge to edge has none: the dock
# already sits flush, so the panel can only be as low, never lower.
gap=$(ipc state | python3 -c "import json,sys; print(json.load(sys.stdin).get('gapsOut', 0))")
row_gap=$(ipc state | python3 -c "import json,sys; print(json.load(sys.stdin).get('itemGap', 0))")

set_cfg panel left false
read -r first last bottom rx ww < <(measure)
if [ "$gap" -gt 0 ]; then
  [ "$bottom" -lt "$dock_bottom" ] || fail "panel not lower than the dock ($bottom >= $dock_bottom)"
else
  [ "$bottom" -le "$dock_bottom" ] || fail "panel higher than the dock ($bottom > $dock_bottom)"
fi
[ "$first" -le 60 ] || fail "panel left: first icon at $first"
left_first=$first

set_cfg panel right false
read -r first last bottom rx ww < <(measure)
[ $((ww - last)) -le 12 ] || fail "panel right: last icon ends $((ww - last)) px from the edge"
right_inset=$((ww - last))

set_cfg panel center false
read -r first last bottom rx ww < <(measure)
d=$(( (first - left_first) - (ww - last) )); d=${d#-}
[ "$d" -le 12 ] || fail "panel center: off by $d"

set_cfg panel spread false
read -r first last bottom rx ww < <(measure)
if [ "$rx" -ge 0 ]; then
  [ "$first" -le 60 ] || fail "panel spread: first icon at $first"
  # Both sides rests the right group where the right alignment puts it
  # (DockLayout.spreadGap floors the gap to the pixel grid: 1 px).
  tol=$((right_inset + 1))
  [ $((ww - last)) -le "$tol" ] || fail "panel spread: last icon ends $((ww - last)) px from the edge (allowed $tol)"
  [ "$rx" -gt $((ww / 2)) ] || fail "panel spread: folders start at $rx"
fi

set_cfg dock spread true
read -r first last bottom rx ww < <(measure)
if [ "$rx" -ge 0 ]; then
  [ $((ww - last)) -le 60 ] || fail "dock spread: last icon ends $((ww - last)) px from the edge"
  [ "$rx" -gt $((ww / 2)) ] || fail "dock spread: folders start at $rx"
fi

set_cfg dock center false
[ "$(ipc itemGeometry)" = "$dock_before" ] || fail "dock not restored after the panel"
echo "LAYOUT PASSED"

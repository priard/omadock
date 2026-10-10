#!/usr/bin/env bash
# Live: a parked window comes back to its own workspace and to its own place.
#
# The dock records, before parking a window, the rectangle of every window of the
# workspace; on restore it has to put each one back. Hyprland re-inserts a parked
# window as a new tiling window, so what can be asserted depends on where the parked
# window sat:
#
#   1. parking the window that is *last* in the visual order - every rectangle must
#      come back identical (the deterministic case);
#   2. parking the window nearest the root of the tree - the window itself and the
#      focus must come back, and the layout is reported but not asserted: by design it
#      may differ, because the tree is rebuilt and no exchange can repair a shape it
#      changed (measured; see the PR notes);
#   3. an emptied workspace must not keep the keyboard: the focus must not stay on the
#      parked window (measured with wtype: a single focus dispatch leaves it there,
#      which is why the dock hands the keyboard back with two).
#
# It opens its own windows on a borrowed workspace (an existing empty one when there is
# one, else a named workspace of its own) and closes exactly the addresses it opened,
# wherever they ended up - a terminal emulator rewrites the window title, so titles
# cannot be trusted to find them again. Windows that were already open are never
# touched. Needs a running dock: `omarchy-shell omadock state` must answer.
set -u
cd "$(dirname "$0")/../.."
. tests/live/common.sh
wait_ready || exit 1

TOLERANCE=4
TITLE="omadock-live-place"

# Both halves of what this test asserts are settings: a restore goes to its
# origin workspace, and the recorded place is won back. Pin them for the run and
# put the file back on exit (the dock re-reads omadock.json as it changes).
CFG=$HOME/.config/omarchy/omadock.json
bak=$(mktemp); cp "$CFG" "$bak"
python3 - "$CFG" <<'EOF'
import json, sys
c = json.load(open(sys.argv[1]))
c["restoreWorkspace"], c["restoreSlot"] = "origin", True
json.dump(c, open(sys.argv[1], "w"), indent=2)
EOF
sleep 1.5

TERM_APP=""
for candidate in alacritty kitty foot ghostty; do
  if command -v "$candidate" >/dev/null 2>&1; then TERM_APP="$candidate"; break; fi
done
if [ -z "$TERM_APP" ]; then
  echo "skip: no terminal emulator to open test windows with"
  exit 0
fi

ipc() { omarchy-shell omadock "$@"; }
hypr() { hyprctl "$@" 2>/dev/null; }

# Focus dispatching takes named workspaces as "name:foo", but hyprctl reports them as
# "foo": keep the two forms apart or no window is ever found.
ws_name() { echo "${1#name:}"; }

# One line per window of a workspace, in visual order: address x y w h
windows_of() {
  hypr -j clients | python3 -c '
import json, sys
want = sys.argv[1]
rows = []
for c in json.load(sys.stdin):
    ws = c.get("workspace") or {}
    if str(ws.get("name") or ws.get("id")) != want:
        continue
    rows.append((c["address"], c["at"][0], c["at"][1], c["size"][0], c["size"][1]))
rows.sort(key=lambda r: (r[1], r[2]))
for r in rows:
    print("%s %d %d %d %d" % r)
' "$1"
}

# Where one window is right now, by address ("" when it is gone).
where() {
  hypr -j clients | python3 -c '
import json, sys
want = sys.argv[1]
for c in json.load(sys.stdin):
    if c["address"] == want:
        print((c.get("workspace") or {}).get("name") or "")
        break
' "$1"
}

address_of_active() {
  hypr -j activewindow | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print(d.get("address") or "")
'
}

current_workspace() {
  hypr -j activeworkspace | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(d.get("name") or d.get("id") or "")
'
}

# An existing workspace with no windows, else a named one of our own.
pick_workspace() {
  hypr -j workspaces | python3 -c '
import json, sys
print("")
for w in json.load(sys.stdin):
    name = str(w.get("name") or "")
    if name == "" or name.startswith("special:"):
        continue
    if int(w.get("windows") or 0) == 0:
        print(name)
        break
'
}

# The dock rebuilds its model on window events (debounced), so a window that has just
# appeared is not in it yet: parking it then leaves the dock with nothing to restore
# from. Wait until the dock lists the window before touching it - a fixed sleep would
# only make the test flaky.
wait_window_seen() {
  local addr="$1" i
  for i in $(seq 40); do
    if ipc status 2>/dev/null | grep -q "$addr"; then return 0; fi
    sleep 0.2
  done
  echo "the dock never listed $addr" >&2
  return 1
}

original="$(current_workspace)"
workspace="$(pick_workspace)"
if [ -z "$workspace" ]; then
  workspace="name:$TITLE"
fi
OPENED=""

cleanup() {
  local addr
  for addr in $OPENED; do
    hypr dispatch "hl.dsp.window.close({ window = \"address:$addr\" })" >/dev/null 2>&1
  done
  [ -n "$original" ] && hypr dispatch "hl.dsp.focus({ workspace = \"$original\" })" >/dev/null 2>&1
}

fail() {
  echo "PLACE RESTORE FAILED: $*" >&2
  echo "--- windows on $workspace ---" >&2
  windows_of "$(ws_name "$workspace")" >&2
  exit 1
}

# Open windows of our own on the borrowed workspace and remember their addresses.
open_workspace() {
  local want="$1" addr n=0 got
  hypr dispatch "hl.dsp.focus({ workspace = \"$workspace\" })" >/dev/null 2>&1
  sleep 0.4
  while [ "$(windows_of "$(ws_name "$workspace")" | wc -l)" -lt "$want" ] && [ "$n" -lt 20 ]; do
    hypr dispatch "hl.dsp.exec_cmd(\"$TERM_APP --title $TITLE\")" >/dev/null 2>&1
    sleep 1.4
    n=$((n + 1))
  done
  got="$(windows_of "$(ws_name "$workspace")" | wc -l)"
  [ "$got" -eq "$want" ] || fail "could not open $want windows (got $got)"
  for addr in $(windows_of "$(ws_name "$workspace")" | cut -d' ' -f1); do
    case " $OPENED " in *" $addr "*) ;; *) OPENED="$OPENED $addr" ;; esac
  done
}

# cleanup also runs mid-test (section 3 borrows another workspace), so the
# config comes back only when the script is done.
finish() { cleanup; cp "$bak" "$CFG"; rm -f "$bak"; }
trap finish EXIT

# ---------------------------------------------------------------- 1. last window
open_workspace 3
before="$(windows_of "$(ws_name "$workspace")")"
last_addr="$(echo "$before" | tail -n 1 | cut -d' ' -f1)"
wait_window_seen "$last_addr" || fail "the dock did not see the last window"
hypr dispatch "hl.dsp.focus({ window = \"address:$last_addr\" })" >/dev/null 2>&1
sleep 0.8
ipc minimizeActive >/dev/null
sleep 1.2
[ "$(windows_of "$(ws_name "$workspace")" | wc -l)" -eq 2 ] || fail "the window was not parked"
ipc restoreLast >/dev/null
sleep 3.5
after="$(windows_of "$(ws_name "$workspace")")"
python3 - "$before" "$after" "$TOLERANCE" <<'PY' || fail "the last window did not come back identical"
import sys
before, after, tol = sys.argv[1], sys.argv[2], int(sys.argv[3])
def parse(block):
    out = {}
    for line in block.strip().splitlines():
        a, x, y, w, h = line.split()
        out[a] = (int(x), int(y), int(w), int(h))
    return out
b, a = parse(before), parse(after)
if set(b) != set(a):
    print("windows changed: %s vs %s" % (sorted(b), sorted(a)), file=sys.stderr)
    sys.exit(1)
for addr, rect in b.items():
    if any(abs(rect[i] - a[addr][i]) > tol for i in range(4)):
        print("window %s moved: %s -> %s" % (addr, rect, a[addr]), file=sys.stderr)
        sys.exit(1)
PY

# ---------------------------------------------------------------- 2. the root window
before2="$(windows_of "$(ws_name "$workspace")")"
root_addr="$(echo "$before2" | head -n 1 | cut -d' ' -f1)"
wait_window_seen "$root_addr" || fail "the dock did not see the root window"
hypr dispatch "hl.dsp.focus({ window = \"address:$root_addr\" })" >/dev/null 2>&1
sleep 0.8
ipc minimizeActive >/dev/null
sleep 1.2
ipc restoreLast >/dev/null
sleep 3.5
after2="$(windows_of "$(ws_name "$workspace")")"
echo "$after2" | grep -q "^$root_addr " || fail "the window parked from the root did not come back to its workspace"
[ "$(address_of_active)" = "$root_addr" ] || fail "the focus did not go back to the restored window"
if [ "$before2" != "$after2" ]; then
  echo "note: parking the window nearest the root rearranged the others (expected; see the header)"
fi

# ---------------------------------------------------------------- 3. an emptied workspace
cleanup
OPENED=""
original="$(current_workspace)"
workspace="$(pick_workspace)"
[ -n "$workspace" ] || workspace="name:$TITLE"
open_workspace 1
only_addr="$(windows_of "$(ws_name "$workspace")" | cut -d' ' -f1)"
wait_window_seen "$only_addr" || fail "the dock did not see the only window"
hypr dispatch "hl.dsp.focus({ window = \"address:$only_addr\" })" >/dev/null 2>&1
sleep 0.8
ipc minimizeActive >/dev/null
sleep 1.2
[ -z "$(windows_of "$(ws_name "$workspace")")" ] || fail "the only window was not parked"
[ "$(address_of_active)" != "$only_addr" ] || fail "the keyboard stayed on the parked window"
ipc restoreLast >/dev/null
sleep 3
[ -n "$(windows_of "$(ws_name "$workspace")")" ] || fail "the only window did not come back"

echo "PLACE RESTORE TEST PASSED: the last window comes back identical, the root window and the focus come back, an emptied workspace does not keep the keyboard"

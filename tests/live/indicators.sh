#!/usr/bin/env bash
# Live: the running marks sit dead-centre on the icon they belong to, in every
# shape the row takes - the accent bar of the focused window and the dots
# beside it.
#
# The marks are read as ink from a screenshot of the dock, so what is asserted
# is the row that is actually drawn, not the source that draws it: renaming a
# property or rewriting the row's layout passes as long as the marks stay
# centred, and a row that declares a slot it does not draw fails (a spare slot
# left a lone bar 2 px off its icon: Qt Grids reserve gaps for declared slots).
#
# It opens its own windows with an unused terminal emulator and gives the dock
# a flat opaque background (wallpaper texture reads as ink). Config, windows
# and focus are put back on exit.
#
# Keep the pointer off the measured item: hover scales the icon and moves the marks.
#
# Exit: 0 centred; 1 no answer, off-centre, or wrong count; 2 nothing to open
# a window with. Never 0 without measuring: a passing skip is a guard that
# cannot fail.
set -u
cd "$(dirname "$0")/../.."
. tests/live/common.sh
wait_ready || exit 1

# Slack: the bug measured 1.0-2.0 px, a centred row 0.0-0.5 px (pixel-grid
# rounding can move an outermost mark half a pixel).
TOL=0.75
TITLE="omadock-live-ind"
CFG=$HOME/.config/omarchy/omadock.json
bak=$(mktemp); cp "$CFG" "$bak"
client_addresses() {
  hyprctl -j clients 2>/dev/null | python3 -c '
import json, sys
print(" ".join(str(c.get("address") or "") for c in json.load(sys.stdin)))
'
}
known=" $(client_addresses) "
active=$(hyprctl -j activewindow 2>/dev/null | python3 -c '
import json, sys
try:
    print((json.load(sys.stdin) or {}).get("address") or "")
except Exception:
    print("")
')
OPENED=""

ipc() { omarchy-shell omadock "$@"; }
fail() { echo "INDICATORS FAILED: $*" >&2; exit 1; }

# Closes only the windows this test opened, hands the keyboard back, and puts
# the config file back byte for byte. Closing is attempted twice: a window can
# still be settling as the run ends.
cleanup() {
  local a i still=()
  for i in 1 2; do
    for a in $OPENED; do
      hyprctl dispatch "hl.dsp.window.close({ window = \"address:$a\" })" >/dev/null 2>&1
    done
    sleep 0.4
  done
  [ -n "$active" ] && hyprctl dispatch "hl.dsp.focus({ window = \"address:$active\" })" >/dev/null 2>&1
  cp "$bak" "$CFG"; rm -f "$bak" /tmp/omadock-ind-*
  for a in $OPENED; do
    case " $(client_addresses) " in *" $a "*) still+=("$a") ;; esac
  done
  [ ${#still[@]} -eq 0 ] || echo "note: still open:${still[*]}" >&2
}
trap cleanup EXIT

# Writes look keys into the config (the dock re-reads the file as it changes).
set_cfg() {
  python3 - "$CFG" "$@" <<'EOF'
import json, sys
c = json.load(open(sys.argv[1]))
for pair in sys.argv[2:]:
    key, value = pair.split("=", 1)
    c[key] = {"true": True, "false": False}.get(value, value)
json.dump(c, open(sys.argv[1], "w"), indent=2)
EOF
  sleep 2
  wait_ready || fail "the dock stopped answering after a config change"
}

# The dock's app items, as "id windows" lines, and one item's window count.
counts() {
  ipc itemGeometry | python3 -c '
import json, sys
for i in json.load(sys.stdin):
    if i["kind"] == "app":
        print(i["id"], i["windows"])
'
}
count_of() { counts | awk -v id="$1" '$1 == id { print $2 }'; }

# Waits until the dock shows at least this many windows for the target item.
wait_windows() {
  local i
  for i in $(seq 60); do
    [ "$(count_of "$TARGET")" -ge "$1" ] && return 0
    sleep 0.4
  done
  fail "the dock never showed $1 window(s) of $TARGET"
}

# Opens one more window of our own app and remembers the address it gained.
open_one() {
  local a i
  hyprctl dispatch "hl.dsp.exec_cmd(\"$TERM_APP --title $TITLE\")" >/dev/null 2>&1
  for i in $(seq 40); do
    sleep 0.4
    for a in $(client_addresses); do
      case " $known " in
        *" $a "*) ;;
        *) OPENED="$OPENED $a"; known="$known $a"; return 0 ;;
      esac
    done
  done
  fail "no $TERM_APP window appeared"
}

# Puts the focus on the newest window this test opened, so the accent bar the
# focused window draws is part of what is measured.
focus_ours() {
  hyprctl dispatch "hl.dsp.focus({ window = \"address:$(echo $OPENED | awk '{print $NF}')\" })" \
    >/dev/null 2>&1
  sleep 0.6
}

# check <what it is>: measures the target item's marks and fails unless they
# are the expected number, the shape this check is about, and centred on the
# icon.
check() {
  focus_ours
  python3 - "$TOL" "$TARGET" "$1" <<'PY' || fail "$1"
import collections, json, subprocess, sys, time

tol, item_id, label = float(sys.argv[1]), sys.argv[2], sys.argv[3]

def out(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout

def report(msg, ok):
    print(f"{label}: {msg}")
    sys.exit(0 if ok else 1)

for attempt in range(2):  # a second frame when the first caught the row mid-settle
    # The dock's layer: its size is the screenshot's frame, its place on the monitor
    # is where grim has to cut from. Item rectangles are layer-local.
    layer = monitor = None
    for name, m in json.loads(out("hyprctl", "-j", "layers")).items():
        for arr in m["levels"].values():
            for l in arr:
                if l.get("namespace") == "omadock":
                    monitor, layer = name, l
    if not layer:
        report("the dock has no layer on screen (hidden?)", False)
    scale, mx, my = 1.0, 0, 0
    for m in json.loads(out("hyprctl", "-j", "monitors")):
        if m["name"] == monitor:
            scale, mx, my = m.get("scale", 1.0), m["x"], m["y"]

    lx, ly = mx + layer["x"], my + layer["y"]
    shot = "/tmp/omadock-ind-shot.png"
    subprocess.run(["grim", "-g", f"{lx},{ly} {layer['w']}x{layer['h']}", shot], check=True)

    item = next((i for i in json.loads(out("omarchy-shell", "omadock", "itemGeometry"))
                 if i["id"] == item_id), None)
    if not item:
        report(f"the dock does not list {item_id}", False)
    x, y, w, h = item["x"], item["y"], item["w"], item["h"]
    # Hovering the item being measured scales it, and the marks
    # move with it: nothing on screen would match its rectangle.
    cursor = json.loads(out("hyprctl", "-j", "cursorpos"))
    if lx + x <= cursor.get("x", -1) < lx + x + w and ly + y <= cursor.get("y", -1) < ly + y + h:
        report("the pointer is over the item being measured: move it away and re-run", False)

    # Row marks live in the item's bottom band (top-touching ink is icon art).
    # The band is slack, not a policy read: a band grown with the policy would
    # follow a wrong size instead of catching it.
    band = max(10, round(8 * scale))
    cx, cy, cw, ch = x, y + h - band, w, band
    raw = {}
    for line in out("magick", shot, "-crop", f"{cw}x{ch}+{cx}+{cy}", "+repage", "txt:-").splitlines()[1:]:
        point, rest = line.split(":", 1)
        px, py = (int(v) for v in point.split(","))
        hexv = rest.split("#")[1][:6]
        raw[(px, py)] = tuple(int(hexv[i:i + 2], 16) for i in (0, 2, 4))
    if not raw:
        report(f"nothing on screen at {item_id}", False)
    # Ink differs from the crop's background well above grain speckle (a few
    # levels) and well below a mark's contrast (a hundred or more).
    near = [v for v in raw.values() if max(abs(a - b) for a, b in zip(v, (16, 16, 16))) <= 60] or list(raw.values())
    bg = collections.Counter(near).most_common(1)[0][0]
    ink = {p for p, v in raw.items() if max(abs(a - b) for a, b in zip(v, bg)) > 80}

    def groups(points):
        # Diagonals count as touching.
        rest, found = set(points), []
        while rest:
            seed = rest.pop()
            group, stack = {seed}, [seed]
            while stack:
                gx, gy = stack.pop()
                for nb in ((gx + 1, gy), (gx - 1, gy), (gx, gy + 1), (gx, gy - 1),
                           (gx + 1, gy + 1), (gx + 1, gy - 1),
                           (gx - 1, gy + 1), (gx - 1, gy - 1)):
                    if nb in rest:
                        rest.discard(nb); group.add(nb); stack.append(nb)
            found.append(group)
        return found

    def box(group):
        xs = [p[0] for p in group]
        ys = [p[1] for p in group]
        return min(xs), min(ys), max(xs), max(ys)

    def is_mark(group):
        """A speckle of grain that survived the cut is not ink."""
        return len(group) >= 3

    marks = [g for g in groups(ink) if min(p[1] for p in g) > 0 and is_mark(g)]
    if marks or attempt > 0:  # fail closed: a real miss fails twice identically
        break
    time.sleep(2)
if not marks:
    report(f"no marks under {item_id} (is anything running there?)", False)
xs = [p[0] for g in marks for p in g]
widths = [box(g)[2] - box(g)[0] + 1 for g in marks]
heights = [box(g)[3] - box(g)[1] + 1 for g in marks]
# The item's own centre: the row hangs on it.
off = ((min(xs) + max(xs) + 1) / 2 + cx) - (x + w / 2)

windows = item["windows"]
expected = 5 if windows > 5 else max(1, min(windows, 5))
# Shape check: the bar lies along the row.
shape = widths[0] > heights[0] if windows == 1 else max(widths) >= 1.8 * min(widths)
ok = len(marks) == expected and abs(off) <= tol and shape
line = (f"{item_id} · {windows} window(s) → {len(marks)} mark(s) of {expected} · "
        f"centre {abs(off):.1f} px off the icon's (tol {tol})")
report(line if ok else f"{line} · marks {widths}x{heights}", ok)
PY
}

# An unused terminal emulator, so the counted marks are the ones this test opened.
TERM_APP=""
shown=$(hyprctl -j clients 2>/dev/null | python3 -c '
import json, sys
try:
    print(" ".join(str(c.get("class") or "").lower() for c in json.load(sys.stdin)))
except Exception:
    print("")
')
for candidate in alacritty kitty foot ghostty wezterm; do
  command -v "$candidate" >/dev/null 2>&1 || continue
  case "$shown" in *"$candidate"*) continue ;; esac
  TERM_APP="$candidate"
  break
done
if [ -z "$TERM_APP" ]; then
  echo "INDICATORS SKIPPED: every terminal emulator is already showing a window," \
    "so this run would have measured nothing - close one and re-run." >&2
  exit 2
fi

counts > /tmp/omadock-ind-before
# Flat grain-free card, modal anchored at its colour: busy art can't elect the modal.
set_cfg autohide=false showBackground=true bgColor=#101010 grain=0 hoverEffect=off
open_one
TARGET=""
for i in $(seq 40); do
  TARGET=$(counts | python3 -c '
import sys
before = dict(line.split() for line in open("/tmp/omadock-ind-before"))
for line in sys.stdin:
    app, n = line.split()
    if int(n) > int(before.get(app, 0)):
        print(app)
        break
')
  [ -n "$TARGET" ] && break
  sleep 0.3
done
[ -n "$TARGET" ] || fail "the dock never listed the window this test opened"
echo "measuring $TARGET, opened with $TERM_APP"

# Each check measures the row as it is drawn and compares its ink with the
# icon's own centre line. Past five windows the count moves into the overflow
# pill, a mark whose ink (its text) sits inside its own cell, so a row that
# ends in one cannot be judged by where its ink lands: it is not checked.

# ------------------------------------------------- 1. the accent bar, alone
wait_windows 1
check "one window: the focused app's accent bar"

# --------------------------------------- 2. the bar beside its open window
open_one
wait_windows 2
check "two windows: the accent bar and a dot"

echo "INDICATORS PASSED"

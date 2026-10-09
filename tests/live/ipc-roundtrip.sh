#!/usr/bin/env bash
# Live: every IPC function round-trips and leaves the dock mapped with a
# clean log. Backs up omadock.json and restores it on exit. No input.
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
for page in appearance placement behavior effects size presets folders groups about; do
  ipc openSettingsPage "$page"; sleep 0.4
  [ "$(st settingsPage)" = "$page" ] || fail "openSettingsPage $page"
done
ipc closeSettings; sleep 0.5
[ "$(st settingsOpen)" = False ] || fail "closeSettings"

v=$(st visible)
ipc toggleVisibility; sleep 0.5; ipc toggleVisibility; sleep 0.5
[ "$(st visible)" = "$v" ] || fail "toggleVisibility twice"
ipc reveal; sleep 0.5

[ "$(ipc applyPreset no-such-preset-xyz)" = "not found" ] || fail "applyPreset unknown"
[ "$(ipc applyPreset "$(python3 -c 'print("x" * 10000)')")" = "not found" ] || fail "applyPreset 10k name"

# Presets: save the look on screen under a chosen name, list it, remove it.
# The list lives in omadock.json, which this script restores on exit.
pid=$(ipc savePreset verify_ipc_roundtrip)
[ -n "$pid" ] || fail "savePreset (six presets already saved? remove one to run this test)"
ipc presets | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert any(p['name'] == 'verify_ipc_roundtrip' and p['id'] == sys.argv[1] for p in d), d
" "$pid" || fail "presets() lists the saved one"
[ "$(ipc deletePreset "$pid")" = "ok" ] || fail "deletePreset"
ipc presets | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert not any(p['id'] == sys.argv[1] for p in d), d
" "$pid" || fail "presets() dropped the removed one"
[ "$(ipc deletePreset "$pid")" = "not found" ] || fail "deletePreset twice"

# One row per name, and no saved preset hidden: a shipped look and a preset of
# the same name are listed once, never twice, and the entry the user saved is
# always among the rows (DockPresets.merge). This is red on a dock that loaded
# its QML before a change to DockPresets.js -- this host disables QML file
# watching, so the running dock only picks the rule up on the next restart.
ipc presets > /tmp/omadock-presets.json
python3 - "$CFG" /tmp/omadock-presets.json <<'PY' || fail "one row per preset name"
import json, sys
rows = json.load(open(sys.argv[2]))
names = [str(r["name"]).strip().lower() for r in rows]
dupes = sorted({n for n in names if names.count(n) > 1})
if dupes:
    raise SystemExit("preset names listed more than once: %s" % ", ".join(dupes))
saved = [str(p.get("name", "")).strip().lower() for p in (json.load(open(sys.argv[1])).get("presets") or [])]
listed = [str(r["name"]).strip().lower() for r in rows if not r.get("builtin")]
missing = [n for n in saved if n not in listed]
if missing:
    raise SystemExit("saved presets missing from the list: %s" % ", ".join(missing))
PY

# The shipped looks ride with the dock: listed, marked, and not removable.
bid=$(ipc presets | python3 -c "
import json, sys
d = [p for p in json.load(sys.stdin) if p.get('builtin')]
if not d: sys.exit(1)
print(d[0]['id'])
") || fail "presets() does not list a shipped look"
[ "$(ipc deletePreset "$bid")" = "not found" ] || fail "a shipped preset is not removable"

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

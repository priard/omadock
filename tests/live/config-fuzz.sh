#!/usr/bin/env bash
# Live: malformed omadock.json contents must neither break the dock nor
# be rewritten by it. Backs up the config and restores it on exit.
set -u
cd "$(dirname "$0")/../.."
CFG=$HOME/.config/omarchy/omadock.json
bak=$(mktemp); cp "$CFG" "$bak"
work=$(mktemp -d)
restore() { cp "$bak" "$CFG"; rm -rf "$bak" "$work"; }
trap restore EXIT
since=$(date '+%Y-%m-%d %H:%M:%S')
rc=0

python3 - "$work" <<'EOF'
import json, pathlib, sys
w = pathlib.Path(sys.argv[1])
cases = {
    "empty": "", "garbage": "garbage{", "null": "null", "array": "[]", "string": '"str"',
    "infinity": '{"iconSize": 1e999, "systemBlurSize": 1e999}',
    "wrong-types": '{"iconSize": "big", "pinned": 5, "appGroups": "x", "autohide": "yes"}',
    "array-like": '{"appGroups": {"length": 1000000}, "pinnedFolders": {"length": 1000000}}',
    "bad-sound": '{"urgentSoundName": "../../../etc/passwd", "urgentSound": true}',
    "relative-folder": '{"pinnedFolders": [{"path": "-x"}, {"path": "rel"}]}',
    "oversize": json.dumps({"pad": "x" * (2 * 1024 * 1024)}),
}
for name, text in cases.items():
    (w / name).write_text(text)
EOF

for f in "$work"/*; do
  name=$(basename "$f")
  cp "$f" "$CFG"
  sleep 1.5
  hyprctl layers | grep -q "namespace: omadock" || { echo "FAIL $name: dock layer gone"; rc=1; }
  cmp -s "$f" "$CFG" || { echo "FAIL $name: the dock rewrote the file"; rc=1; }
done

cp "$bak" "$CFG"; sleep 1.5
bash tests/smoke-test.sh >/dev/null || { echo "FAIL: smoke test after fuzz"; rc=1; }
if journalctl --user --since "$since" | grep -iE "omadock/.*(TypeError|ReferenceError|is not a)"; then
  echo "FAIL: runtime errors in the log"; rc=1
fi
[ $rc = 0 ] && echo "CONFIG FUZZ PASSED"
exit $rc

#!/usr/bin/env bash
# The CappedFileView pre-read gate, extracted from the QML and run as the
# dock runs it: exit 0 + content, 2 = not a readable regular file,
# 3 = over the byte ceiling. GATE_QML overrides the source file.
set -u
cd "$(dirname "$0")/../.."
qml=${GATE_QML:-components/CappedFileView.qml}
gate=$(python3 - "$qml" <<'EOF'
import re, sys
src = open(sys.argv[1]).read()
block = re.search(r"gateScript:\s*\[(.*?)\]\.join\(\"\\n\"\)", src, re.S).group(1)
print("\n".join(re.findall(r"'((?:[^'\\]|\\.)*)'", block)))
EOF
)
[ -n "$gate" ] || { echo "gate script not found in $qml"; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
printf 'hello' > "$tmp/small"; head -c 2000 /dev/zero > "$tmp/big"; mkfifo "$tmp/fifo"; mkdir "$tmp/dir"
ln -s /dev/zero "$tmp/zero"
rc=0
check() { # name expected-exit path max [expected-output]
  out=$(timeout 5 sh -c "$gate" gate "$3" "$4"); code=$?
  if [ "$code" != "$2" ] || { [ $# -ge 5 ] && [ "$out" != "$5" ]; }; then
    echo "FAIL $1: exit $code, output '$out'"; rc=1
  fi
}
check small 0 "$tmp/small" 100 hello
check oversize 3 "$tmp/big" 1000
check directory 2 "$tmp/dir" 1000
check fifo 2 "$tmp/fifo" 1000
check dev-zero-symlink 2 "$tmp/zero" 1000
check missing 2 "$tmp/none" 1000
[ $rc = 0 ] && echo "capped gate: 6 cases ok"
exit $rc

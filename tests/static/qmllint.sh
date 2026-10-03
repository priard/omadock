#!/usr/bin/env bash
# qmllint (Qt 6) on every tracked QML file, compared with a committed
# baseline. --update rewrites the baseline after a reviewed change.
set -u
cd "$(dirname "$0")/../.."
QMLLINT=/usr/lib/qt6/bin/qmllint
[ -x "$QMLLINT" ] || { echo "skip: $QMLLINT missing"; exit 0; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
"$QMLLINT" --json "$tmp/lint.json" $(git ls-files '*.qml') >/dev/null 2>&1
python3 tests/static/qmllint_summary.py "$tmp/lint.json" > "$tmp/now.json" || exit 1
if [ "${1:-}" = "--update" ]; then cp "$tmp/now.json" tests/static/qmllint-baseline.json; exit 0; fi
python3 tests/static/qmllint_summary.py --compare tests/static/qmllint-baseline.json "$tmp/now.json"

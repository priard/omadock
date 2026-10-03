#!/usr/bin/env bash
# manifest.json parses, names the plugin and its entry point, and passes
# Omarchy's own validator. MANIFEST overrides the file (validator skipped).
set -u
cd "$(dirname "$0")/../.."
m=${MANIFEST:-manifest.json}
python3 - "$m" <<'EOF' || exit 1
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("id") == "omadock", "id"
assert d.get("entryPoints", {}).get("overlay") == "DockHost.qml", "entryPoints.overlay"
assert "overlay" in d.get("kinds", []), "kinds"
EOF
[ -n "${MANIFEST:-}" ] || omarchy plugin validate "$PWD"

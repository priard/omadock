#!/usr/bin/env bash
# Committed .qsb files must be exactly what the .frag sources compile to
# (qsb output is deterministic), so the binaries carry nothing the sources
# do not. SHADER_DIR overrides the directory checked.
set -u
cd "$(dirname "$0")/../.."
QSB=/usr/lib/qt6/bin/qsb
dir=${SHADER_DIR:-shaders}
[ -x "$QSB" ] || { echo "skip: $QSB missing"; exit 0; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
rc=0
for src in "$dir"/*.frag; do
  if ! "$QSB" --glsl "100 es,120,150" --hlsl 50 --msl 12 -o "$tmp/out.qsb" "$src" >/dev/null 2>&1; then
    echo "compile failed: $src"; rc=1; continue
  fi
  cmp -s "$tmp/out.qsb" "$src.qsb" || { echo "out of sync: $src.qsb"; rc=1; }
done
exit $rc

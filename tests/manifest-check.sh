#!/usr/bin/env bash

# Mirrors `omarchy plugin validate` (/usr/share/omarchy/bin/omarchy-plugin-validate)
# so pull requests get the same manifest gate on GitHub runners, which have no
# Omarchy install. Keep this in sync with the upstream validator: schemaVersion,
# required fields, safe relative entry points that exist, an entry point for each
# kind that needs one, barWidget.defaultSection, and no symlinks.

set -o pipefail

fail() {
  echo "manifest-check: $*" >&2
  exit 1
}

PLUGIN_DIR="${1:-}"
[[ -n $PLUGIN_DIR && -d $PLUGIN_DIR ]] || fail "plugin folder not found: ${PLUGIN_DIR:-<none>}"

MANIFEST="$PLUGIN_DIR/manifest.json"
[[ -f $MANIFEST ]] || fail "missing manifest.json in $PLUGIN_DIR"
jq -e . "$MANIFEST" >/dev/null 2>&1 || fail "manifest.json is not valid JSON: $MANIFEST"

# schemaVersion must be exactly the JSON number 1 (jq's == is type-aware).
jq -e '.schemaVersion == 1' "$MANIFEST" >/dev/null 2>&1 \
  || fail "unsupported or missing schemaVersion (expected 1) in $MANIFEST"

for field in id name version kinds entryPoints; do
  jq -e --arg f "$field" 'has($f)' "$MANIFEST" >/dev/null 2>&1 \
    || fail "manifest missing required field '$field'"
done

ID=$(jq -r '.id // ""' "$MANIFEST")
[[ -n $ID ]] || fail "manifest 'id' is empty"
[[ $ID =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "invalid plugin id '$ID'"
[[ $ID != *".."* ]] || fail "invalid plugin id '$ID'"
[[ $ID != omarchy.* ]] || fail "plugin id '$ID' uses the reserved omarchy.* namespace"

# kinds must be a non-empty array.
jq -e '(.kinds | type) == "array" and (.kinds | length) > 0' "$MANIFEST" >/dev/null 2>&1 \
  || fail "'kinds' must be a non-empty array"

# entryPoints must be an object.
jq -e '(.entryPoints | type) == "object"' "$MANIFEST" >/dev/null 2>&1 \
  || fail "'entryPoints' must be an object"

# barWidget.defaultSection, when declared, must be left, center, or right.
jq -e '
  if ((.barWidget? | type) == "object" and (.barWidget | has("defaultSection"))) then
    .barWidget.defaultSection as $section
    | ($section | type) == "string"
      and (["left", "center", "right"] | index($section)) != null
  else
    true
  end
' "$MANIFEST" >/dev/null 2>&1 \
  || fail "'barWidget.defaultSection' must be left, center, or right"

# Read each entry point as a JSON-encoded string (one per line), then decode it,
# so a value that itself contains a newline stays one literal path.
while IFS= read -r ep_json; do
  [[ -n $ep_json ]] || continue
  ep=$(jq -r '.' <<<"$ep_json")
  [[ -n $ep ]] || fail "entry point path is empty"
  [[ $ep != *$'\n'* ]] || fail "entry point may not contain a newline"
  [[ $ep != /* ]] || fail "entry point must be a relative path: '$ep'"
  [[ $ep != *".."* ]] || fail "entry point may not contain '..': '$ep'"
  [[ -f "$PLUGIN_DIR/$ep" ]] || fail "entry point file not found: '$ep'"
done < <(jq -c '.entryPoints | to_entries[] | .value' "$MANIFEST")

# A kind is a promise to supply something to load under a fixed key.
for kind_entry_point in \
  "bar:bar" \
  "bar-widget:barWidget" \
  "menu:menu" \
  "overlay:overlay" \
  "panel:panel" \
  "service:service"; do
  kind="${kind_entry_point%%:*}"
  entry_point="${kind_entry_point##*:}"
  jq -e --arg kind "$kind" '(.kinds | index($kind)) != null' "$MANIFEST" >/dev/null 2>&1 || continue
  jq -e --arg ep "$entry_point" '.entryPoints | has($ep)' "$MANIFEST" >/dev/null 2>&1 \
    || fail "kind '$kind' requires an 'entryPoints.$entry_point' to load"
done

# Refuse any symlink anywhere inside the plugin folder (git internals excepted).
link=$(find "$PLUGIN_DIR" -name .git -prune -o -type l -print -quit 2>/dev/null)
[[ -z $link ]] || fail "symlinks are not allowed inside a plugin folder: $link"

exit 0

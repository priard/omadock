#!/usr/bin/env bash
# A second Quickshell instance running THIS working tree's DockHost.qml, for
# live tests that must not touch the desktop the owner is using.
#
# Why this exists: the launcher runs Quickshell with QS_DISABLE_FILE_WATCHER=1,
# so the running dock keeps executing the code it loaded. A live test that
# drives it through `omarchy-shell omadock` therefore tests the previous
# release, not the tree in front of you - and it opens the settings overlay on
# the owner's screen. This harness runs the plugin's own entry point in its own
# instance instead, against a byte-copy of the config under a redirected HOME,
# and keeps it off screen (autohide on, exclusiveZone 0, hide() called).
#
# Usage - source it, then start/stop around your checks:
#
#   . tests/live/probe.sh
#   probe_start || exit 1
#   probe_ipc presets                     # IPC against the probe instance
#   probe_cfg                             # the probe's own config copy
#   probe_cleanup                         # kill, remove, re-check the owner
#
# probe_cleanup re-checks the owner's side and prints what it found: the
# omadock.json md5 and the shell PID it recorded at probe_start must be
# unchanged, and no probe process may be left. It returns non-zero otherwise,
# so end a test with `probe_cleanup || exit 1`.
#
# Notes worth keeping:
#  - qs.* modules resolve from the CONFIG DIRECTORY, so the shell's Commons and
#    Ui directories are symlinked into the probe directory; QML2_IMPORT_PATH
#    does not help and the modules are otherwise "not installed".
#  - An absolute path import needs the file: schema ("is not a valid import
#    URL" without it).
#  - XDG_RUNTIME_DIR is never overridden: the Wayland socket lives there
#    (a redirected one fails with "Failed to create wl_display"). The IPC
#    socket keys off the config path, so the probe stays separately addressable
#    as `qs -p "$PROBE_DIR" ipc call omadock ...`.
#  - A "qt.qpa.services ... portal" warning is normal for a second instance.
#  - The probe is a real dock on the owner's session, so keep its surfaces off
#    screen: never openSettings / openSettingsPage (a full-screen overlay would
#    cover the owner's desktop) and never reveal / toggleVisibility without
#    hiding again. The hide() at start and probe_stop are what make it
#    invisible - a test that calls those on the probe is not non-intrusive.
#
# Functions: probe_start, probe_ipc, probe_cfg, probe_wait_cfg, probe_log_tail,
#            probe_running, probe_pids, probe_stop, probe_cleanup.

# PROBE_CFG_SRC points the probe at another config to copy: the owner's file
# (the default) or, for a case the owner's config cannot show - a fresh install
# with no saved presets - a synthetic one. The copy is still the only file the
# probe or the test may read and write; the source is never touched.
PROBE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE_OWNER_CFG="${PROBE_CFG_SRC:-${HOME}/.config/omarchy/omadock.json}"
PROBE_OWNER_MD5=""
PROBE_OWNER_PID=""
PROBE_DIR=""
PROBE_PID=""

# The plugin directory under test (not the live plugin under
# ~/.config/omarchy/plugins/omadock, which follows the active profile).
probe_root() { echo "$PROBE_ROOT"; }

# Start the probe. 0 on success; on failure the log tail is printed and the
# caller should probe_cleanup and stop.
# The probe's own processes: real quickshell/qs binaries whose command line
# names the probe directory. `pgrep -f` alone also matches any unrelated
# process that merely mentions the path (a shell running a monitoring command,
# an editor), which would both report a leak that is not there and, through
# pkill -f, kill something that is not the probe. The executable is checked
# for that reason, and cleanup kills the PIDs it identified.
probe_pids() {
  local p exe
  for p in $(pgrep -f -- " -p $PROBE_DIR" 2>/dev/null); do
    exe=$(basename "$(readlink -f "/proc/$p/exe" 2>/dev/null || true)")
    case "$exe" in quickshell|qs) echo "$p" ;; esac
  done
}

probe_start() {
  local i
  if [ ! -f "$PROBE_OWNER_CFG" ]; then
    echo "probe: no config at $PROBE_OWNER_CFG to copy" >&2
    return 1
  fi
  PROBE_OWNER_MD5=$(md5sum "$PROBE_OWNER_CFG" | cut -d' ' -f1)
  PROBE_OWNER_PID=$(pgrep -x quickshell | head -1)
  PROBE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/omadock-probe-XXXXXX") || return 1
  mkdir -p "$PROBE_DIR/home/.config/omarchy"
  cp "$PROBE_OWNER_CFG" "$PROBE_DIR/home/.config/omarchy/omadock.json"
  # The owner's file as it was, kept for comparisons; the dock only ever writes
  # the copy under the probe's HOME.
  cp "$PROBE_OWNER_CFG" "$PROBE_DIR/owner-config.json"
  # Hidden and harmless: never covers a window, never reserves desktop space.
  python3 - "$PROBE_DIR/home/.config/omarchy/omadock.json" <<'PY'
import json, sys
path = sys.argv[1]
try:
    conf = json.load(open(path))
except Exception:
    conf = {}
if not isinstance(conf, dict):
    conf = {}
conf["autohide"] = True
conf["exclusiveZone"] = 0
json.dump(conf, open(path, "w"), indent=2)
PY
  ln -s /usr/share/omarchy/shell/Commons "$PROBE_DIR/Commons"
  ln -s /usr/share/omarchy/shell/Ui "$PROBE_DIR/Ui"
  cat > "$PROBE_DIR/shell.qml" <<EOF
import Quickshell
import "file:$PROBE_ROOT" as Od

ShellRoot {
  Od.DockHost { }
}
EOF
  ( cd "$PROBE_DIR" && HOME="$PROBE_DIR/home" QS_DISABLE_FILE_WATCHER=1 \
      setsid --fork qs -p "$PROBE_DIR" > "$PROBE_DIR/probe.log" 2>&1 </dev/null )
  for i in $(seq 40); do
    if qs -p "$PROBE_DIR" ipc call omadock state >/dev/null 2>&1; then
      PROBE_PID=$(probe_pids | head -1)
      probe_ipc hide >/dev/null 2>&1
      return 0
    fi
    sleep 0.5
  done
  echo "probe: the dock never answered over IPC" >&2
  probe_log_tail >&2
  return 1
}

# An IPC call against the probe, arguments passed through literally (the
# endpoint takes names, not JSON - `applyPreset "Nameplates"`, never the id).
probe_ipc() { qs -p "$PROBE_DIR" ipc call omadock "$@"; }

# The probe's config copy: the only file a live test may assert on or mutate.
probe_cfg() { echo "$PROBE_DIR/home/.config/omarchy/omadock.json"; }

# Wait (up to ~8s) until a python predicate on the config copy holds. Argument 1
# is the program, the config path is argv[1] and further arguments follow it; the
# program exits non-zero while the dock has not written the file yet. A preset
# save or delete lands on disk a moment after the IPC call returns, so a test
# that reads the file straight after one races the write and reports a state
# that has already passed. Best-effort pacing only: the caller keeps its own
# assertion, which is what explains a real failure.
#
#   probe_wait_cfg 'import json,sys; c=json.load(open(sys.argv[1]));
#                    sys.exit(0 if sys.argv[2] in [p["id"] for p in c.get("presets") or []] else 1)' "$id"
#   python3 - "$CFG" "$id" <<'PY'   # the real assertion, with its diagnostics
probe_wait_cfg() {
  local prog=$1 i
  shift
  for i in $(seq 40); do
    python3 -c "$prog" "$(probe_cfg)" "$@" >/dev/null 2>&1 && return 0
    sleep 0.2
  done
  return 1
}

probe_log_tail() { tail -20 "$PROBE_DIR/probe.log" 2>/dev/null; }

probe_running() { [ -n "$PROBE_DIR" ] && [ -n "$(probe_pids)" ]; }

probe_stop() {
  local i pids
  [ -n "$PROBE_DIR" ] || return 0
  pids=$(probe_pids)
  [ -n "$pids" ] && kill $pids 2>/dev/null
  for i in $(seq 20); do
    [ -n "$(probe_pids)" ] || break
    sleep 0.25
  done
  pids=$(probe_pids)
  [ -n "$pids" ] && kill -9 $pids 2>/dev/null
}

# Stop the probe, remove its directory, and report the owner's side. Returns
# non-zero if the owner's config or shell changed, or anything was left behind.
probe_cleanup() {
  local rc=0 now nowpid
  probe_stop
  if [ -n "$PROBE_OWNER_MD5" ]; then
    now=$(md5sum "$PROBE_OWNER_CFG" | cut -d' ' -f1)
    if [ "$now" = "$PROBE_OWNER_MD5" ]; then
      echo "probe: owner's omadock.json unchanged (md5 $now)"
    else
      echo "probe: OWNER CONFIG CHANGED ($PROBE_OWNER_MD5 -> $now)" >&2
      rc=1
    fi
    nowpid=$(pgrep -x quickshell | head -1)
    if [ "$nowpid" = "$PROBE_OWNER_PID" ]; then
      echo "probe: owner's shell PID unchanged ($nowpid)"
    else
      echo "probe: OWNER SHELL PID CHANGED ($PROBE_OWNER_PID -> $nowpid)" >&2
      rc=1
    fi
  fi
  if [ -n "$(probe_pids)" ]; then
    echo "probe: a probe process is still running ($(probe_pids | tr '\n' ' '))" >&2
    rc=1
  fi
  [ -n "$PROBE_DIR" ] && rm -rf "$PROBE_DIR"
  PROBE_DIR=""
  return $rc
}

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
#  - qs.* modules resolve from the CONFIG DIRECTORY: the shell's Commons and Ui
#    directories are symlinked into the probe directory (QML2_IMPORT_PATH does
#    not help; otherwise they are "not installed"). An absolute path import
#    needs the file: schema ("is not a valid import URL" without it).
#  - XDG_RUNTIME_DIR is never overridden: the Wayland socket lives there (a
#    redirected one fails with "Failed to create wl_display"). The IPC socket
#    keys off the config path, so the probe stays addressable as
#    `qs -p "$PROBE_DIR" ipc call omadock ...`.
#  - A "qt.qpa.services ... portal" warning is normal for a second instance.
#  - Keep its surfaces off screen: never openSettings / openSettingsPage (a
#    full-screen overlay would cover the owner's desktop) and never reveal /
#    toggleVisibility without hiding again. The hide() at start and probe_stop
#    are what make it invisible - a test that calls those is not non-intrusive.
#
# A probe session must leave NOTHING behind: the dock spawns helpers through
# `Process` (scripts/drive-removal-watch.py, the folder scanner) and they do not
# exit with the shell - they are reparented to the user's systemd and keep
# running (80 had accumulated on this desktop). probe_stop kills the session's
# whole process group plus every descendant it can see, and probe_cleanup fails
# on a surviving process or scratch directory (tests/live/teardown.sh keeps it).
#
# Functions: probe_start, probe_ipc, probe_cfg, probe_ready, probe_wait_cfg,
#            probe_wait_presets, probe_log, probe_log_tail, probe_pids,
#            probe_descendants, probe_pgid, probe_group_pids, probe_cmdlines,
#            probe_stop, probe_cleanup.

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
# The probe's own process group (it is started with `setsid --fork`, so the
# group holds the shell and every helper it spawned) and what teardown saw.
PROBE_PGID=""
PROBE_LEAKED=""

# The probe's own processes: real quickshell/qs binaries whose command line
# names the probe directory. `pgrep -f` alone also matches anything that merely
# mentions the path (an editor, a monitoring shell), which would report a leak
# that is not there and, through pkill -f, kill something that is not ours.
probe_pids() {
  local p exe
  # No directory yet (probe_start refused a missing config, say): " -p " with
  # nothing after it would match the owner's own dock and report it as ours.
  [ -n "$PROBE_DIR" ] || return 0
  for p in $(pgrep -f -- " -p $PROBE_DIR" 2>/dev/null); do
    exe=$(basename "$(readlink -f "/proc/$p/exe" 2>/dev/null || true)")
    case "$exe" in quickshell|qs) echo "$p" ;; esac
  done
}

# The probe's process group: `setsid --fork` makes the Quickshell process a
# group leader, so the group is the whole session. Recorded at start, because
# the group is unreadable once the leader is gone.
probe_pgid() { [ -n "$PROBE_PGID" ] && echo "$PROBE_PGID"; }

# This shell's own process group, so a group kill can never take the caller.
probe_own_pgid() { ps -o pgid= -p $$ 2>/dev/null | tr -d ' '; }

# Every process reachable from the given PIDs by parentage - the helpers a
# Quickshell dock spawns. A snapshot of the tree, walked breadth-first; a
# helper spawned after the snapshot is caught by probe_group_pids instead.
probe_descendants() {
  local snap frontier next pid kid out depth
  [ -n "$1" ] || return 0
  snap=$(ps -eo pid=,ppid= 2>/dev/null)
  frontier="$*"
  out=""
  for depth in 1 2 3 4 5 6; do
    next=""
    for pid in $frontier; do
      kid=$(printf '%s\n' "$snap" | awk -v pp="$pid" '$2 == pp {print $1}' | tr '\n' ' ')
      next="$next $kid"
    done
    next=$(echo $next)
    [ -n "$next" ] || break
    out="$out $next"
    frontier="$next"
  done
  echo $out
}

# Anything still in the probe's process group. Nothing of the owner's can be
# in it (their dock is not started with setsid), so a match is litter.
probe_group_pids() {
  [ -n "$PROBE_PGID" ] || return 0
  ps -eo pid=,pgid= 2>/dev/null | awk -v g="$PROBE_PGID" '$2 == g {print $1}'
}

# The command lines behind a list of PIDs, for the failure report.
probe_cmdlines() {
  local p out
  for p in $*; do
    out="$out $p:$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)"
  done
  echo $out
}

# 1 when the dock has applied its config copy: its preset listing is not empty
# (DockConfigLogic.qml:120 is that list's only writer, and a merge always yields
# the shipped looks, so an empty listing means the file is not read yet). A
# first read before it lands sees no preset at all - measured 1 session in 8 -
# which is what made presets.sh fail intermittently; probe_start waits on this
# so no call site has to wait on its own.
probe_ready() {
  probe_ipc presets 2>/dev/null | python3 -c 'import json,sys
d = json.load(sys.stdin)
sys.exit(0 if isinstance(d, list) and d else 1)' 2>/dev/null
}

# Start the probe. 0 on success; on failure the log tail is printed and the
# caller should probe_cleanup and stop.
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
  # PROBE_BODY names a QML file whose contents become the body of ShellRoot,
  # for a test that must reach inside the dock (tests/live/label-metrics.sh).
  # Such a body declares its own `Od.DockHost { ... }`; the default is the dock
  # alone. Imports go at the top, so the body holds only what is inside ShellRoot.
  {
    printf 'import QtQuick\nimport Quickshell\nimport "file:%s" as Od\n\nShellRoot {\n' "$PROBE_ROOT"
    if [ -n "${PROBE_BODY:-}" ]; then cat "$PROBE_BODY"; else printf '  Od.DockHost { }\n'; fi
    printf '}\n'
  } > "$PROBE_DIR/shell.qml"
  ( cd "$PROBE_DIR" && HOME="$PROBE_DIR/home" QS_DISABLE_FILE_WATCHER=1 \
      setsid --fork qs -p "$PROBE_DIR" > "$PROBE_DIR/probe.log" 2>&1 </dev/null )
  for i in $(seq 40); do
    # Recorded before the IPC wait, so a start that never answers is still
    # torn down with its group (and its helpers) rather than left behind.
    [ -n "$PROBE_PID" ] || PROBE_PID=$(probe_pids | head -1)
    [ -n "$PROBE_PGID" ] || PROBE_PGID=$(ps -o pgid= -p "${PROBE_PID:-0}" 2>/dev/null | tr -d ' ')
    if qs -p "$PROBE_DIR" ipc call omadock state >/dev/null 2>&1 && probe_ready; then
      probe_ipc hide >/dev/null 2>&1
      return 0
    fi
    sleep 0.5
  done
  echo "probe: the dock never answered over IPC with its config applied" >&2
  probe_log_tail >&2
  return 1
}

# An IPC call against the probe, arguments passed through literally (the
# endpoint takes names, not JSON - `applyPreset "Nameplates"`, never the id).
probe_ipc() { qs -p "$PROBE_DIR" ipc call omadock "$@"; }

# The probe's config copy: the only file a live test may assert on or mutate.
probe_cfg() { echo "$PROBE_DIR/home/.config/omarchy/omadock.json"; }

# Wait (up to ~8s) until a python predicate on the config copy holds: argv[1] is
# the program, the config path is argv[2] and further arguments follow; it exits
# non-zero while the dock has not written the file. Pacing only - the caller
# keeps the assertion that explains a real failure (see probe_wait_presets).
probe_wait_cfg() {
  local prog=$1 i
  shift
  for i in $(seq 40); do
    python3 -c "$prog" "$(probe_cfg)" "$@" >/dev/null 2>&1 && return 0
    sleep 0.2
  done
  return 1
}

# Wait until the presets in the config copy satisfy one condition: every id
# given is present (`probe_wait_presets in <id>...`) or every id is absent
# (`out <id>...`). A save or delete lands a moment after the IPC call returns.
probe_wait_presets() {
  local want=$1
  shift
  probe_wait_cfg 'import json,sys
c = json.load(open(sys.argv[1]))
ids = [p["id"] for p in c.get("presets") or []]
hits = [i for i in sys.argv[3:] if i in ids]
ok = hits == sys.argv[3:] if sys.argv[2] == "in" else not hits
sys.exit(0 if ok else 1)' "$want" "$@"
}

probe_log() { echo "$PROBE_DIR/probe.log"; }

probe_log_tail() { tail -20 "$PROBE_DIR/probe.log" 2>/dev/null; }

# Stop the probe AND everything it spawned: the helpers a dock spawns under
# `Process` do not die with the shell (they are reparented), so the whole
# process group is signalled and any descendant that left it is hunted by PID.
# Whatever survives both is recorded in PROBE_LEAKED for probe_cleanup to fail.
probe_stop() {
  local i pids pgid p survivors
  [ -n "$PROBE_DIR" ] || return 0
  pids=$(probe_pids)
  pgid=$(probe_pgid)
  if probe_group_killable "$pgid"; then kill -TERM -- "-$pgid" 2>/dev/null; fi
  [ -n "$pids" ] && kill $pids 2>/dev/null
  for i in $(seq 20); do
    [ -z "$(probe_pids)" ] && break
    sleep 0.25
  done
  if probe_group_killable "$pgid"; then kill -KILL -- "-$pgid" 2>/dev/null; fi
  [ -n "$pids" ] && kill -9 $pids 2>/dev/null
  sleep 0.3
  PROBE_LEAKED=""
  survivors="$(probe_group_pids) $(probe_descendants "$PROBE_PID")"
  for p in $survivors; do
    [ "$p" = "$$" ] && continue
    kill -9 "$p" 2>/dev/null && PROBE_LEAKED="$PROBE_LEAKED $p"
  done
  PROBE_LEAKED=$(echo $PROBE_LEAKED)
}

# A group kill is only safe when the group is a real one, is not init's, and
# is not this shell's own (that would kill the test that is running it).
probe_group_killable() {
  local g=$1 own
  [ -n "$g" ] || return 1
  [ "$g" = "1" ] && return 1
  own=$(probe_own_pgid)
  [ -n "$own" ] && [ "$g" = "$own" ] && return 1
  return 0
}

# Stop the probe, remove its directory, and report the owner's side. Returns
# non-zero if the owner's config or shell changed, or anything was left behind
# - a process of the session's group, a helper that outlived it, or the
# scratch directory itself.
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
  # Nothing of the session may survive it. The group scan catches a helper
  # spawned after probe_stop's snapshot; PROBE_LEAKED names one that was
  # still alive when teardown finished.
  local leftovers
  leftovers=$(echo $(probe_group_pids) $PROBE_LEAKED | tr ' ' '\n' | sort -n -u | tr '\n' ' ')
  leftovers=$(echo $leftovers)
  if [ -n "$leftovers" ]; then
    echo "probe: LEFT BEHIND by the session:$(probe_cmdlines $leftovers)" >&2
    kill -9 $leftovers 2>/dev/null
    rc=1
  fi
  if [ -n "$PROBE_DIR" ]; then
    rm -rf "$PROBE_DIR"
    if [ -e "$PROBE_DIR" ]; then
      echo "probe: scratch directory survived ($PROBE_DIR)" >&2
      rc=1
    fi
  fi
  PROBE_DIR=""
  PROBE_PID=""
  PROBE_PGID=""
  PROBE_LEAKED=""
  return $rc
}

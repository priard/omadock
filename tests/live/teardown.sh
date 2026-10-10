#!/usr/bin/env bash
# Every probe session must leave nothing behind: not a process, not a
# directory.
#
# A Quickshell dock spawns helpers through `Process` (scripts/drive-removal-watch.py,
# the folder scanner) and a helper does not exit with the shell that spawned
# it: it is reparented to the user's systemd and keeps polling forever. Stopping
# only the Quickshell process therefore leaked one helper per session, and 80
# had accumulated on this desktop before this test existed - litter produced by
# the harness that exists to be non-intrusive.
#
# The fix is in tests/live/probe.sh (probe_stop kills the session's process
# group and every descendant, probe_cleanup fails on a survivor or a surviving
# scratch directory). This test is the regression test for it: it starts fresh
# sessions and counts what is still running afterwards, so the next leak fails
# a test instead of accumulating.
#
# Non-intrusive: the sessions are the same hidden second instance
# tests/live/presets.sh uses - this tree's DockHost.qml against a byte-copy of
# the config under a redirected HOME, autohide on, exclusiveZone 0. Nothing is
# shown on screen and the owner's own config is only read.
#
# Usage: ./tests/live/teardown.sh [sessions]     (default 3)

set -u
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
# shellcheck source=tests/live/probe.sh
. ./probe.sh

SESSIONS=${1:-3}
fail=0

# The helper a running dock spawns, assembled from fragments so this test's own
# command line cannot match it (a search on the literal name matches the
# process asking the question - which then kills the wrong thing).
HELPER='drive-removal-'"watch.py"
helper_pids() {
  ps -eo pid=,args= | WATCH="$HELPER" awk 'index($0, ENVIRON["WATCH"]) {print $1}' | sort -n
}

# Scratch directories a session creates; a surviving one is visible even when
# nothing is running any more.
scratch_dirs() { ls -d "${TMPDIR:-/tmp}"/omadock-probe-* 2>/dev/null | sort; }

owner_shell=$(pgrep -x quickshell | head -1)
before_helpers=$(helper_pids | tr '\n' ' ')
before_dirs=$(scratch_dirs | tr '\n' ' ')
# Whether the LIVE dock has a helper of its own: it must still be there at the
# end, which is what proves the teardown's group kill never reaches the owner.
owner_helper=""
for p in $before_helpers; do
  if [ "$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null)" = "$owner_shell" ]; then
    owner_helper="$p"
  fi
done

echo "-- $SESSIONS fresh probe session(s), each started and stopped"
for i in $(seq "$SESSIONS"); do
  if ! probe_start; then
    echo "   FAIL: session $i never started" >&2
    probe_cleanup >/dev/null 2>&1
    fail=1
    break
  fi
  echo "   session $i up ($(probe_pids | tr '\n' ' '))"
  probe_ipc state >/dev/null 2>&1
  # Its own report (owner md5, owner shell PID, anything left behind) and its
  # exit status: a session that leaks fails here, in every suite that uses it.
  probe_cleanup || fail=1
done

echo "-- helpers of a running dock"
after_helpers=$(helper_pids | tr '\n' ' ')
new_helpers=""
for p in $after_helpers; do
  case " $before_helpers " in
    *" $p "*) ;;
    *) new_helpers="$new_helpers $p" ;;
  esac
done
new_helpers=$(echo $new_helpers)
if [ -z "$new_helpers" ]; then
  echo "   no helper appeared across the sessions"
else
  for p in $new_helpers; do
    ppid=$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null)
    if [ -n "$owner_shell" ] && [ "$ppid" = "$owner_shell" ]; then
      echo "   the live dock's own helper appeared ($p) - not a leak"
    else
      echo "   FAIL: helper $p (ppid=${ppid:-gone}) outlived its session: $(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)" >&2
      fail=1
    fi
  done
fi
if [ -n "$owner_helper" ]; then
  if kill -0 "$owner_helper" 2>/dev/null; then
    echo "   the live dock's own helper ($owner_helper) is untouched"
  else
    echo "   FAIL: the live dock's own helper ($owner_helper) is gone" >&2
    fail=1
  fi
fi

echo "-- scratch directories"
after_dirs=$(scratch_dirs | tr '\n' ' ')
new_dirs=""
for d in $after_dirs; do
  case " $before_dirs " in
    *" $d "*) ;;
    *) new_dirs="$new_dirs $d" ;;
  esac
done
if [ -n "$(echo $new_dirs)" ]; then
  echo "   FAIL: scratch director(ies) left behind:$(echo $new_dirs)" >&2
  fail=1
else
  echo "   no probe directory was left behind"
fi

if [ "$fail" = "0" ]; then
  echo "TEARDOWN PASSED: $SESSIONS session(s), nothing left behind"
else
  echo "TEARDOWN FAILED" >&2
fi
exit $fail

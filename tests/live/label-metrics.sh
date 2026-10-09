#!/usr/bin/env bash
# A dock tile's name shortening must survive its own metrics being destroyed.
#
# components/DockLabel.qml shortens the name with a search that writes into the
# label's own TextMetrics (`probe.text = t`, line 97). The call is deferred
# (Qt.callLater), so it can land in the window where a delegate's children have
# been destroyed and the label itself has not - and there the write is a null
# dereference. That is not hypothetical: the quickshell logs hold seven
# occurrences today, every one at DockLabel.qml:97, with
#   TypeError: Value is null and could not be converted to an object
#   (exception occurred during delayed function evaluation)
# and the live suite's clean-log assertion failed on one of them.
#
# This test manufactures that state instead of waiting for it: it runs the real
# dock (tests/live/probe.sh with a fixture body), destroys a real label's two
# TextMetrics from outside, proves the deletion landed, and calls reshorten()
# directly. Without the guard in reshorten() the call throws the message above;
# with it, the call is a no-op and the label keeps the name it had.
#
# It also pins the ordinary path first (LM-INTACT: a long name really is
# shortened), so a guard that broke shortening could not pass.
#
# Non-intrusive: a hidden second Quickshell instance on a byte-copy of the
# config under a redirected HOME (see tests/live/probe.sh). Nothing is shown on
# screen; the owner's config is only read. Warnings from the fixture's own
# destruction (a binding that reads a destroyed metric) are tolerated - the
# assertions name the statement under test.

set -u
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
# shellcheck source=tests/live/probe.sh
. ./probe.sh

# The fixture body probe_start puts inside ShellRoot (see its header).
PROBE_BODY="$PWD/label-metrics-shell.qml"
export PROBE_BODY

fail=0
note() { echo "   $*"; }

echo "-- a real dock label, its metrics destroyed, reshorten() called"
if ! probe_start; then
  echo "   FAIL: the probe never started" >&2
  probe_cleanup >/dev/null 2>&1
  exit 1
fi
# The fixture works at 4 s and quits right after; wait for its last marker. It
# quits the instance itself, so probe_cleanup has nothing left to stop.
for _ in $(seq 40); do
  grep -q "LM-DONE" "$(probe_log)" 2>/dev/null && break
  sleep 0.5
done
log=$(cat "$(probe_log)" 2>/dev/null || true)
probe_cleanup || fail=1

marker() { printf '%s\n' "$log" | grep -m1 "$1"; }

intact=$(marker "LM-INTACT")
after=$(marker "LM-AFTER")
if [ -z "$intact" ]; then
  echo "   FAIL: the fixture never reached a dock label" >&2
  fail=1
else
  note "$(echo "$intact" | sed 's/^.*LM-INTACT/LM-INTACT/')"
  if ! printf '%s\n' "$intact" | grep -q "shortened=true"; then
    echo "   FAIL: the ordinary path did not shorten the long name" >&2
    fail=1
  fi
fi

if [ -z "$after" ]; then
  echo "   FAIL: the metrics were never destroyed (fixture invalid)" >&2
  fail=1
else
  note "$(echo "$after" | sed 's/^.*LM-AFTER/LM-AFTER/')"
  before_n=$(printf '%s\n' "$intact" | sed -n 's/.* data=\([0-9]*\)$/\1/p')
  after_n=$(printf '%s\n' "$after" | sed -n 's/.* data=\([0-9]*\)$/\1/p')
  if [ -z "$before_n" ] || [ -z "$after_n" ] || [ "$after_n" -ge "$before_n" ]; then
    echo "   FAIL: the label's children did not go away (${before_n:-?} -> ${after_n:-?})" >&2
    fail=1
  else
    note "the label's children went from $before_n to $after_n"
  fi
fi

if printf '%s\n' "$log" | grep -q "LM-THREW"; then
  echo "   FAIL: reshorten() threw with the metrics gone:" >&2
  printf '%s\n' "$log" | grep -m2 "LM-THREW" | sed 's/^/     /' >&2
  fail=1
else
  note "$(marker "LM-RESHORTEN" | sed 's/^.*LM-RESHORTEN/LM-RESHORTEN/')"
fi

# The dock's own log must carry no fault at the statement: the deferred
# reshorten() queued by the fixture's name change lands in the same window, so
# an unguarded statement logs the wild line even when the direct call is caught.
if printf '%s\n' "$log" | grep -qE "DockLabel\.qml\[97"; then
  echo "   FAIL: the dock logged a fault at DockLabel.qml:97:" >&2
  printf '%s\n' "$log" | grep -m3 "DockLabel\.qml\[97" | sed 's/^/     /' >&2
  fail=1
else
  note "no fault logged at DockLabel.qml:97"
fi

if [ "$fail" = "0" ]; then
  echo "LABEL METRICS PASSED: reshorten() survives its metrics being gone"
else
  echo "LABEL METRICS FAILED" >&2
fi
exit $fail

# Shared by the live tests that drive the RUNNING dock (sourced).
#
# A test that needs wait_ready/omarchy-shell talks to the dock on the owner's
# desktop: it writes the live config and exercises the code the running dock
# loaded (the launcher sets QS_DISABLE_FILE_WATCHER=1, so that is the previous
# release, not this working tree). Prefer tests/live/probe.sh, which runs the
# plugin's own entry point in a second Quickshell instance against a byte-copy
# of the config under a redirected HOME - see tests/live/presets.sh.

# Quickshell reloads the plugin whenever any file in its directory changes
# (a commit, __pycache__, an editor's swap file), and the IPC target is gone
# for about half a second. Wait until the dock answers twice in a row.
wait_ready() {
  local i
  for i in $(seq 60); do
    if omarchy-shell omadock state 2>/dev/null | grep -q '"docks"'; then
      sleep 1
      omarchy-shell omadock state 2>/dev/null | grep -q '"docks"' && return 0
    fi
    sleep 0.3
  done
  echo "the dock did not answer over IPC" >&2
  return 1
}

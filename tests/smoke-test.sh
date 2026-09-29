#!/usr/bin/env bash
# OmaDock load-time smoke test (read-only, part of the verification suite).
#
# The dock's worst failure mode is silent: a QML type error during component
# creation only surfaces as a WARN ("Process is not a type", "Type Dock
# unavailable") in the shell log while the overlay simply never maps — the
# dock just isn't there. This test asserts the plugin actually instantiated
# in the live Omarchy shell:
#
#   1. hyprctl layers  -> an overlay layer with namespace "omadock" exists
#   2. qs ipc show     -> the "omadock" IPC target is registered
#   3. quickshell log  -> no omadock QML runtime errors ("is not a type",
#                         TypeError, ReferenceError, "Type ... unavailable")
#
# Read-only: it only inspects the running shell and never launches anything.
# Exit 0 = plugin live and clean, 1 = failure (evidence printed to stderr).
#
# Usage: tests/smoke-test.sh [--restart]
#   --restart  run `omarchy restart shell` and wait 8s before probing

set -u

SHELL_PATH="/usr/share/omarchy/shell"

fail() {
  echo "SMOKE TEST FAILED: $*" >&2
  exit 1
}

if [ "${1:-}" = "--restart" ]; then
  omarchy restart shell
  sleep 8
fi

# 1. The overlay layer must be mapped (DockHost -> Dock instantiated).
hyprctl layers | grep -q "namespace: omadock" \
  || fail "no omadock layer in 'hyprctl layers' — the dock failed to instantiate (look for '... is not a type' / 'Type ... unavailable' in the shell log)"

# 2. The IPC target must be registered (DockHost completed its IpcHandler).
qs -p "$SHELL_PATH" ipc show 2>/dev/null | grep -q "target omadock" \
  || fail "IPC target 'omadock' is not registered in 'qs ipc show'"

# 3. The shell log must not carry omadock QML runtime errors.
suspects="$(quickshell log -p "$SHELL_PATH" -t 30 2>&1 \
  | grep -iE "error|TypeError|ReferenceError|is not a type|unavailable" \
  | grep -iE "dock|omadock|settings" | head -n 3)"
if [ -n "$suspects" ]; then
  printf '%s\n' "$suspects" >&2
  fail "omadock QML errors found in the shell log (see above)"
fi

echo "SMOKE TEST PASSED: omadock layer mapped, IPC target registered, log clean"

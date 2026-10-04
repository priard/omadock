#!/usr/bin/env bash
# OmaDock tests. --offline (default): unit and static checks, nothing
# outside temp dirs is touched. --live: checks against the running shell
# (backs up and restores omadock.json, no clicks, no keyboard). --all: both.
set -u
cd "$(dirname "$0")/.."
# Writing __pycache__ inside the plugin directory would make Quickshell
# reload the live dock.
export PYTHONDONTWRITEBYTECODE=1
mode=${1:---offline}
fail=0
step() {
  local name=$1; shift
  printf '\n== %s\n' "$name"
  if "$@"; then printf 'ok   %s\n' "$name"; else printf 'FAIL %s\n' "$name"; fail=1; fi
}
offline() {
  step "DockModel (node)" node --test tests/unit/*.test.js tests/unit/*.test.mjs
  step "scripts (python)" python3 -m unittest discover -s tests/unit -p 'test_*.py'
  step "shaders in sync" bash tests/static/shaders-in-sync.sh
  step "manifest" bash tests/static/manifest.sh
  step "manifest (upstream CI gate)" bash tests/manifest-check.sh .
  step "qmllint baseline" bash tests/static/qmllint.sh
  step "security grep" python3 tests/static/security-grep.py
}
live() {
  step "smoke" bash tests/smoke-test.sh
  step "ipc round-trip" bash tests/live/ipc-roundtrip.sh
  step "config fuzz" bash tests/live/config-fuzz.sh
  # tests/launch-harness.py is not run here: it fails on any installed
  # desktop entry GIO cannot resolve (hidden local overrides), which says
  # more about the system than the dock. Run it by hand; see README.
}
case $mode in
  --offline) offline ;;
  --live) live ;;
  --all) offline; live ;;
  *) echo "usage: $0 [--offline|--live|--all]"; exit 2 ;;
esac
printf '\n%s\n' "$([ $fail = 0 ] && echo 'ALL PASSED' || echo 'SOME FAILED')"
exit $fail

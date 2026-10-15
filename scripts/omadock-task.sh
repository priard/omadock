#!/bin/sh
# OmaDock Task Reporter & Wrapper
#
# Reports command execution status (running/success/error), duration, and exit code
# to OmaDock's Task HUD via Quickshell IPC.
#
# Usage as a command wrapper:
#   scripts/omadock-task.sh cargo build --release
#   scripts/omadock-task.sh npm test
#
# Usage as direct IPC caller:
#   scripts/omadock-task.sh report <appId> <status> <exitCode> <title> <duration>
#   scripts/omadock-task.sh clear <appId>
#   scripts/omadock-task.sh status
#
# Exit status:
#   report/clear/status  the IPC call's own outcome. Non-zero, with the reason
#                        on stderr, when the dock is not reachable.
#   wrapped command      the wrapped command's own exit code. A report that
#                        could not be delivered is shouted on stderr and does
#                        NOT change it: the command's status is what a wrapper
#                        exists to report.
#
# OMADOCK_SHELL_PATH overrides the shell config directory the IPC socket is
# looked up under (default /usr/share/omarchy/shell), so a test can drive a
# dock that is not the owner's.
SHELL_PATH="${OMADOCK_SHELL_PATH:-/usr/share/omarchy/shell}"

# 0 when a dock answers under $SHELL_PATH and exposes the IPC function $1.
# `qs ipc call` prints "Function not found." to STDOUT and still exits 0, so
# neither its output nor its status alone can be trusted.
ipc_available() {
  command -v qs >/dev/null 2>&1 || return 1
  qs -p "$SHELL_PATH" ipc show 2>/dev/null | awk -v fn="$1" '
    /^target / { on = ($2 == "omadock") }
    on && $1 == "function" && index($2, fn "(") == 1 { found = 1 }
    END { exit found ? 0 : 1 }'
}

# The one way this script talks to the dock. Says why on stderr and answers
# non-zero rather than silently doing nothing.
call_ipc() {
  if ! ipc_available "$1"; then
    echo "omadock-task: omadock.$1 is not available under $SHELL_PATH - is the dock running?" >&2
    return 1
  fi
  qs -p "$SHELL_PATH" ipc call omadock "$@"
}

detect_terminal() {
  if [ -n "$OMADOCK_APP" ]; then
    echo "$OMADOCK_APP"
    return
  fi

  ai_app=""
  if [ -n "$AI_AGENT" ]; then
    ai_app="$AI_AGENT"
  elif [ -n "$ANTIGRAVITY_AGENT" ]; then
    ai_app="antigravity"
  elif [ -n "$CLAUDE_CODE" ] || [ -n "$CLAUDE_SESSION_ID" ]; then
    ai_app="claude"
  elif [ -n "$AIDER_ANALYTICS" ] || [ -n "$AIDER_DIR" ] || [ -n "$AIDER_MODEL" ]; then
    ai_app="aider"
  elif [ -n "$CURSOR_VERSION" ] || [ -n "$CURSOR_PROJECT_DIR" ]; then
    ai_app="cursor"
  elif [ -n "$WINDSURF_VERSION" ]; then
    ai_app="windsurf"
  elif [ -n "$OPEN_INTERPRETER" ]; then
    ai_app="interpreter"
  fi

  curr=$$
  term_app=""
  while [ -n "$curr" ] && [ "$curr" -gt 1 ] 2>/dev/null; do
    comm=$(cat "/proc/$curr/comm" 2>/dev/null)
    case "$comm" in
      agy|antigravity)
        [ -z "$ai_app" ] && ai_app="antigravity"
        ;;
      claude|claude-code)
        [ -z "$ai_app" ] && ai_app="claude"
        ;;
      aider|aider-chat)
        [ -z "$ai_app" ] && ai_app="aider"
        ;;
      ollama)
        [ -z "$ai_app" ] && ai_app="ollama"
        ;;
      cursor|cursor-bin)
        [ -z "$ai_app" ] && ai_app="cursor"
        ;;
      windsurf)
        [ -z "$ai_app" ] && ai_app="windsurf"
        ;;
      gemini|gemini-cli)
        [ -z "$ai_app" ] && ai_app="gemini"
        ;;
      aichat)
        [ -z "$ai_app" ] && ai_app="aichat"
        ;;
      sgpt)
        [ -z "$ai_app" ] && ai_app="sgpt"
        ;;
      mods)
        [ -z "$ai_app" ] && ai_app="mods"
        ;;
      interpreter|open-interpreter)
        [ -z "$ai_app" ] && ai_app="interpreter"
        ;;
      fabric)
        [ -z "$ai_app" ] && ai_app="fabric"
        ;;
      copilot|github-copilot)
        [ -z "$ai_app" ] && ai_app="copilot"
        ;;
      mentat)
        [ -z "$ai_app" ] && ai_app="mentat"
        ;;
      ghostty|kitty|alacritty|foot|footclient|wezterm|wezterm-gui|konsole|gnome-terminal*|tilix|xterm|xfce4-terminal|kgx|st)
        if [ -z "$term_app" ]; then
          term_app="$comm"
        fi
        ;;
    esac
    curr=$(awk '{print $4}' "/proc/$curr/stat" 2>/dev/null)
  done

  if [ -n "$ai_app" ] && [ -n "$term_app" ]; then
    echo "${ai_app}|${term_app}"
    return
  fi
  if [ -n "$ai_app" ]; then
    echo "$ai_app"
    return
  fi
  if [ -n "$term_app" ]; then
    echo "$term_app"
    return
  fi
  if [ -n "$TERM_PROGRAM" ]; then
    echo "$TERM_PROGRAM"
    return
  fi
  echo "terminal"
}

case "$1" in
  report)
    shift
    call_ipc reportTask "$@"
    exit $?
    ;;
  clear)
    shift
    call_ipc clearTask "$@"
    exit $?
    ;;
  status)
    call_ipc taskStatus
    exit $?
    ;;
  "")
    echo "Usage: omadock-task <command...> | report <args> | clear <appId> | status" >&2
    exit 1
    ;;
esac

# Running as a wrapper around an executable command
APP_ID=$(detect_terminal)
CMD_NAME="$*"
START_TIME=$(date +%s)

# Execute command
"$@"
EXIT_CODE=$?

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))
[ "$DURATION" -lt 0 ] && DURATION=0

STATUS="done"
[ "$EXIT_CODE" -ne 0 ] && STATUS="error"

# Report final status. The report is a side channel: if it cannot be delivered
# the wrapped command's own exit code still stands, but the failure is loud.
if ! call_ipc reportTask "$APP_ID" "$STATUS" "$EXIT_CODE" "$CMD_NAME" "$DURATION" >/dev/null; then
  echo "omadock-task: the task status was not reported to the dock (the command's exit code $EXIT_CODE stands)" >&2
fi

exit $EXIT_CODE

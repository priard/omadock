#!/bin/bash
# One place for the dock's user-facing notifications. Arguments pass through
# quoted variables only; nothing is ever interpolated.
#
# notify-send goes first with options before "--", so a title or body that
# starts with a dash (a drive label like "-u...") stays text. When notify-send
# is missing or broken (a libnotify ABI mismatch fails it at startup and the
# warning would be silently lost), fall back to Omarchy's own sender, which
# takes the headline and description as positional text.

icon=$1
title=$2
body=$3

if command -v notify-send >/dev/null 2>&1 && notify-send -a omadock -i "$icon" -- "$title" "$body" 2>/dev/null; then
  exit 0
fi
if command -v omarchy-notification-send >/dev/null 2>&1; then
  exec omarchy-notification-send --app-name omadock -i "$icon" "$title" "$body"
fi
exit 1

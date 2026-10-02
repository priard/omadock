# Hover window previews Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The tooltip of a running app shows still thumbnails of its windows as a card stack that the wheel rotates.

**Architecture:** A new `WindowCardStack.qml` renders the cards and owns the captures (`ScreencopyView` in a `Loader` per card, active only while the tooltip is visible and the card is among the front three). `DockItem.qml` puts it in the tooltip in place of the title rows and feeds it the existing `selectedWindowIdx`.

**Tech Stack:** QML, Quickshell 0.3.1 (`Quickshell.Wayland._Screencopy`, `ToplevelManager`), Hyprland 0.56.

**Spec:** `docs/superpowers/specs/2026-10-02-hover-window-previews-design.md`

## Global Constraints

- One frame per capture (`live: true` until `hasContent`, then `live: false`); no capture while the tooltip is hidden.
- At most three cards hold a capture at a time (front + two peeking).
- One window: a single card, no stack, no counter.
- "Window previews" off (`advancedTooltips: false`): the title list.
- Branch `feat/window-previews` from `upstream/main`; no FORK.md, manifest or docs/superpowers in it.

## Review Focus

- Window closed while its card is shown: the card must drop out, not crash on a dead toplevel (the Repeater follows `tooltipWindows`; captureSource goes null → icon fallback).
- Window on another workspace or a hidden special workspace: the capture still arrives (measured: it does).
- Capture fails (`stopped` signal): icon fallback instead of an empty card.
- Very tall or very wide windows: thumbnail fits the card frame, letterboxed, never stretched.
- Tooltip near the screen edge: the wider tooltip still clamps inside the dock window (existing `x` clamp uses `width`).

---

### Task 1: WindowCardStack and tooltip integration

**Files:**
- Create: `components/WindowCardStack.qml`
- Modify: `components/DockItem.qml` (tooltip `Column`, ~line 490-555)

**Interfaces:**
- `WindowCardStack { rootRef; windows: var[]; frontIndex: int; active: bool; fallbackIcon: url }`

- [ ] Write `WindowCardStack.qml`: cards positioned by `depth = (index - frontIndex + n) % n`; depth 0/1/2 get y 0/-10/-20 px, scale 1/0.94/0.88, opacity 1/0.8/0.55, depth ≥ 3 opacity 0; `Behavior` (180 ms, OutCubic) on y/scale/opacity; z = 10 - depth. Each card: framed `Rectangle`, `Loader` (active: `stack.active && depth <= 2`) holding a `ScreencopyView` sized to fit the frame by `sourceSize` aspect, app icon underneath as fallback. Counter badge "i/n" on the front card when n > 1.
- [ ] In `DockItem.qml`: `frontIndex` = `selectedWindowIdx` if ≥ 0, else the focused window's index, else 0. When `advancedTooltips` and windows exist: name, stack, front window's `windowRowLabel` below. Otherwise title rows as today, shown when `!advancedTooltips`.
- [ ] Smoke test; temporary `debugTooltip(appId)` IPC forcing the tooltip open; screenshot with 1 and 2 windows (zen), after a rotation; restore DockHost.qml and grep the debug function is gone.
- [ ] VRAM before / tooltip open / after close (`nvidia-smi`).
- [ ] Commit.

### Task 2: Settings hint, branch and merge

**Files:**
- Modify: `components/SettingsPanel.qml` (hint of "Window previews")

- [ ] Hint: "Thumbnails of an app's windows in its tooltip; scroll to flip through them." Commit.
- [ ] Dry-run merge into `priard` with `git merge-tree --write-tree`, merge, smoke test.

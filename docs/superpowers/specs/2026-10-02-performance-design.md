# Performance: CPU, RAM and VRAM — design

Date: 2026-10-02. Status: approved in conversation, awaiting spec review.
Part 2 of 4. Depends on the benchmark (part 1) for before/after numbers.
Goes upstream as two PRs: `feat/perf-fixes` (small, independent fixes) and
`feat/popup-windows` (the surface refactor), both cut from `upstream/main`.

## Goal

Keep the author's "zero-CPU background" promise true in every state, cut
the CPU spent per event and per hover, and shrink the dock's RAM and
especially VRAM. Priority: CPU first, then VRAM, then RAM.

## Evidence (2026-10-02)

- The dock costs ~194 MiB VRAM and ~38 MB RSS (plugin disabled vs enabled,
  fresh restart). Idle CPU difference is within noise (~0.15 %).
- Shrinking the layer from 5120x1404 to 5120x420 saved 132 MiB VRAM (68 %
  of the dock's VRAM). Most of the remaining 62 MiB is the 5120 px width.
- Audit findings with file:line are summarised below.

## A. `feat/popup-windows`: card-sized dock surface

Today `Dock.qml:4207` gives the `PanelWindow` a height of almost the full
screen and anchors it left and right, so Qt keeps buffers for 5120x1404
logical (10240x2808 at DPR 2) and every animation frame damages the whole
surface, which Hyprland recomposites and blurs at 120 Hz. The input mask
(`Dock.qml:4209`) limits input only.

### Architecture

- The dock `PanelWindow` (namespace `omadock`) covers only the card plus
  the room needed for magnification and hover lift. Width and height derive
  from the card; for left/right positions the axes swap. The surface is
  resized when items are added or removed, at the end of the size
  animation, not on every frame.
- Each popup becomes a Quickshell `PopupWindow` anchored to the dock window:

| today (inside the dock layer) | after |
|---|---|
| hover tooltip, incl. window previews (`HoverTooltip`, `WindowCardStack`) | `PopupWindow` created on show, destroyed on hide |
| `DockContextMenu` | `PopupWindow` via `LazyLoader`; its pages become `Loader`s too |
| `FolderPopup` (stacks) | `PopupWindow` via `LazyLoader` |
| `AppGroupPopup` | `PopupWindow` via `LazyLoader` |

- Outside-click dismissal, today a full-surface `MouseArea`
  (`globalDismiss`, `Dock.qml:4272`), becomes `HyprlandFocusGrab` covering
  the popup and the dock window.
- Drop gaps (`DropGhost`) and reordering stay inside the card, so in the
  dock window. Dragging a file out of a stack into the dock crosses two
  surfaces through ordinary Wayland DnD, as dragging into other apps
  already does.
- Popup blur: the existing runtime layer rule (`_G.omadock_blur_rule`) is
  extended to the popups' namespace(s).

### Risks and how they are handled

1. Edge placement: `PopupWindow` anchors with an adjustment policy (flip or
   slide) so menus stay on screen.
2. First popup frame may appear one frame later than today; acceptable,
   verified by eye by the user.
3. Hover tooltip churn: creating a window per hover could cost more CPU
   than it saves; the tooltip window is kept alive while the pointer moves
   between items and destroyed after the hide delay. Measured with S1.
4. Large upstream diff: one commit per popup, each leaving the dock
   working, so the author can review step by step.

### Success criteria

- `--full` benchmark: dock VRAM cost drops from ~194 MiB to ≤ 40 MiB.
- S1 (hover sweep): Hyprland CPU and quickshell render-thread CPU drop
  measurably versus the baseline.
- All popups, drag-and-drop paths and dismissal behave as before (user
  tests clicks and drags).

## B. `feat/perf-fixes`: CPU per event and idle guarantees

| # | where | fix |
|---|---|---|
| 1 | `DockItem.qml:123-145` urgent bounce/pulse `loops: Animation.Infinite` | bounce a fixed number of times (~10), then a static indicator; the idle CPU guarantee holds with urgent windows |
| 2 | `Dock.qml:1940,1947` closewindow refreshes synchronously and via `modelTimer` | keep only the debounced timer (keep `modelSettleTimer`) |
| 3 | `Dock.qml:1947-1949` workspace events rebuild the whole model | update only per-window workspace fields, or debounce harder if that proves fragile |
| 4 | `handleThemeChanged` (`Dock.qml:2223`) fired by up to 5 sources, each running `rescanApps()` + `refreshDock()` | coalesce into one run via a short timer |
| 5 | `DockModel.js:683` `entryFor` runs `getCandidates()` regexes over all desktop rows for unmatched apps; `hyprToplevelFor` (`Dock.qml:2642`) is a linear scan per toplevel | cache entry and icon lookups per appId, cleared when the app list or theme changes; build the wayland→hypr map once per rebuild |
| 6 | `Dock.qml:255-303` icon index streams ~23.6k lines into a `SplitParser` | dedupe in the shell command and parse once with a `StdioCollector` |
| 7 | `DockItem.qml:241` `mediaPlayerFor` per pinned item on every MPRIS change | one appId→player map at Dock level |
| 8 | `DockCard.qml:454` shadow layers enabled while invisible | `layer.enabled: visible` |
| 9 | `DockIconArt.qml:84` per-icon shadow layer re-rendered every magnification frame | render at fixed size and scale, or one shadow under the row |
| 10 | `FileTile.qml:68-93` hidden MultiEffect and icon image load even with a thumbnail | load only when shown |
| 11 | window previews: up to 6 full-resolution captures (~66 MB each on 7680x2160) | lower the cap to 3 front cards, keep scaled-down copies for cards behind |

Each fix is one commit with its own benchmark note where measurable
(S0/S1/S4/S5/S6).

## RAM

The dock's own share is ~38 MB. Gains come from not instantiating hidden
UI (context menu pages, popups via `LazyLoader`), not loading unused
images, and the icon index fix. No target number is promised before
measuring; the `--full` comparison is reported in the PRs.

## Order of work

1. Benchmark (part 1), then a baseline run (`--full --events`).
2. `feat/perf-fixes`, measured.
3. `feat/popup-windows`, measured.
4. Final comparison quoted in both PR bodies.

## Already efficient (do not touch)

SettingsPanel via `LazyLoader`; keyed delegates (`KeyedListModel`); icons
decoded at a fixed `sourceSize`; HoverFx glow and lift shadow enabled only
while used; static gradient/grain shaders; no polling timers; drives via
`udevadm monitor`; folder listing capped and virtualised; window preview
cards exist only while the tooltip is open.

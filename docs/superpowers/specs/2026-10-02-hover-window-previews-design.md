# Hover window previews (card stack) — design

## Goal

Hovering a running app on the dock shows what its windows look like, not just
their titles, without costing anything while the dock is idle. Today the
"Window previews" switch (`advancedTooltips`) only adds a list of window
titles to the tooltip, although its hint promises live thumbnails.

## Behaviour

- After the tooltip delay, the tooltip of a running app shows a **card**: a
  still thumbnail of one window (about 260 px wide, the window's aspect
  ratio) with the app name above and the window title below.
- With 2+ windows the cards form a **stack**: up to two further cards peek
  out behind the front one, offset upwards and slightly smaller, and a
  counter reads "2/5".
- The **wheel over the icon** rotates the stack (both directions, wrapping):
  the front card slides back and drops to the end of the stack while the
  next one rises to the front (~180 ms). This reuses the existing
  `selectedWindowIdx` wheel logic, so the stack starts at the focused
  window like the title list does.
- **Click on the icon** focuses the front card's window (existing behaviour
  of `selectedWindowIdx`). Scrolling never switches windows by itself.
- One window: a single card, no stack. No windows (pinned, not running):
  the plain name tooltip as today.
- The preview is not interactive (same as the tooltip today); no keyboard
  arrows, because the dock layer would have to grab the keyboard on hover.
- Switch "Window previews" off: the current title list comes back. The
  switch's hint is corrected.

## Resource rules

Measured on the live dock (RTX 4090, 3812x1991 windows): one capture is
~30 MB VRAM, the image arrives 4-17 ms after the view is created, ~5 ms CPU
in quickshell and ~20 ms in Hyprland; VRAM returns to baseline after the
views are destroyed (the driver frees it a few seconds later).

- Thumbnails exist only while the tooltip is shown: each card's
  `ScreencopyView` sits in a `Loader` active only then, so buffers are
  released when the tooltip hides.
- Only the cards that are visible (front + up to 2 peeking) capture; a card
  gets its capture when it becomes visible.
- One frame per capture (`live: true` until `hasContent`, then
  `live: false`), never a live stream.
- The tooltip delay keeps a pass of the pointer across the dock from
  capturing anything.

## Structure

- New `components/WindowCardStack.qml`: takes the window list, the front
  index and the dock root; resolves each window's toplevel by address
  (`root.liveToplevelForAddress`), lays out and animates the cards, and owns
  the capture loaders. Falls back to the app icon on a card whose capture
  fails or has no toplevel.
- `components/DockItem.qml`: the tooltip shows `WindowCardStack` instead of
  the title rows when `advancedTooltips` is on and the app has windows.
- `components/SettingsPanel.qml`: hint text for "Window previews".

## Testing

- Smoke test after each step; temporary `debugX` IPC to force a tooltip open
  on a given app and screenshot it with `grim` (single window, 2 windows,
  5+ windows, a window on another workspace, a parked window).
- VRAM before/after opening and closing previews (`nvidia-smi`).
- Wheel rotation and click-to-focus are checked by the user.

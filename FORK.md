# omadock — fork `priard`

Local fork of https://github.com/thepathless/omadock (remote `upstream`,
no `origin`, so `omarchy plugin update` leaves it alone).

Sync: `git fetch upstream && git merge upstream/main`

## Changes

- **Settings panel** (`components/SettingsPanel.qml`). Right-click on the
  Omarchy button (or on the dock background) → *Dock Settings…* opens a
  full panel with a sidebar: Appearance, Placement, Behavior, Effects,
  Size & Spacing, Folders, App Groups. Changes apply live. Esc or a click
  outside closes it. The old category sub-menus in `DockContextMenu.qml`
  are left in place (unreachable) to keep upstream merges clean.
- **Appearance toggles**: `showBackground`, `showShadow`, `showBorder`
  (config keys in `~/.config/omarchy/omadock.json`, default `true`).
- **Monitor picker** in Placement, plus upstream's multi-monitor switches
  (`multiMonitor`, `perMonitorApps`); `screen` can be reset to automatic.
- **Resume fix**: taken from upstream v3.7.3 (#9, rebuild the surface after
  the compositor closes it). The fork's own re-arm timer was dropped in the
  merge; only the `realScreens` helper remains, for the monitor picker.
- **IPC** (in `DockHost.qml`, acts on the focused monitor's dock):
  `omarchy-shell omadock openSettings | openSettingsPage <page> |
  closeSettings` (pages: appearance, placement, behavior, effects, size,
  folders, groups).

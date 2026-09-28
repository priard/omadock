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
- **Monitor picker**: `screen` can be reset to automatic (key removed).
- **Resume fix**: the nameless placeholder screen Qt creates while all
  outputs are gone (DP drops off on DPMS blank / suspend) is never used as
  the dock screen, and the dock surface is unmapped on every output change
  and mapped again 1.5 s later, so it always comes back on a live output.
- **IPC**: `omarchy-shell omadock openSettings | openSettingsPage <page> |
  closeSettings` (pages: appearance, placement, behavior, effects, size,
  folders, groups).

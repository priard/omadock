# Appearance presets — design

Date: 2026-10-02. Status: approved in conversation, awaiting spec review.

## Goal

Save the dock's current look as a named preset and switch between saved
looks quickly: from a new Settings page, from the dock's right-click menu,
and through IPC (for keybinds). Each preset shows a small live thumbnail.

Out of scope for now: export/import, sharing, built-in presets, and binding
presets to Omarchy themes (a later idea, see "Future").

## What a preset holds

A preset is `{ id, name, look }`. `look` holds every value from the
Appearance, Effects and Size & Spacing pages, plus the visual options on the
Folders and App Groups pages, under their **config key names** (the names
`saveConfig` writes), always all of them, explicitly:

| config key | property | notes |
|---|---|---|
| `showBackground` | showBackground | |
| `bgColor` | dockBgColor | |
| `bgFill` | bgFill | `solid` / `gradient` |
| `gradientPreset` | gradientPreset | |
| `gradientStrength` | gradientStrength | |
| `grain` | grain | |
| `opacity` | dockOpacity | `"theme"` or 0..1 |
| `blur` | blurMode | `system` / `on` / `off`; applying calls `applyBlurRule` |
| `showShadow` | showShadow | |
| `shadowStrength` | shadowStrength | |
| `showBorder` | showBorder | |
| `borderWidth` | borderWidth | |
| `borderOpacity` | borderOpacity | `"theme"` or 0..1 |
| `shape` | dockShape | |
| `cornerRadius` | cornerRadius | `-1` = follow shape/theme (config omits the key) |
| `splitSections` | splitSections | |
| `dividerHeight`, `dividerStyle`, `dividerWidth`, `dividerOpacity` | same | |
| `iconStyle`, `iconTint`, `iconHoverOriginal`, `iconContrast`, `iconStrength`, `iconGrid` | same | |
| `indicatorShape` | indicatorShape | |
| `hoverEffect`, `launchBounce` | same | Effects page |
| `groupStyle`, `groupIconEffects` | same | App Groups → Look |
| `folderColor` | folderColor | Folders → Folder color |
| `iconSize` | configuredIconSize | `0` = automatic (config omits the key) |
| `itemSpacing`, `sectionSpacing` | same | |

Not in a preset: behaviour (autohide, clicks, tooltips, urgency), placement
and monitors, the global Hyprland blur size (`blurSize`, `systemBlurSize`),
`showAppsButton`, `showRemovableDrives`, and content (pins, folders, groups).

## Storage

- `presets` array in `~/.config/omarchy/omadock.json`, written only through
  the existing `saveConfig`. No new files, no new processes.
- At most **6** presets. Names are trimmed, control characters removed,
  capped at 40 characters, and must not be empty. `id` is `"preset_" +
  Date.now()` (bounded like group ids).
- On load, `DockModel.boundPresets(list)` keeps at most 6 entries with a
  valid id and name and an object `look`; anything else is dropped. The
  `look` object is passed through `DockModel.pickLook` so unknown keys are
  dropped. Values are not trusted: they are only ever applied through the
  same parsing as the config (below).

## Code structure

- **`DockModel.js`** (pure, testable in node):
  - `LOOK_KEYS`: the list above.
  - `pickLook(conf)`: an object with exactly `LOOK_KEYS` from a config-shaped
    object, filling `iconSize: 0` and `cornerRadius: -1` when absent.
  - `lookEquals(a, b)`: true when every `LOOK_KEYS` value is equal
    (`JSON.stringify` per key).
  - `boundPresets(list)`, `cleanPresetName(s)`, `MAX_PRESETS = 6`,
    `MAX_PRESET_NAME = 40`.
- **`Dock.qml`**:
  - Split the look part out of `loadConfig` into `applyLook(parsed)`; it
    holds the existing per-key parsing unchanged, plus `cornerRadius: -1`
    accepted as "follow the shape", then `applyBlurRule(false)`. The
    divider migration (theme dividers without a border) stays inside it.
    `loadConfig` calls it with the parsed file, so there is one validation
    path.
  - Split the config-building part of `saveConfig` into
    `buildConfig(base)`, which writes the dock's properties onto `base` and
    returns it without reading anything. `saveConfig` passes the parsed
    file (as today); `currentLook()` = `pickLook(buildConfig({}))`, so the
    ✓ binding depends on properties only and never reads the file.
  - `property var presets: []`, loaded with `boundPresets`, saved by
    `saveConfig` as `conf.presets`.
  - `readonly property string activePresetId`: the id of the first preset
    whose look equals `currentLook()`, or `""`.
  - `savePreset(name)`, `renamePreset(id, name)`, `updatePreset(id)`,
    `deletePreset(id)`, `applyPreset(id)`.
  - `applyPreset(id)`: `applyLook(Object.assign(currentLook(), preset.look))`
    (keys missing from an older preset keep their current value), then one
    `saveConfig()`.
- **`components/PresetThumb.qml`**: the thumbnail (below).
- **`components/SettingsPanel.qml`**: the Presets page and sidebar entry.
- **`components/DockContextMenu.qml`**: the Presets page in the dock menu.
- **`DockHost.qml`**: IPC `applyPreset(name: string): string`.

## Settings → Presets

A sidebar entry "Presets" between Size & Spacing and Folders.

- Header line: "Presets" and "N of 6".
- One row per preset: thumbnail, name, a ✓ when it is the active preset,
  and actions **Apply**, **Update**, **⋯**.
  - Clicking the name edits it in place (`TextField`, as on the App Groups
    page): Enter saves, Esc cancels, losing focus cancels.
  - Apply applies the preset; the panel stays open so the dock beneath
    previews it.
  - Update overwrites the preset with the current look (no confirmation;
    the thumbnail changes at once).
  - ⋯ shows "Delete?" in the row, then "Yes"/"No"; no separate dialog.
- **Save current look** button below the list: creates "Preset N" (lowest
  free N) and opens its name for editing. Disabled at 6 presets, with the
  hint "6 of 6 — delete one to save a new look".
- Empty state: one line explaining presets, and the Save button.
- Names render with `textFormat: Text.PlainText`.

## Dock right-click menu

In the `__dock_settings__` menu, after "Dock Settings…": **Presets ›**, shown
only when at least one preset exists. It opens a page inside the menu (as
the folder menu's "View As ›" does):

- "‹ Back"
- one row per preset, ✓ on the active one; clicking applies it and closes
  the menu
- divider, "Manage Presets…" (opens Settings on the Presets page)

## Thumbnail (`PresetThumb.qml`)

About 160×40 px, drawn live from a `look` object; no images, no files.

- Backdrop: a small two-colour field from the current theme, so opacity and
  a missing background are visible.
- Dock body: shape and corner radius as the dock computes them for that
  height; solid or gradient fill (the gradient through the existing
  `shaders/gradient.frag.qsb`, with the preset's palette and strength), at
  the preset's opacity; border at its width and opacity; a soft shadow when
  on; split sections drawn as separate panels.
- Content: six placeholder icons in three sections (3, 2, 1) separated by
  dividers in the preset's style, height and width. Icons are small rounded
  tiles: theme accent and palette colours for `original`, the tint colour
  for `mono` and `dots`, a coarse block pattern for `pixel`. Indicator dots
  under two of them, in the preset's indicator shape.
- Theme-dependent colours (theme background, text, accent) use the current
  Omarchy theme, as the dock would after applying.

The thumbnail shows the character of a look, not an exact copy.

## IPC

`omarchy-shell omadock applyPreset "<name>"`:

- the argument is coerced with `String()`, trimmed and capped at 40
  characters;
- matched against preset names exactly, ignoring case;
- applies through `applyPreset(id)`, so it can set nothing a preset cannot
  hold;
- returns `"ok"` or `"not found"`.

## Security notes

- No new processes, files or network access; the only write is the
  existing `saveConfig`.
- Preset values reach the dock only through `applyLook`, the same parsing
  as the config file, so a hand-edited preset is clamped and allow-listed
  like any config value.
- Bounded counts and lengths (6 presets, 40-character names, `pickLook`
  dropping unknown keys); names rendered as plain text in every sink.
- The IPC method takes one bounded string and only triggers the normal,
  non-destructive apply.

## Testing

- node check of `pickLook`, `lookEquals`, `boundPresets` and
  `cleanPresetName` on sample data (as done for `ungroupRow`).
- Smoke test after restart; the log stays clean.
- Screenshots: the Presets page via `openSettingsPage presets` with a few
  presets written into the config (backed up and restored), and the
  thumbnails for solid, gradient, transparent, split, pixel and dots looks.
- IPC: `applyPreset` with an existing name, a different case, an unknown
  name and an over-long string.
- The user tests clicking: save, rename, update, delete, the menu page.

## Delivery

Branch `feat/presets` from `upstream/main`, merged into `priard` for
testing, then one PR. This spec stays on `priard` only.

## Future

Assign a preset to an Omarchy theme, so a theme change (by hand, or
automatic through a plugin such as the user's Before Sunset) switches the
dock's look. Announced to the author in PR #16; not designed yet.
